#!/bin/bash
# Remove a qa/ branch and every Actions run on it (CI and Feature QA, failed, cancelled and
# running ones included), so the history keeps only main's release runs.
#
#   Scripts/qa-clean.sh qa/<name>                delete the runs, then the branch
#   Scripts/qa-clean.sh --keep-branch qa/<name>  delete the runs only
#
# It acts only on a branch named qa/…, and only on runs whose branch is exactly that one,
# so main's and the releases' runs are never touched.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=zlichtman/MacSpaces

keep=0
[ "${1:-}" = --keep-branch ] && { keep=1; shift; }
branch=${1:-}
if [[ ! "$branch" =~ ^qa/[A-Za-z0-9._/-]+$ || "$branch" == *..* ]]; then
  echo "usage: Scripts/qa-clean.sh [--keep-branch] qa/<name>  (only qa/ branches)" >&2
  exit 2
fi

runs() { # id and status of each run on exactly this branch
  gh run list -R "$repo" --branch "$branch" -L 1000 --json databaseId,headBranch,status \
    --jq ".[] | select(.headBranch == \"$branch\") | \"\(.databaseId) \(.status)\""
}

# A run that's still going can't be deleted: cancel it and wait for it to stop.
for _ in $(seq 30); do
  active=$(runs | awk '$2 != "completed" {print $1}')
  [ -z "$active" ] && break
  for id in $active; do gh run cancel -R "$repo" "$id" > /dev/null 2>&1 || true; done
  sleep 5
done

deleted=0
for id in $(runs | awk '$2 == "completed" {print $1}'); do
  # Belt and braces: look at the run itself before deleting it.
  [ "$(gh run view -R "$repo" "$id" --json headBranch --jq .headBranch)" = "$branch" ] || continue
  gh run delete -R "$repo" "$id" > /dev/null
  deleted=$((deleted + 1))
done
left=$(runs | wc -l | tr -d ' ')
echo "Deleted $deleted runs on $branch$([ "$left" = 0 ] || echo "; $left still there (running?)")"

if [ "$keep" = 0 ]; then
  if git ls-remote --exit-code --heads origin "$branch" > /dev/null; then
    git push -q origin --delete "$branch" && echo "Deleted origin/$branch"
  fi
  # The local branch too, unless a worktree has it checked out.
  if git show-ref -q --verify "refs/heads/$branch"; then
    git branch -q -D "$branch" 2> /dev/null && echo "Deleted local $branch" || echo "Kept local $branch (checked out in a worktree)"
  fi
  git fetch -q --prune origin 2> /dev/null || true
fi
