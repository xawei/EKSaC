#!/usr/bin/env bash
# delete-all-crossplane-managed.sh
# Deletes ALL Crossplane Managed Resources returned by `kubectl get managed`
# - Does NOT wait for deletion to complete
# - Ignores not-found errors
# Optional: set DRY_RUN=true to preview

set -o pipefail

DRY_RUN="${DRY_RUN:-false}"

# Build the kubectl delete command
delete_cmd=(kubectl delete --wait=false --ignore-not-found)
if [[ "$DRY_RUN" == "true" ]]; then
  delete_cmd+=(--dry-run=client)
fi

# Collect all MRs as resource/name lines
mapfile -t MRS < <(kubectl get managed -o name | sed '/^$/d')

if (( ${#MRS[@]} == 0 )); then
  echo "No managed resources found."
  exit 0
fi

echo "Deleting ${#MRS[@]} managed resources..."
# Delete in batches to avoid arg-length issues
printf '%s\n' "${MRS[@]}" | xargs -r -n 100 "${delete_cmd[@]}"