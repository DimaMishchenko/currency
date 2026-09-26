#!/bin/bash
set -euo pipefail

# Event runs use their own build. Scheduled/manual runs find the latest actual
# release, ignoring successful no-op runs and expired artifacts.
page=1
while :; do
  if [[ -n "${RELEASE_RUN_ID:-}" ]]; then
    run_ids=$RELEASE_RUN_ID
  else
    run_ids=$(gh api --method GET "repos/$GH_REPO/actions/workflows/publish.yml/runs" \
      -f branch=main -f status=success -f event=workflow_run -F per_page=100 -F page="$page" \
      --jq '.workflow_runs[].id')
  fi
  [[ -n "$run_ids" ]] || break
  while IFS= read -r run_id; do
    artifact=$(gh api "repos/$GH_REPO/actions/runs/$run_id/artifacts" \
      --jq 'any(.artifacts[]; .name == "currency-release-build" and .expired == false)')
    if [[ "$artifact" == true ]]; then
      printf 'run_id=%s\n' "$run_id" >> "$GITHUB_OUTPUT"
      exit 0
    fi
  done <<< "$run_ids"
  [[ -z "${RELEASE_RUN_ID:-}" ]] || break
  page=$((page + 1))
done
echo 'No published build is available for this run; skipping public beta promotion.' >> "$GITHUB_STEP_SUMMARY"
