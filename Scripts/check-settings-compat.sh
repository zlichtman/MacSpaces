#!/bin/bash
# An update never changes a user's settings. Compares the settings this commit reads
# (UserDefaults keys, their defaults, and the raw values of the enums stored in them)
# with the last release's, from the newest vX.Y tag on origin, which ship.sh maintains.
# Every new key, removed key, changed default (including starting values such as
# `NotchTab.defaultDock`) or removed stored value must be listed for that
# release in Scripts/settings-changes.tsv with the migration that keeps users' choices.
#   Scripts/check-settings-compat.sh                 against the last release's tag
#   Scripts/check-settings-compat.sh --base <dir>    against a checkout's Sources (tests)
#   Scripts/check-settings-compat.sh --list          prints this commit's settings
#   Scripts/check-settings-compat.sh --self-test     checks the guard on the cases it exists for
set -euo pipefail
cd "$(dirname "$0")/.."

base_dir='' base_name='' list=0 head_dir=. ledger=Scripts/settings-changes.tsv
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base_dir=$2; base_name=${3:-$(basename "$2")}; shift 2; [ $# -gt 0 ] && [ "${1#--}" = "$1" ] && shift ;;
    --list) list=1; shift ;;
    --head) head_dir=$2; shift 2 ;;
    --ledger) ledger=$2; shift 2 ;;
    --self-test) exec "$0" --self-test-run ;;
    --self-test-run) self_test=1; shift ;;
    *) echo "usage: $0 [--base <dir> [<version>]] [--list]" >&2; exit 2 ;;
  esac
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [ "${self_test:-0}" = 1 ]; then
  # The guard itself: a fake last release and a fake commit, with the cases that knocked
  # users' settings in 3.29–3.34.
  mkdir -p "$work/old/Sources" "$work/new/Sources"
  cat > "$work/old/Sources/A.swift" <<'SWIFT'
enum NotchTab: String, Codable { case music, wisp, tray, messages }
extension NotchTab { static let defaultDock: [NotchTab] = [.wisp, .music, .tray] }
enum ThemeFamily: String { case macspaces, oneDark }
func load() {
    peek = defaults.object(forKey: "agentActivity.peekWhileWorking") as? Bool ?? true
    look = defaults.string(forKey: "notch.look").flatMap(Look.init(rawValue:)) ?? .solid
    family = defaults.string(forKey: "theme.family").flatMap(ThemeFamily.init(saved:))
    defaults.set(true, forKey: "wisp.dockButton")
    tab = NotchTab(rawValue: defaults.string(forKey: "dockApps") ?? "")
}
SWIFT
  cat > "$work/new/Sources/A.swift" <<'SWIFT'
enum NotchTab: String, Codable { case music, wisp, tray }
extension NotchTab { static let defaultDock: [NotchTab] = [.music, .tray] }
enum ThemeFamily: String { case macspaces, karma }
let replaced: [String: ThemeFamily] = ["oneDark": .karma]
func load() {
    peek = defaults.object(forKey: "agentActivity.peekWhileWorking") as? Bool ?? false
    look = defaults.string(forKey: "notch.look").flatMap(Look.init(rawValue:)) ?? .solid
    family = defaults.string(forKey: "theme.family").flatMap(ThemeFamily.init(saved:))
    defaults.set(true, forKey: "dock.wispPageWithdrawn")
    tab = NotchTab(rawValue: defaults.string(forKey: "dockApps") ?? "")
}
SWIFT
  : > "$work/empty.tsv"
  out=$("$0" --head "$work/new" --base "$work/old" 9.9 --ledger "$work/empty.tsv" 2>&1) && { echo "$out"; echo 'self-test: unrecorded changes passed' >&2; exit 1; }
  for want in 'MISSING  default agentActivity.peekWhileWorking' 'MISSING  default NotchTab.defaultDock' \
              'MISSING  removed wisp.dockButton' 'MISSING  new     dock.wispPageWithdrawn' 'MISSING  value   NotchTab.messages'; do
    grep -qF "$want" <<<"$out" || { echo "$out"; echo "self-test: expected '$want'" >&2; exit 1; }
  done
  for unwanted in notch.look ThemeFamily.oneDark; do
    if grep -qF "$unwanted" <<<"$out"; then echo "$out"; echo "self-test: flagged unchanged $unwanted" >&2; exit 1; fi
  done
  printf '9.9\t%s\t%s\tsee test\n' default agentActivity.peekWhileWorking default NotchTab.defaultDock removed wisp.dockButton \
    new dock.wispPageWithdrawn value NotchTab.messages > "$work/ledger.tsv"
  "$0" --head "$work/new" --base "$work/old" 9.9 --ledger "$work/ledger.tsv" >/dev/null \
    || { echo 'self-test: recorded changes still failed' >&2; exit 1; }
  echo 'Settings compatibility self-test passed'
  exit 0
