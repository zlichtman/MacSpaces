# MacSpaces demo material

`screenshots/` holds the README's images: the website's captures of the real app
(`LIFE/PROJECTS/PORTFOLIO/public/projects/macspaces/media`), rendered by the Debug demo
helpers with synthetic data and converted with `cwebp -q 84 -m 6`. Every one is referenced
by the README. Videos live on the website, not here.

Songs and cover art belong to their artists and are shown only to demonstrate the media
controls; lyrics are short excerpts.

Run `Scripts/capture-demos.sh` from the app checkout for automatically timed local captures.
Use `--music-only` for the original Music reel and its five settled stills, or `--check`
to verify prerequisites. The single-window recorder includes the native rendering effects
and excludes the pointer, audio and surrounding desktop. The output has a proof sheet,
PNG stills, an MP4 and capture provenance; local website and README copies are updated.
Nothing is published. The original song order, excerpts and themes live in
`music-sequence.json`; missing content stops the capture instead of substituting a song.

If capture stops, rerun with `Scripts/capture-demos.sh --retry --output <folder>`
using the folder printed by the command. It reuses the compiled app when its source
has not changed. `--clean --output <folder>` removes that run's retained temporary
build without deleting exported demos. A successful run cleans up automatically.
