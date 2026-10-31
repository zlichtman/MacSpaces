#!/usr/bin/env python3
"""Resolve the approved demo songs once into a temporary, validated asset lock."""
import argparse, hashlib, json, pathlib, re, time, urllib.parse, urllib.request


def fetch(url, binary=False):
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "MacSpaces-Demo/1"})
            with urllib.request.urlopen(req, timeout=25) as response:
                data = response.read()
            return data if binary else json.loads(data)
        except Exception:
            if attempt == 2:
                raise
            time.sleep(2 * (attempt + 1))


def normal(text):
    return re.sub(r"[^a-z0-9]", "", text.lower())


def prepare(manifest, output):
    spec = json.loads(manifest.read_text())
    digest = hashlib.sha256(manifest.read_bytes()).hexdigest()
    output.mkdir(parents=True, exist_ok=True)
    lock = output / "tracks.json"
    if lock.exists():
        tracks = json.loads(lock.read_text())
        if (output / "manifest.sha256").exists() and (output / "manifest.sha256").read_text() == digest:
            if all(pathlib.Path(t["cover"]).exists() and hashlib.sha256(pathlib.Path(t["cover"]).read_bytes()).hexdigest() == t["coverSHA256"] for t in tracks.values()):
                print(f"Using validated music assets: {lock}")
                return
    tracks = {}
    for song in spec["songs"]:
        query = urllib.parse.urlencode({"term": song["artist"] + " " + song["title"], "entity": "song", "limit": 50, "country": "us"})
        results = fetch("https://itunes.apple.com/lookup?" + urllib.parse.urlencode({"id": song["trackId"], "country": "us"}))["results"]
        matches = [r for r in results if normal(r["artistName"]) == normal(song["artist"]) and normal(r["trackName"]) == normal(song["title"])]
        matches = [r for r in matches if normal(r["collectionName"]).startswith(normal(song["album"]))]
        if not matches:
            raise RuntimeError(f"No exact recording/album match for {song['key']}; refusing to substitute")
        result = sorted(matches, key=lambda r: r["trackId"])[0]
        art_url = result["artworkUrl100"].replace("100x100bb", "600x600bb")
        cover = output / (song["key"] + ".jpg")
        art = fetch(art_url, binary=True)
        if len(art) < 1000 or not (art.startswith(b"\xff\xd8") or art.startswith(b"\x89PNG")):
            raise RuntimeError(f"Invalid cover for {song['key']}")
        cover.write_bytes(art)
        # Editorial excerpts and playback positions are fixed in the approved manifest.
        # No live lyric service is needed to reproduce an already approved silent reel.
        at, end = song["lyricAt"], song["lyricEnd"]
        tracks[song["key"]] = dict(title=result["trackName"], artist=result["artistName"], album=result["collectionName"],
            duration=result["trackTimeMillis"] / 1000, cover=str(cover.resolve()), lyrics=[song["excerpt"]],
            lyricAt=at, lyricEnd=end, trackId=result["trackId"],
            artworkURL=art_url, coverSHA256=hashlib.sha256(art).hexdigest())
        print(f"Verified {song['key']}: {result['trackName']} / {result['collectionName']} at {at:.2f}s")
    tracks["home"] = tracks["modern-english"]
    tracks["everforest"] = tracks["fog-lake"]
    lock.write_text(json.dumps(tracks, indent=2) + "\n")
    (output / "manifest.sha256").write_text(digest)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()
    prepare(args.manifest, args.output)
