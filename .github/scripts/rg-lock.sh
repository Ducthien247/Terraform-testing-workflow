#!/usr/bin/env bash
# Resource-group lock helper for the Terraform workflows.
#
#   status <plan.json>   Work out which RG the plan targets, inspect its
#                        RG-scope locks, and emit `rg`, `level` and
#                        `needs_unlock` to $GITHUB_OUTPUT.
#   unlock <rg>          Delete the locks recorded by `status`.
#   restore <rg>         Recreate them with their original name/level/notes.
#
# The RG name comes from the plan's own resolved variables rather than an
# Actions variable, so the lock can never target a different group than the
# apply does. `status` writes the locks it found to $LOCK_BACKUP so `restore`
# can rebuild them even if the apply failed partway through.
set -euo pipefail

LOCK_BACKUP="${LOCK_BACKUP:-/tmp/rg-locks.json}"

# Locks inherit downwards, so `az lock list -g` also returns locks placed on
# individual resources. Only the ones scoped to the RG itself matter here.
RG_SCOPE_RE='^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/Microsoft.Authorization/locks/[^/]+$'

emit() { [ -n "${GITHUB_OUTPUT:-}" ] && echo "$1" >> "$GITHUB_OUTPUT"; return 0; }

cmd=$1

case "$cmd" in
  status)
    plan_json=$2

    rg=$(jq -r '.variables.resource_group_name.value // empty' "$plan_json")
    if [ -z "$rg" ]; then
      echo "::error::Could not read resource_group_name from $plan_json." >&2
      exit 1
    fi

    if az group show --name "$rg" --output none 2>/dev/null; then
      az lock list --resource-group "$rg" --output json
    else
      echo '[]'   # first apply: the RG does not exist yet
    fi | jq -c --arg re "$RG_SCOPE_RE" '[ .[] | select(.id | test($re; "i")) ]' > "$LOCK_BACKUP"

    # Several locks can coexist on one scope; the most restrictive one wins.
    if   jq -e 'any(.[]; .level == "ReadOnly")'     "$LOCK_BACKUP" >/dev/null; then level=ReadOnly
    elif jq -e 'any(.[]; .level == "CanNotDelete")' "$LOCK_BACKUP" >/dev/null; then level=CanNotDelete
    else level=None
    fi

    # "read" entries are data sources, not infrastructure changes.
    changes=$(jq '[ .resource_changes[]? | select(
                     .change.actions != ["no-op"] and .change.actions != ["read"]) ] | length' "$plan_json")
    # Replaces show up as ["delete","create"] or ["create","delete"]; both are
    # caught by looking for "delete" anywhere in the action list.
    destroys=$(jq '[ .resource_changes[]? | select(
                     .change.actions | index("delete")) ] | length' "$plan_json")

    case "$level" in
      None)         needs_unlock=false ;;
      CanNotDelete) [ "$destroys" -gt 0 ] && needs_unlock=true || needs_unlock=false ;;
      ReadOnly)     [ "$changes"  -gt 0 ] && needs_unlock=true || needs_unlock=false ;;
    esac

    emit "rg=$rg"
    emit "level=$level"
    emit "needs_unlock=$needs_unlock"
    emit "changes=$changes"
    emit "destroys=$destroys"
    echo "rg=$rg lock=$level changes=$changes destroys=$destroys -> needs_unlock=$needs_unlock"
    ;;

  unlock)
    rg=$2
    jq -r '.[].name' "$LOCK_BACKUP" | while read -r name; do
      az lock delete --name "$name" --resource-group "$rg" --output none
      echo "::warning::Removed lock '$name' on '$rg' for this apply; it will be restored afterwards."
    done
    ;;

  restore)
    rg=$2
    [ -f "$LOCK_BACKUP" ] || exit 0
    jq -c '.[]' "$LOCK_BACKUP" | while read -r lock; do
      name=$(jq -r '.name'         <<<"$lock")
      lvl=$( jq -r '.level'        <<<"$lock")
      notes=$(jq -r '.notes // ""' <<<"$lock")
      # Idempotent: `az lock create` overwrites a lock of the same name, so a
      # re-run after a partial failure is safe.
      az lock create --name "$name" --resource-group "$rg" \
        --lock-type "$lvl" --notes "$notes" --output none
      echo "Restored lock '$name' ($lvl) on '$rg'."
    done
    ;;

  *)
    echo "unknown command: $cmd" >&2
    exit 1
    ;;
esac
