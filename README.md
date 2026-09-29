# Azure VNet Terraform Template

Creates an Azure resource group and a virtual network in it. That is the whole
stack — it is deliberately minimal so the CI/CD and resource-group-lock flow
around it can be exercised without a deploy failing for unrelated reasons.

## Prerequisites

- Terraform >= 1.5
- Azure CLI

```powershell
az login
az account set --subscription <subscription-id>
```

Copy the example variables file and fill in your subscription ID:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
```

State lives in an Azure Blob Storage backend (partial config), so `init` needs
the backend details — see [Remote state backend](#remote-state-backend):

```powershell
terraform init `
  -backend-config="resource_group_name=tfstate-rg" `
  -backend-config="storage_account_name=<uniquestorageacct>" `
  -backend-config="container_name=tfstate" `
  -backend-config="key=hub-gec.tfstate"
terraform plan
terraform apply
```

## Resource group lock

The resource group can carry an Azure management lock. The lock is **not**
managed by Terraform on purpose: if it lived in state and CI deleted it to get
an apply through, state would immediately disagree with reality and every
subsequent plan would want to recreate it. A guardrail should sit outside the
thing it guards.

Create it once, by hand or via the reconcile workflow:

```bash
az lock create --name rg-terraform-vnet-lock \
  --resource-group rg-terraform-vnet \
  --lock-type CanNotDelete \
  --notes "Guardrail; lifted automatically by CI only for destructive applies"
