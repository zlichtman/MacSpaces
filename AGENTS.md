# MacSpaces agent rules

Read [docs/ENGINEERING.md](docs/ENGINEERING.md) for the code layout, how each feature works, the
build and release steps, and the checks. The [README](README.md) is the public page.

## Keeping the docs current

- docs/ENGINEERING.md describes the current state only. When something changes, edit its section in
  the present tense. The history goes in `CHANGELOG.md` (one entry per version), which is
  kept on this Mac only: it's gitignored and never published. Never an "X.Y:" paragraph in the guide. Don't repeat the version or build anywhere but `project.yml` and
  `RELEASE_NOTES.md`.
- Update the README's feature text with every release. Its Requirements list the lowest macOS and
  every feature that needs a newer one (from the `#available` checks); its Privacy section lists
  every network service, so add one there when a feature starts using it.
- No line breaks in the README or site captions: every caption and bullet fits on one line (a
  Pages caption is about 35 characters with its bold name). Shorten the words rather than wrap.
- Record site and README demos on the owner's Mac with `Scripts/capture-demos.sh` (how to run it is in
  docs/ENGINEERING.md): it draws the real glass, scenes and shaders. GitHub runner renders can't, so
  use them only for checks, never for published pictures.
- README images live in `Demos/screenshots`, use real songs, are the website's captures
  converted with `cwebp -q 84 -m 6`, and sit in HTML `<img width="49%">` rows (no Markdown tables
  with empty headers). Every file there must be referenced by the README. Videos stay on the
  website, never in the repo.
- Add a `SettingsSearch.entries` entry for every new Settings card. New `NookWidgetKind` cases need a
  title, symbol and sizing, and `libraryGroups` must list every widget.

## Code

- macOS 13 is the deployment target and the build is universal. Anything newer needs `#available`
  with a fallback (shared stand-ins go in `OlderMacOS.swift`). The current release must keep running
  on macOS 13, because 1.14's updater can't check the minimum macOS.
- Use explicit captures in nested actor closures (the CI compiler requires it), and
  `OSAllocatedUnfairLock`, not `NSLock`, for locks used from async code.
- Animate with `.periodic` TimelineViews, never `.animation` schedules (they pause while macOS
  reports the panel hidden). No `rotation3DEffect` spins; scale x instead. Schedule timers in
  `.common` run-loop modes. All motion honours Reduce Motion, the system's or the app's own.
- An update never changes a user's settings. A new option defaults to the existing behaviour, a
  removed or renamed setting migrates to an identical result, and a changed default applies only to
  new installs (existing ones get what they had). Nothing is added to a saved dock or Home on its
  own. Record each change in `Scripts/settings-changes.tsv`; `check-settings-compat` enforces it.
- Keep heavy work (statistics, scans, thumbnails, artwork, camera and device discovery) off the main
  thread on bounded workers, and drop results from cancelled or superseded requests.
- SwiftTerm is the only package; every `xcodebuild` passes `-skipPackagePluginValidation`. Keep the
  bundle identifier `dev.opensource.MacSpaces` stable. Shared keys go in `WidgetOptions.Keys`, never
  repeated as strings.
- UI copy: no ellipses in the menu-bar menu, and Settings shows only the version (the build appears
  on hover).

## Privacy and safety

- Opening a page, a widget or Settings requests no permission. Each permission is asked only from an
  explicit action (an Allow button, Mirror's camera button, voice mode, turning a feature on).
  Hover warming never asks for Location.
- Network use is limited to what a feature needs, from the services listed in README Privacy.
- Every `sqlite3_open` is `SQLITE_OPEN_READONLY`; the only other app's store MacSpaces reads is
  Maccy's.
- Clipboard history never keeps concealed or transient types or text shaped like a credential.
- Meetings uses a closed set of actions and never runs user JavaScript; it refuses unknown or
  ambiguous states.
- The power helper's XPC contract is exactly four argument-free calls with fixed `pmset` arguments:
  no shells, no sudoers, and the helper and app each check the other's signing team.
- The Tray and baskets hold references: removing an item never touches the file. File Tools never
  edit an original.

## Building, checking and releasing

- Demo songs are the owner's own picks, already set up and matched to themes in the demo fixtures (the original Music reel's songs: Generationals, Phantogram, Suki Waterhouse, Fog Lake, Blue and the rest). Never swap in other songs, and never children's or novelty songs; to change one, ask him.

- CI must pass on the exact commit being released; a passing local build is not enough.
- Run `Scripts/preflight.sh` before pushing any branch or dispatching CI or Feature QA, and push
  only once it passes: it compiles the harness and runs the check scripts in a few minutes, so
  GitHub's Macs are never used to find compile errors.
- Feature QA runs only when dispatched (`gh workflow run feature-qa.yml --ref qa/<name> -f scopes=…`):
  put every scope and clip you need in one dispatch; a push starts nothing, so nothing needs
  cancelling. When done with the branch, `Scripts/qa-clean.sh qa/<name>` deletes it and all its runs.
- Wait for a run with `Scripts/qa-wait.sh <run id>` (it names the repo, so it works from any folder, and rides out API errors), never a bare `gh run watch`. Pass `--repo zlichtman/MacSpaces` to every other `gh` call.
- A new harness assertion first reports what it measures; make it fatal only once a run shows the
  real value. Timing budgets stay in Feature QA: release CI gates only checks that give the same
  answer on every run.
- Debug harnesses run only under their own bundle identifiers, with isolated preferences and
  synthetic data. Captures never read the real Shortcuts list, and demo covers are never committed.
- Before shipping visual changes, inspect Settings and the Midnight and Everforest scenes.
- The agent bubble and the teleprompter are hidden from screenshots, recordings and screen sharing on purpose (`sharingType = .none`), and the hardware notch never appears in a screenshot. So the owner's screenshots won't show them, and nothing captured from the screen will either: judge them from Feature QA's own renders, and ask for a phone photo when the real notch matters (for example during a Space swipe).
- Release in batches: ship once a set of finished work is ready, not after every merge. `ship.sh` runs preflight itself and publishes without waiting for CI (`SHIP_WAIT_CI=1` waits); if CI then fails on the released commit, fix it in the next release.
- Ship only with `Scripts/ship.sh`, and only once the owner approves the release. Bump `project.yml`
  and `RELEASE_NOTES.md` (current version only, named in bold) and add the local `CHANGELOG.md` entry first.
  `CFBundleVersion` must exceed every published build.
- `main` is a single root commit, `MacSpaces X.Y`. No recovery bundles, backup branches or spare app
  copies. Docs-only updates go through `Scripts/publish-docs.sh`, which publishes only `README.md`,
  `AGENTS.md`, `Demos/` and `docs/`; anything else ships with the next release.
- Never delete `downloads.tsv`: it's the only record of deleted releases' download counts.
- `zlichtman/tap/macspaces` is the only cask; run `brew style --cask` before pushing the tap.
- Never commit credentials, generated projects or release artifacts.
