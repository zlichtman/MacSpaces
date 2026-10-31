#!/bin/bash
# The shell every workflow step runs in (`defaults.run.shell` in ci.yml and feature-qa.yml).
# It runs the step as GitHub's own bash does (-eo pipefail), keeps its output, and when the
# step fails writes one line saying why to the run's summary and as an error annotation, so
# `gh run view <id>` names the cause without the logs.
#
#   bash Scripts/ci-step.sh <step script>   run a step (GitHub passes the script as {0})
#   Scripts/ci-step.sh --cause <log>        print a log's one-line cause
#
# A step that writes its own summary lines (Feature QA's scopes) sets STEP_SUMMARY=self.
set -uo pipefail

# The first compiler error (with the count), else the first Swift runtime trap with what it
# printed after a trailing colon, else a timeout, else the last line of output.
cause() {
  python3 - "$1" <<'PY'
import re, sys
lines = [l.rstrip("\n") for l in open(sys.argv[1], errors="replace")]
# Runner log prefixes and the workspace path add nothing.
clean = [re.sub(r"^.*?/work/[^/]+/[^/]+/", "", re.sub(r"\x1b\[[0-9;]*m", "", l)).strip() for l in lines]
errors = [l for l in clean if re.search(r":\d+:\d+: error: ", l)]
if errors:
    seen = list(dict.fromkeys(errors))
    more = f" (+{len(seen) - 1} more)" if len(seen) > 1 else ""
    print(seen[0] + more); sys.exit()
for i, l in enumerate(clean):
    m = re.search(r"(Fatal error|Precondition failed|Assertion failed)(: .*)?$", l)
    if not m:
        continue
    text = re.sub(r"^.*?(\w+\.swift:\d+: )", r"\1", l)
    if text.endswith(":"):
        rest = []
        for d in clean[i + 1:]:
            if not d or "Trace/BPT" in d or d.startswith("/") or d.startswith("##["):
                break
            rest.append(d)
        text += " " + "; ".join(rest[:3]) + (f" (+{len(rest) - 3} more)" if len(rest) > 3 else "")
    print(text); sys.exit()
if any("Alarm clock" in l for l in clean):
    print("Timed out (the harness never quit)"); sys.exit()
for l in reversed(clean):
    if l and not l.startswith("##[") and not l.startswith("::"):
        print(l[:300]); sys.exit()
print("Failed with no output")
PY
}

if [ "${1:-}" = "--cause" ]; then
  cause "$2"
  exit 0
fi

script=$1
log=$(mktemp "${RUNNER_TEMP:-/tmp}/step.XXXXXX")
bash --noprofile --norc -eo pipefail "$script" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

if [ "$status" != 0 ] && [ "${STEP_SUMMARY:-}" != "self" ]; then
  # Name the step by its first command: a check script's name, xcodebuild, or the line.
  first=$(grep -vE '^[[:space:]]*(#|$)' "$script" | head -1 | sed -E 's/^[[:space:]]+//')
  case "$first" in
    *Scripts/*.sh*) label=$(grep -oE 'Scripts/[A-Za-z0-9_-]+\.sh' <<< "$first" | head -1) ;;
    xcodebuild*) label=xcodebuild ;;
    *) label=$(cut -c1-50 <<< "$first") ;;
  esac
  why=$(cause "$log")
  # Workflow-command escaping (the message only: `gh run view` shows no titles).
  esc() { local v=${1//%/%25}; v=${v//$'\r'/%0D}; echo "${v//$'\n'/%0A}"; }
  echo "::error::$(esc "$label: $why")"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf -- '- **Failed** `%s`: %s\n' "$label" "${why//|/\\|}" >> "$GITHUB_STEP_SUMMARY"
  fi
fi
rm -f "$log"
exit "$status"