```

### When CI lifts it

`.github/scripts/rg-lock.sh` compares the live lock against the saved plan JSON
and lifts the lock only when the plan genuinely cannot proceed without it:

| Lock | Plan contents | Lock lifted? |
| --- | --- | --- |
| none | anything | no |
| `CanNotDelete` | only creates / updates / no-ops | **no** |
| `CanNotDelete` | any delete or replace | yes |
| `ReadOnly` | all no-ops | **no** |
| `ReadOnly` | any change at all | yes |

`CanNotDelete` only blocks deletes, so routine applies that add or modify
resources run with the lock still on. Replaces count as deletes — Terraform
reports them as `["delete","create"]` in the plan JSON, so they are caught.

`ReadOnly` is far more disruptive than it sounds: it blocks every control-plane
write, including things that feel read-only (listing storage account keys, VM
start/stop, editing a Key Vault's network ACLs). `CanNotDelete` is the
recommended level here.

Note that locks are an ARM control-plane mechanism. They do not touch the data
plane — blob contents and Key Vault secrets stay writable under either level,
and the Terraform state blob lease is unaffected.

### Who can lift it

Managing locks needs `Microsoft.Authorization/locks/*`, which **Contributor does
not have**. Grant the CI service principal either `User Access Administrator`
scoped to the resource group, or a custom role with just the lock permissions:

```bash
az role assignment create \
  --assignee <ARM_CLIENT_ID> \
  --role "User Access Administrator" \
  --scope /subscriptions/<sub>/resourceGroups/rg-terraform-vnet
```

Worth deciding deliberately: a pipeline that can remove its own lock is
protected against *accidents*, not against *a bad pipeline*. If you want the
lock to stop CI too, withhold the permission and lift it manually.

### Drift recovery

The apply restores the lock in an `always()` step, but that cannot run if the
runner is killed outright. `tf-lock-reconcile.yml` runs daily, re-asserts the
lock declared by `RG_LOCK_LEVEL` / `RG_LOCK_NAME`, and opens an issue labelled
`tf-lock-drift` when it had to. It shares the apply workflow's concurrency group
so it can never fire while an apply has the lock deliberately lifted.

## CI/CD (GitHub Actions)

| Workflow | Trigger | Behaviour |
| --- | --- | --- |
| `tf-plan.yml` | Push to **any** branch | Runs `terraform plan`, publishes it to the run **Summary**, saves the output as `plan-<sha>`. If the branch has an open PR, updates its sticky comment. |
| `tf-plan.yml` | PR to `main` (opened/reopened) | **Reuses** the saved plan for the PR's head commit if the code is unchanged; otherwise plans fresh. Posts a sticky PR comment. |
| `tf-plan.yml` | Push to `main`, or manual | Plans, saves `tfplan` + `tfplan.json`, reports the lock verdict, opens an approval **issue**. |
| `tf-apply-run.yml` | Comment on the approval issue | On an authorized `/approve`, lifts the lock if the plan needs it, applies, restores the lock, closes the issue. `/deny` closes without applying. |
| `tf-lock-reconcile.yml` | Daily cron, or manual | Re-asserts the declared RG lock and reports drift. |

A lock never blocks `terraform plan` — reading ARM is permitted under both
levels — so the plan job only *reports* the verdict. The apply job recomputes it
from scratch rather than trusting the plan run, because the lock may change
while the approval issue waits.

### Plan reuse (avoid duplicate planning)

The plan workflow identifies "same code" by **commit SHA**:

- Every branch push saves its plan output as an artifact named `plan-<sha>`.
- When a PR is opened for that same commit, a lightweight `check` job finds the
  saved `plan-<sha>` and a `reuse` job posts it as the PR comment — **no second
  `terraform plan`**. If no saved plan is found (e.g. the artifact expired), it
  falls back to planning fresh.
- `synchronize` is intentionally not a PR trigger: pushing to a PR branch is
  handled by the push run (which also updates the PR comment), so the same code
  is never planned twice.

Reused plans are **previews**. The plan that actually gets applied is always
regenerated fresh at merge to `main` (and saved as `tfplan`).

### Issue-based approval (ChatOps)

Deployment is gated by an issue-based approval that uses only first-party
actions (works under org policies that block third-party actions):

1. **On a PR to `main`**, the plan runs and is posted as a comment on the PR.
2. **When code lands on `main`**, the plan runs and opens an issue (labelled
   `tf-apply-approval`) containing the plan and the lock verdict.
3. A reviewer comments **`/approve`** on that issue, which applies and closes it.
   **`/deny`** closes it without applying.

Only users with write access (`author_association` of `OWNER`, `MEMBER`, or
`COLLABORATOR`) can approve.

> The apply applies the **exact plan** you reviewed. If the state drifted since
> the plan was created, Terraform rejects the stale plan (safe by design) —
> re-run the plan to produce a fresh approval issue.

### Required secrets

Settings → Secrets and variables → Actions → **Secrets**:

| Secret | Purpose |
| --- | --- |
| `ARM_CLIENT_ID` | Service principal app ID |
| `ARM_CLIENT_SECRET` | Service principal secret |
| `ARM_TENANT_ID` | Azure AD tenant ID |
| `ARM_SUBSCRIPTION_ID` | Target subscription ID |

### Required variables

Same page → **Variables** tab:

| Variable | Purpose |
| --- | --- |
| `TFSTATE_RESOURCE_GROUP` | Resource group holding the state storage account |
| `TFSTATE_STORAGE_ACCOUNT` | Storage account name for remote state |
| `TFSTATE_CONTAINER` | Blob container name for remote state |
| `RESOURCE_GROUP_NAME` | RG this stack manages — used both as `TF_VAR_resource_group_name` and as the lock target. Must match `resource_group_name` in your tfvars. |
| `VNET_NAME` | Name of the virtual network (`TF_VAR_vnet_name`) |
| `RG_LOCK_LEVEL` | Declared lock level: `None`, `CanNotDelete`, or `ReadOnly` |
| `RG_LOCK_NAME` | Name of the declared lock, e.g. `rg-terraform-vnet-lock` |

## Remote state backend

State is stored in Azure Blob Storage via the `azurerm` backend, using partial
configuration. The storage account must exist **before** the first run —
Terraform cannot bootstrap its own backend:

```bash
az group create -n tfstate-rg -l eastus
az storage account create -n <uniquestorageacct> -g tfstate-rg --sku Standard_LRS
az storage container create -n tfstate --account-name <uniquestorageacct>
```

Grant the service principal **Storage Blob Data Contributor** on that storage
account.
