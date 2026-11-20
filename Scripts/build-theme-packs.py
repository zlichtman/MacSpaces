#!/usr/bin/env python3
"""Builds Sources/Resources/theme-packs.json: the Base16 and Gogh packs for the Terminal drawer.

One JSON object, {"Base16": [rows], "Gogh": [rows]}, each row as in ghostty-themes.json:
[name, background, foreground, accent, sixteen ANSI colours as one hex string]. Run it after
build-ghostty-themes.py: a theme whose name or colours match one already kept is left out, so a
pack only adds what's new, and so is one whose text wouldn't read at 4.5:1. Both packs are MIT
(Gogh is MIT or Apache); their notices are in Acknowledgements.txt.

    Scripts/build-theme-packs.py <tinted-theming/schemes checkout> <Gogh-Co/Gogh checkout>

Reads only.
"""
import glob, importlib.util, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location("build_ghostty_themes", os.path.join(HERE, "build-ghostty-themes.py"))
GHOSTTY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GHOSTTY)
RESOURCES = os.path.join(HERE, "..", "Sources", "Resources")
# How close, on average per colour channel out of 255, counts as the same theme.
SAME_THEME = 7
MIN_TEXT_CONTRAST = 4.5


def channels(hex6):
    return [int(hex6[i:i + 2], 16) for i in (0, 2, 4)]


def signature(row):
    return channels(row[1]), [channels(c) for c in [row[2]] + [row[4][i * 6:i * 6 + 6] for i in range(8)]]


def distance(a, b):
    if sum(abs(x - y) for x, y in zip(a[0], b[0])) > 18:
        return 999
    total = sum(abs(x - y) for x, y in zip(a[0], b[0]))
    for p, q in zip(a[1], b[1]):
        total += sum(abs(x - y) for x, y in zip(p, q))
    return total / (3 * (len(a[1]) + 1))


def normal(name):
    return re.sub(r"[^a-z0-9]", "", name.lower())


def row(name, background, foreground, ansi):
    if not background or not foreground or len(ansi) != 16 or any(c is None for c in ansi):
        return None
    if GHOSTTY.contrast(foreground, background) < MIN_TEXT_CONTRAST:
        return None
    return [name, background, foreground, GHOSTTY.accent(background, foreground, ansi), "".join(ansi)]


def base16(folder):
    rows = []
    for path in glob.glob(os.path.join(folder, "base16", "*.yaml")):
        text = open(path, encoding="utf-8", errors="replace").read()
        c = {m[1].lower(): GHOSTTY.hexcolour(m[2]) for m in re.finditer(r"(base[0-9A-Fa-f]{2}):\s*\"?(#?[0-9A-Fa-f]{6})", text)}
        name = re.search(r"(?m)^name:\s*\"?([^\"\n]+)", text)
        if not name or "base0f" not in c:
            continue
        order = ["00", "08", "0b", "0a", "0d", "0e", "0c", "05", "03", "08", "0b", "0a", "0d", "0e", "0c", "07"]
        rows.append(row(name[1].strip(), c.get("base00"), c.get("base05"), [c.get("base" + key) for key in order]))
    return [r for r in rows if r]


def gogh(folder):
    rows = []
    for path in glob.glob(os.path.join(folder, "themes", "*.yml")):
        text = open(path, encoding="utf-8", errors="replace").read()
        c = {m[1]: GHOSTTY.hexcolour(m[2]) for m in re.finditer(r"(color_\d\d|background|foreground):\s*[\"']?(#[0-9A-Fa-f]{3,8})", text)}
        name = re.search(r"(?m)^name:\s*[\"']?([^\"'\n]+)", text)
        if not name:
            continue
        rows.append(row(name[1].strip(), c.get("background"), c.get("foreground"),
                        [c.get("color_%02d" % i) for i in range(1, 17)]))
    return [r for r in rows if r]


def main():
    existing = json.load(open(os.path.join(RESOURCES, "ghostty-themes.json"), encoding="utf-8"))
    kept = [signature(r) for r in existing]
    names = {normal(r[0]) for r in existing}
    packs = {}
    for label, rows in (("Base16", base16(sys.argv[1])), ("Gogh", gogh(sys.argv[2]))):
        fresh = []
        for candidate in sorted(rows, key=lambda r: r[0].casefold()):
            mark = signature(candidate)
            if normal(candidate[0]) in names or any(distance(mark, other) < SAME_THEME for other in kept):
                continue
            fresh.append(candidate)
            kept.append(mark)
            names.add(normal(candidate[0]))
        packs[label] = fresh
        print(f"{label}: {len(fresh)} of {len(rows)}")
    out = os.path.join(RESOURCES, "theme-packs.json")
    with open(out, "w", encoding="utf-8") as handle:
        json.dump(packs, handle, separators=(",", ":"), ensure_ascii=False)
    print(f"{os.path.getsize(out) / 1024:.0f} KB -> {os.path.normpath(out)}")


if __name__ == "__main__":
    main()
