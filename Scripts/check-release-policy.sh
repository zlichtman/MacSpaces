#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(git rev-list --count HEAD)" != 1 ]]; then
  echo 'MacSpaces must have one root commit. Amend the existing snapshot; do not append or merge commits.' >&2
  exit 1
fi
python3 - <<'PY'
import plistlib, re
from pathlib import Path
info = plistlib.loads(Path('Sources/Resources/Info.plist').read_bytes())
spec = Path('project.yml').read_text()
for key in ['CFBundleShortVersionString', 'CFBundleVersion']:
    match = re.search(rf'^\s*{key}: "([^"]+)"$', spec, re.M)
    assert match and match[1] == info[key], f'{key} differs between project.yml and Info.plist'
assert info['CFBundleShortVersionString'] == '1.0.0', 'The public version must remain 1.0.0'
assert info['CFBundleVersion'].isascii() and info['CFBundleVersion'].isdigit() and int(info['CFBundleVersion']) > 0
print('Release policy passed: one commit, public version 1.0.0, matching internal build')
PY