fi
if [ "$list" = 0 ] && [ -z "$base_dir" ]; then
  "$0" --self-test >/dev/null || { "$0" --self-test; exit 1; }
  # The newest release tag on origin (ship.sh keeps only the current one).
  git fetch --quiet --force origin 'refs/tags/v*:refs/tags/v*' 2>/dev/null || true
  tag=$(git tag -l 'v[0-9]*.[0-9]*' | sort -V | tail -1)
  [ -n "$tag" ] || { echo 'check-settings-compat: no vX.Y release tag found (git fetch origin --tags)' >&2; exit 1; }
  mkdir -p "$work/base"
  git archive "$tag" Sources | tar -x -C "$work/base"
  base_dir=$work/base base_name=${tag#v}
fi

HEAD_DIR=$head_dir LEDGER=$ledger BASE_DIR=$base_dir BASE_NAME=$base_name LIST=$list python3 - <<'PY'
import os, re, sys
from pathlib import Path

def swift_files(root):
    # Debug harnesses run under their own bundle ids with isolated preferences.
    return [p for p in sorted(Path(root, 'Sources').rglob('*.swift')) if 'Debug' not in p.relative_to(root).parts]

def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    def strip(line):
        for m in re.finditer(r'//', line):
            if line[:m.start()].count('"') % 2 == 0: return line[:m.start()]
        return line
    return '\n'.join(strip(line) for line in text.splitlines())

def matching(text, start, open_ch, close_ch):
    depth = 0
    for i in range(start, len(text)):
        if text[i] == open_ch: depth += 1
        elif text[i] == close_ch:
            depth -= 1
            if depth == 0: return i
    return len(text)

def split_top(body):
    parts, depth, cur, quote = [], 0, '', False
    for ch in body:
        if ch == '"': quote = not quote
        if not quote:
            if ch in '([{': depth += 1
            elif ch in ')]}': depth -= 1
            elif ch == ',' and depth == 0:
                parts.append(cur); cur = ''; continue
        cur += ch
    if cur.strip(): parts.append(cur)
    return [p.strip() for p in parts if p.strip()]

def norm(expr):
    return re.sub(r'\s+', ' ', expr).strip().rstrip(',')

RECEIVER = r'(?:defaults|UserDefaults\.standard|\.standard)'
READ = r'(?:bool|integer|double|float|string|stringArray|array|data|object|dictionary|url)'

def manifest(root):
    files = {p: strip_comments(p.read_text()) for p in swift_files(root)}
    # String constants, so `Keys.dockApps` and "dockApps" are the same key.
    local, everywhere = {}, {}
    for path, text in files.items():
        for name, value in re.findall(r'\blet\s+(\w+)\s*(?::\s*String)?\s*=\s*"([^"\\]+)"', text):
            local.setdefault(path, {}).setdefault(name, set()).add(value)
            everywhere.setdefault(name, set()).add(value)
    def key_of(path, expr):
        expr = expr.strip()
        if re.fullmatch(r'"[^"\\]*"', expr): return expr[1:-1]
        if not re.fullmatch(r'[\w.]+', expr): return None   # built at run time ("clipboard." + key)
        name = expr.split('.')[-1]
        for table in (local.get(path, {}), everywhere):
            if len(table.get(name, ())) == 1: return next(iter(table[name]))
        return None
    keys, defaults = set(), {}
    def add_default(key, how, value):
        defaults.setdefault(key, set()).add(f'{how} {norm(value)}')
    for path, text in files.items():
        for m in re.finditer(r'forKey:\s*("[^"\\]*"|[\w.]+)', text):
            line_start = text.rfind('\n', 0, m.start()) + 1
            line = text[line_start:text.find('\n', m.end())]
            if not re.search(RECEIVER + r'\??\.' + r'(?:set|removeObject|' + READ + r')\(', line): continue
            key = key_of(path, m[1])
            if not key: continue
            keys.add(key)
            # A read's own fallback: `object(forKey: k) as? Bool ?? true`, `string(forKey: k) ... ?? .solid`.
            read = re.search(RECEIVER + r'\??\.' + r'(' + READ + r')\(forKey:\s*' + re.escape(m[1]) + r'\)(.*)$', line)
            if read:
                tail = read[2]
                fallback = re.search(r'\?\?\s*(\.?[\w."\[\]]+(?:\([^()]*\))?)', tail)
                if fallback and not fallback[1].startswith('""'):
                    # `X(rawValue: defaults.string(forKey: k) ?? "") ?? .poster`: the outer fallback.
                    add_default(key, 'fallback', fallback[1])
                elif fallback:
                    outer = re.search(r'\?\?\s*""\s*\)\s*\??[^?]*\?\?\s*(\.?[\w.]+)', tail)
                    if outer: add_default(key, 'fallback', outer[1])
        for m in re.finditer(r'register\(defaults:\s*\[', text):
            body = text[m.end():matching(text, m.end() - 1, '[', ']')]
            for entry in split_top(body):
                k, sep, v = entry.partition(':')
                key = key_of(path, k) if sep else None
                if key:
                    keys.add(key); add_default(key, 'registered', v)
        for m in re.finditer(r'@AppStorage\(\s*("[^"\\]*"|[\w.]+)[^)]*\)\s*(?:private\s+|public\s+)*var\s+\w+\s*(?::\s*[\w.?]+)?\s*=\s*([^\n]+)', text):
            key = key_of(path, m[1])
            if key:
                keys.add(key); add_default(key, 'appstorage', m[2])
    # Enums whose raw values are stored: read back with init(rawValue:) next to a key, or Codable.
    stored_enums = set()
    for text in files.values():
        for line in text.splitlines():
            if 'forKey' in line or 'AppStorage' in line or 'stringArray' in line:
                stored_enums.update(re.findall(r'([A-Z]\w*)(?:\.init)?\((?:rawValue|saved):', line))
                stored_enums.update(re.findall(r'flatMap\(([A-Z][\w.]*?)\.init\((?:rawValue|saved):', line))
        for t in re.findall(r'@AppStorage\([^)]*\)\s*(?:private\s+)?var\s+\w+\s*:\s*([\w.]+)\s*=', text):
            stored_enums.add(t)
    stored_enums = {n.split('.')[-1] for n in stored_enums}
    enums = {}
    for path, text in files.items():
        for m in re.finditer(r'\benum\s+(\w+)\s*:\s*([^{]*)\{', text):
            name, conformances = m[1], m[2]
            if not re.match(r'\s*String\b', conformances): continue
            if name not in stored_enums and 'Codable' not in conformances: continue
            body = text[m.end():matching(text, m.end() - 1, '{', '}')]
            depth, values = 0, set()
            for line in body.splitlines():
                stripped = line.strip()
                if depth == 0 and stripped.startswith('case ') and '(' not in stripped.split('=')[0]:
                    for item in split_top(stripped[5:]):
                        case, _, raw = item.partition('=')
                        raw = raw.strip()
                        values.add(raw[1:-1] if raw.startswith('"') else case.strip())
                depth += line.count('{') - line.count('}')
            enums.setdefault(name, []).append((path.relative_to(root).as_posix(), values))
    # Same-named enums (Prompter's Mode, a widget's Mode) are told apart by file.
    named = {}
    for name, found in enums.items():
        for where, values in found:
            named[name if len(found) == 1 else f'{name}@{Path(where).stem}'] = values
    # A retired value still mapped somewhere ("oneDark": .karma) is migrated, not lost.
    mapped = set()
    for text in files.values():
        mapped.update(re.findall(r'"([^"\\]+)"\s*:\s*\.\w', text))
    # Starting values that aren't stored but decide what a user gets: `NotchTab.defaultDock`,
    # `NookSettings.starterWidgets`. Changing one changes every install that never chose.
    for path, text in files.items():
        for m in re.finditer(r'static\s+(?:let|var)\s+((?:default|starter|legacy)\w*)\s*(?::\s*[^=\n]+)?=\s*', text):
            owner = re.findall(r'\b(?:enum|struct|class|extension)\s+(\w+)', text[:m.start()])
            end = matching(text, m.end(), '[', ']') + 1 if text[m.end():m.end() + 1] == '[' else text.find('\n', m.end())
            defaults[f'{owner[-1] if owner else path.stem}.{m[1]}'] = {f'starts as {norm(text[m.end():end])}'}
    return keys, defaults, named, mapped

head_keys, head_defaults, head_enums, head_mapped = manifest(os.environ['HEAD_DIR'])
if os.environ['LIST'] == '1':
    for key in sorted(head_keys):
        print(key, '|', '; '.join(sorted(head_defaults.get(key, ()))) or 'unregistered')
    for name in sorted(head_enums):
        print(f'enum {name}:', ', '.join(sorted(head_enums[name])))
    sys.exit(0)

base = os.environ['BASE_NAME']
base_keys, base_defaults, base_enums, _ = manifest(os.environ['BASE_DIR'])
changes = []
for key in sorted(base_keys - head_keys):
    changes.append(('removed', key, 'no longer read: a stored value would be ignored'))
for key in sorted(head_keys - base_keys):
    changes.append(('new', key, f"{'; '.join(sorted(head_defaults.get(key, ()))) or 'unregistered'}: its default must be the old behaviour"))
for key in sorted((base_keys & head_keys) | (base_defaults.keys() & head_defaults.keys() - base_keys - head_keys)):
    old, new = base_defaults.get(key, set()), head_defaults.get(key, set())
    if old != new:
        changes.append(('default', key, f"{'; '.join(sorted(old)) or 'unregistered'} -> {'; '.join(sorted(new)) or 'unregistered'}"))
for name in sorted(base_enums.keys() & head_enums.keys()):
    for value in sorted(base_enums[name] - head_enums[name] - head_mapped):
        changes.append(('value', f'{name}.{value}', 'a stored value this release no longer reads'))
for name in sorted(base_enums.keys() - head_enums.keys()):
    changes.append(('value', f'{name}.*', 'stored enum no longer found'))

KINDS = ('new', 'removed', 'default', 'value')
recorded = {}
ledger = Path(os.environ['LEDGER'])
for number, line in enumerate(ledger.read_text().splitlines(), 1):
    if not line.strip() or line.startswith('#'): continue
    fields = line.split('\t')
    assert len(fields) == 4 and all(f.strip() for f in fields), f'{ledger}:{number}: want release, kind, key, migration (tab-separated)'
    release, kind, key, how = fields
    assert kind in KINDS, f'{ledger}:{number}: kind is one of {", ".join(KINDS)}'
    recorded[(release, kind, key)] = how

missing = [c for c in changes if (base, c[0], c[1]) not in recorded]
for kind, key, detail in changes:
    mark = 'MISSING' if (kind, key, detail) in missing else 'recorded'
    print(f'  {mark:8} {kind:7} {key}: {detail[:160]}')
if missing:
    print(f'\ncheck-settings-compat: {len(missing)} change(s) since {base} have no recorded migration.', file=sys.stderr)
    print('An update never changes a user\'s settings: a new option defaults to the existing behaviour, a removed or',
          'renamed one migrates to an identical result, and a changed default applies only to new installs. Then add',
          f'"{base}<TAB>kind<TAB>key<TAB>how existing users keep what they had" to Scripts/settings-changes.tsv.',
          sep='\n', file=sys.stderr)
    sys.exit(1)
print(f'Settings compatibility passed against {base}: {len(head_keys)} keys, {len(head_enums)} stored enums, '
      f'{len(changes)} recorded change(s)')
PY
