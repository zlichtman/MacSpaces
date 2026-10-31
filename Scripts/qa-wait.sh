#!/bin/bash
# Waits for a GitHub Actions run and prints its conclusion; exits 0 only on success.
# Works from any folder (the repo is named, never inferred) and rides out passing API errors,
# which `gh run watch` treats as the end of the run. Usage: Scripts/qa-wait.sh <run id>
set -uo pipefail
repo=zlichtman/MacSpaces
run=${1:?usage: qa-wait.sh <run id>}
until state=$(gh api "repos/$repo/actions/runs/$run" --jq '"\(.status) \(.conclusion)"' 2>/dev/null) && [[ "$state" == completed* ]]; do
  sleep 30
done
echo "run $run: ${state#completed }"
[[ "$state" == "completed success" ]]
