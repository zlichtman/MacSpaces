#!/usr/bin/env python3
"""Builds Sources/Resources/ghostty-themes.json from Ghostty's bundled themes.

Ghostty ships the iTerm2-Color-Schemes collection (MIT, Mark Badolato and contributors;
each theme's copyright stays with its author, credited in Acknowledgements.txt). This
reads the plain `key = value` theme files and writes one compact JSON array, one row per
theme: [name, background, foreground, accent, sixteen ANSI colours as one hex string].
The accent is worked out here, once (see `accent`), and the rows are written in Ghostty's
own order (alphabetical by name, ignoring case, as its theme list shows them), so families
like Gruvbox and Catppuccin stay together and the app sorts nothing.

    Scripts/build-ghostty-themes.py [themes-dir]

The default themes-dir is Ghostty.app's own folder; a checkout of
iTerm2-Color-Schemes/ghostty works too. Reads only; never launches Ghostty.
"""
import colorsys, json, os, sys

DEFAULT = "/Applications/Ghostty.app/Contents/Resources/ghostty/themes"
OUT = os.path.join(os.path.dirname(__file__), "..", "Sources", "Resources", "ghostty-themes.json")


def hexcolour(value):
    value = value.strip().lstrip("#").lower()
    if len(value) == 3:
        value = "".join(c * 2 for c in value)
    return value if len(value) == 6 and all(c in "0123456789abcdef" for c in value) else None


def luminance(hex6):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (int(hex6[i:i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def contrast(a, b):
    x, y = luminance(a), luminance(b)
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)


def accent(background, foreground, ansi):
    """The first colourful ANSI colour in this order that reads at 3:1 or better:
    blue, magenta, cyan, green, yellow, red (normal before bright, which is often paler)."""
    for index in (4, 12, 5, 13, 6, 14, 2, 10, 3, 11, 1, 9):
        colour = ansi[index]
        r, g, b = (int(colour[i:i + 2], 16) / 255 for i in (0, 2, 4))
        _, saturation, value = colorsys.rgb_to_hsv(r, g, b)
        if saturation >= 0.3 and value >= 0.35 and contrast(colour, background) >= 3:
            return colour
    return foreground


def parse(path):
    values, ansi = {}, [None] * 16
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if "=" not in line or line.lstrip().startswith("#"):
                continue
            key, value = (part.strip() for part in line.split("=", 1))
            if key == "palette" and "=" in value:
                index, colour = value.split("=", 1)
                if index.strip().isdigit() and int(index) < 16:
                    ansi[int(index)] = hexcolour(colour)
            else:
                values[key] = value
    background, foreground = hexcolour(values.get("background", "")), hexcolour(values.get("foreground", ""))
    if not background or not foreground or any(c is None for c in ansi):
        return None
    pick = accent(background, foreground, ansi)
    return [os.path.basename(path), background, foreground, pick, "".join(ansi)]


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    rows = []
    for name in sorted(os.listdir(folder), key=str.casefold):
        row = parse(os.path.join(folder, name))
        if row:
            rows.append(row)
    with open(OUT, "w", encoding="utf-8") as out:
        json.dump(rows, out, separators=(",", ":"), ensure_ascii=False)
    print(f"{len(rows)} themes, {os.path.getsize(OUT) / 1024:.0f} KB -> {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()
