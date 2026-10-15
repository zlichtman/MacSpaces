#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import plistlib, re
from pathlib import Path
info = plistlib.loads(Path('Sources/Resources/Info.plist').read_bytes())
spec = Path('project.yml').read_text()
for key in ['CFBundleShortVersionString', 'CFBundleVersion']:
    match = re.search(rf'^\s*{key}: "([^"]+)"$', spec, re.M)
    assert match and match[1] == info[key], f'{key} differs between project.yml and Info.plist'
version = info['CFBundleShortVersionString']
build = info['CFBundleVersion']
assert build.isascii() and build.isdigit() and int(build) > 0, 'The internal build must be a positive integer'
# 2.x versions are major.build (2.32), so one number tells people exactly which
# installer they have. From 3.0 (owner) the version is a plain major.minor name and
# only the build has to keep rising; updaters compare builds, not names. 1.0.0
# predates the scheme.
if version != '1.0.0':
    assert re.fullmatch(r'[0-9]{1,3}\.[0-9]{1,5}', version), 'The public version must look like 3.0'
    if version.split('.')[0] == '2':
        assert version.split('.')[1] == build, f'A 2.x version must end in the build (2.{build})'
    else:
        assert int(version.split('.')[0]) >= 3, 'Versions after 2.x start at 3.0'
notes = Path('RELEASE_NOTES.md').read_text()
assert f'**{version}**' in notes, 'RELEASE_NOTES.md must name the current version'
print(f'Release policy passed: public version {version}, internal build {build}')
PY
