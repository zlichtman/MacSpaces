#!/bin/bash
# The privileged power helper: launchd plist, XPC contract and the limits on what it runs.
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
fail() { echo "check-power-helper: $*" >&2; exit 1; }

label=dev.opensource.MacSpaces.PowerHelper
plist=Helpers/PowerHelper/$label.plist
plutil -lint -s "$plist"
[[ "$(plutil -extract Label raw "$plist")" == "$label" ]] || fail "Label isn't $label"
[[ "$(plutil -extract BundleProgram raw "$plist")" == Contents/MacOS/MacSpacesPowerHelper ]] || fail 'BundleProgram'
[[ "$(/usr/libexec/PlistBuddy -c "Print :MachServices:$label" "$plist" 2>/dev/null)" == true ]] || fail 'MachServices'
[[ "$(plutil -extract AssociatedBundleIdentifiers.0 raw "$plist")" == dev.opensource.MacSpaces ]] || fail 'AssociatedBundleIdentifiers'
for key in Program ProgramArguments RunAtLoad KeepAlive; do
  plutil -extract "$key" raw "$plist" >/dev/null 2>&1 && fail "unexpected $key"
done

# Exactly four operations, no arguments from the client, and only pmset with fixed arguments.
protocol=Sources/Services/PowerHelperProtocol.swift
[[ $(grep -c '^    func ' "$protocol") == 4 ]] || fail 'the protocol must have exactly four methods'
for method in preventSleep allowSleep enableLowPowerMode disableLowPowerMode; do
  grep -q "func $method(withReply reply: @escaping (Int32) -> Void)" "$protocol" || fail "$method"
done
helper=Helpers/PowerHelper/main.swift
[[ $(grep -c 'Process()' "$helper") == 1 ]] || fail 'the helper may start one process'
grep -q 'URL(fileURLWithPath: "/usr/bin/pmset")' "$helper" || fail 'the helper must run /usr/bin/pmset'
# pmset's arguments come only from four literal lists.
[[ $(grep -c 'Self.pmset(' "$helper") == 4 ]] || fail 'pmset is called from exactly four operations'
[[ $(grep -cE 'Self\.pmset\(\["-a", "(disablesleep|lowpowermode)", "[01]"\]\)' "$helper") == 4 ]] || fail 'pmset arguments must be fixed'
grep -q 'process.arguments = arguments' "$helper" || fail 'pmset arguments'
grep -Eq 'osascript|/bin/(ba|z)?sh|NSAppleScript|system\(|popen' "$helper" && fail 'the helper must not run shells or scripts'
grep -q 'connection.setCodeSigningRequirement(PowerHelperXPC.clientRequirement)' "$helper" || fail 'clients must be checked'
grep -q 'identifier \\"\\(appBundleIdentifier)\\" and certificate leaf\[subject.OU\] = \\"\\(teamIdentifier)\\"' "$protocol" || fail 'client requirement'
grep -q 'teamIdentifier = "28LJG7MXT3"' "$protocol" || fail 'team identifier'

# QA/demo bundles never register or call the helper; no sudoers exceptions anywhere.
app=Sources/Services/LidClosedAwake.swift
for function in setEnabled installHelper removeHelper turnOffForQuit readHelperState callHelper; do
  awk -v f="$function" '$0 ~ "func " f "\\(" { found = 1 } found && /isMainBundle/ { ok = 1; exit } found && /^    }/ { exit } END { exit !ok }' "$app" \
    || fail "$function must check isMainBundle"
done
grep -rIlE '/etc/sudoers|sudoers\.d|visudo|NOPASSWD' Sources Helpers Scripts --exclude=check-power-helper.sh && fail 'no sudoers rules'

# The contract and helper compile on their own.
swiftc -parse-as-library -typecheck "$protocol" 2>&1
swiftc "$protocol" "$helper" -o "$check_dir/helper"
echo 'check-power-helper: OK'
