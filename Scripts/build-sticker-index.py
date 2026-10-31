#!/usr/bin/env python3
"""Builds Sources/Resources/sticker-index.json, the Scenes lyric style's catalog of
Microsoft's Fluent Emoji (MIT): each emoji's name, keywords and the paths of its 3D
still and (when Microsoft made one) its animation, which MacSpaces downloads on demand.

Usage: build-sticker-index.py <fluentui-emoji checkout with assets/*/metadata.json>
       <static-paths.txt> <animated-paths.txt> <output.json>
The path lists are `git ls-tree` style paths from microsoft/fluentui-emoji (the /3D/
files) and microsoft/fluentui-emoji-animated."""
import json, os, re, sys

checkout, static_list, animated_list, output = sys.argv[1:5]
statics = [line.strip() for line in open(static_list) if line.strip()]
animated = [line.strip() for line in open(animated_list) if line.strip()]
# Flags, letters, arrows and other signs aren't things a lyric shows.
skipped_groups = {"Flags", "Symbols", "Component"}

def first(paths, folder, kind):
    # Prefer the default (no skin tone) file, then any.
    prefix = f"assets/{folder}/"
    candidates = [p for p in paths if p.startswith(prefix) and f"/{kind}/" in p]
    default = [p for p in candidates if f"/Default/{kind}/" in p]
    return (default or sorted(candidates) or [None])[0]

entries = []
for folder in sorted(os.listdir(os.path.join(checkout, "assets"))):
    path = os.path.join(checkout, "assets", folder, "metadata.json")
    if not os.path.exists(path):
        continue
    meta = json.load(open(path))
    if meta.get("group") in skipped_groups:
        continue
    still = first(statics, folder, "3D")
    if not still:
        continue
    words = set()
    for phrase in [meta.get("cldr", ""), meta.get("tts", ""), folder] + meta.get("keywords", []):
        for word in re.split(r"[^a-z0-9']+", phrase.lower()):
            if len(word) >= 3:
                words.add(word)
    entry = {"n": folder, "u": meta.get("unicode", ""), "g": meta.get("group", ""),
             "k": sorted(words), "s": still[len("assets/"):]}
    moving = first(animated, folder, "animated")
    if moving:
        entry["a"] = moving[len("assets/"):]
    entries.append(entry)

json.dump({"source": "https://github.com/microsoft/fluentui-emoji (MIT)",
           "still": "https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/assets/",
           "animated": "https://media.githubusercontent.com/media/microsoft/fluentui-emoji-animated/main/assets/",
           "emoji": entries}, open(output, "w"), ensure_ascii=False, separators=(",", ":"))
print(f"{len(entries)} emoji, {sum('a' in e for e in entries)} animated -> {output}")
