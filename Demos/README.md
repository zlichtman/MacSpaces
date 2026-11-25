# Demo pictures

Every still zlichtman.com/macspaces has, in the site's order, one folder per section under `screenshots/`. Same files, same names as the site's, so either can be pulled from. Videos stay on the site. **README** marks the ones the README shows.

## Retaking the shots

Everything that makes these pictures is in `Demos/scripts`. Run from the project folder, with Screen Recording on for the app running the command and the Mac unlocked. Each run updates the site's copies and these folders; nothing is committed or published.

| To retake | Command |
|---|---|
| Everything the site shows | `Demos/scripts/capture-demos.sh` |
| Every still, no videos | `Demos/scripts/capture-demos.sh --stills-only` |
| Every video, plus the Tools pictures | `Demos/scripts/capture-demos.sh --videos` |
| The music reel and its five stills | `Demos/scripts/capture-demos.sh --music-only` |
| One or more shots | `Demos/scripts/capture-demos.sh --only page-shelf,page-usage` |
| A quick test that recording works | `Demos/scripts/capture-demos.sh --test` |

Shot names for `--only`:

- **Nook:** `page-home`, `page-calendar`, `page-weather`, `page-clock`, `page-timers`, `page-system`, `page-shortcuts`, `page-notes`, `page-todos`, `page-homebrew`, `page-usage`, `page-coding`, `page-meetings`, `page-dictation`, `page-prompter`, `page-mirror`, `page-status` (from `MACSPACES_DEMO_ONLY=status`)
- **Tsukumo:** `page-wisp-hello`, `page-wisp`, `kemosabe-sarah`
- **Heartable:** `page-music`, `page-music-terminal`, `page-shelf`, `page-stats`, `page-backups`, `page-backup-compare`
- **Tape:** `tape`
- **Folio:** `page-folio-board` (the Tray slide), `page-folio-search`
- **Videos:** `calendar-life`, `clock-match`, `themes`, `ascii`

The Agents, Pop-outs and File Converter videos and the Tools pictures are drawn off screen by `--videos`. The three theme pictures come from the `themes-redesign` check scope.

## The Nook

| Picture | Shows | Captured for | Note |
|---|---|---|---|
| <img src="screenshots/nook/home.webp" width="220" alt="Home"> | **Home**<br>`home.webp` · README | 4.06<br>8 Nov | A crop of the site's Home. To be redone tighter. |
| <img src="screenshots/nook/calendar-life-poster.webp" width="220" alt="Calendar"> | **Calendar**<br>`calendar-life-poster.webp` | 4.06<br>8 Nov | Video's poster. |
| <img src="screenshots/nook/calendar.webp" width="220" alt="Calendar"> | **Calendar**<br>`calendar.webp` · README | 4.06<br>8 Nov |  |
| <img src="screenshots/nook/weather.webp" width="220" alt="Weather"> | **Weather**<br>`weather.webp` · README | 4.06<br>8 Nov |  |
| <img src="screenshots/nook/clock-match-poster.webp" width="220" alt="Clock"> | **Clock**<br>`clock-match-poster.webp` | 4.06<br>8 Nov | Video's poster. |
| <img src="screenshots/nook/clock.webp" width="220" alt="Clock"> | **Clock**<br>`clock.webp` · README | 4.06<br>8 Nov |  |
| <img src="screenshots/nook/timers.webp" width="220" alt="Timers"> | **Timers**<br>`timers.webp` · README | 4.32<br>24 Nov | Gruvbox, timers in rows, drawn off screen. |
| <img src="screenshots/nook/system.webp" width="220" alt="System"> | **System**<br>`system.webp` · README | 4.06<br>8 Nov |  |
| <img src="screenshots/nook/shortcuts.webp" width="220" alt="Shortcuts"> | **Shortcuts**<br>`shortcuts.webp` · README | 4.06<br>8 Nov |  |
| <img src="screenshots/nook/notes.webp" width="220" alt="Notes"> | **Notes**<br>`notes.webp` · README | 4.34<br>25 Nov | Solarized, with the To-Dos row, drawn off screen. |
| <img src="screenshots/nook/todos.webp" width="220" alt="To-Dos"> | **To-Dos**<br>`todos.webp` | 4.34<br>25 Nov | Nord, drawn off screen. |
| <img src="screenshots/nook/homebrew.webp" width="220" alt="Homebrew"> | **Homebrew**<br>`homebrew.webp` | 4.32<br>24 Nov | Dracula, drawn off screen. |
| <img src="screenshots/nook/usage.webp" width="220" alt="Usage"> | **Usage**<br>`usage.webp` · README | 4.06<br>8 Nov | Wanted in a Ghostty theme. |
| <img src="screenshots/nook/agents-poster.webp" width="220" alt="Sessions"> | **Sessions**<br>`agents-poster.webp` | 4.06<br>8 Nov | Video's poster. |
| <img src="screenshots/nook/coding.webp" width="220" alt="Sessions"> | **Sessions**<br>`coding.webp` · README | 4.06<br>8 Nov |  |
| <img src="screenshots/nook/meetings.webp" width="220" alt="Meetings"> | **Meetings**<br>`meetings.webp` · README | 4.06<br>8 Nov |  |
| <img src="screenshots/nook/dictation.webp" width="220" alt="Dictate"> | **Dictate**<br>`dictation.webp` · README | 4.06<br>8 Nov |  |
| <img src="screenshots/nook/prompter.webp" width="220" alt="Studio"> | **Studio**<br>`prompter.webp` · README | 4.06<br>8 Nov |  |
| <img src="screenshots/nook/mirror.webp" width="220" alt="Mirror"> | **Mirror**<br>`mirror.webp` | 4.33<br>25 Nov | Tokyo Night, at rest, drawn off screen (captures never use the camera). |
| <img src="screenshots/nook/popouts-poster.webp" width="220" alt="Nudges"> | **Nudges**<br>`popouts-poster.webp` | 4.06<br>8 Nov | Video's poster. |
| <img src="screenshots/nook/notch-poster.webp" width="220" alt="Notch"> | **Notch**<br>`notch-poster.webp` | 4.06<br>8 Nov | Not shown on the site now. |
| <img src="screenshots/nook/status.webp" width="220" alt="Status icon"> | **Status**<br>`status.webp` | 4.34<br>25 Nov | The icon in a drawn menu bar with its real menu lines, and large in four states; drawn off screen (`MACSPACES_DEMO_ONLY=status` writes `page-status.png`). |

## Tsukumo

| Picture | Shows | Captured for | Note |
|---|---|---|---|
| <img src="screenshots/tsukumo/kemosabe-sarah-poster.webp" width="220" alt="KemoSabe"> | **KemoSabe**<br>`kemosabe-sarah-poster.webp` · README | 4.07<br>8 Nov | Video's poster. |
| <img src="screenshots/tsukumo/wisp-hello.webp" width="220" alt="Wisp's greeting"> | **Wisp's greeting**<br>`wisp-hello.webp` · README | 4.07<br>8 Nov | Not shown on the site now. |

## Heartable

| Picture | Shows | Captured for | Note |
|---|---|---|---|
| <img src="screenshots/heartable/music.webp" width="220" alt="Lyrics"> | **Lyrics**<br>`music.webp` · README | 4.06<br>8 Nov |  |
| <img src="screenshots/heartable/music-terminal-poster.webp" width="220" alt="Vinyl"> | **Vinyl**<br>`music-terminal-poster.webp` · README | 4.12<br>9 Nov |  |
| <img src="screenshots/heartable/shelf.webp" width="220" alt="Shelf"> | **Shelf**<br>`shelf.webp` · README | 4.34<br>25 Nov | Duckbones, the new row of covers, drawn off screen. |
| <img src="screenshots/heartable/stats.webp" width="220" alt="Stats"> | **Stats**<br>`stats.webp` | 4.06<br>8 Nov |  |
| <img src="screenshots/heartable/backups.webp" width="220" alt="Backups"> | **Backups**<br>`backups.webp` | 4.33<br>24 Nov | Nord, weekly backups up to today, drawn off screen. |
| <img src="screenshots/heartable/backup-compare.webp" width="220" alt="Compare"> | **Compare**<br>`backup-compare.webp` | 4.33<br>24 Nov | Measured Dark, songs with covers under clear playlist names, drawn off screen. |

## Tape

| Picture | Shows | Captured for | Note |
|---|---|---|---|
| <img src="screenshots/tape/tape-poster.webp" width="220" alt="Tape"> | **Tape**<br>`tape-poster.webp` · README | 4.06<br>8 Nov | Being redone. |

## Folio

| Picture | Shows | Captured for | Note |
|---|---|---|---|
| <img src="screenshots/folio/tray.webp" width="220" alt="Tray"> | **Tray**<br>`tray.webp` · README | 4.32<br>24 Nov | Real pictures over Moonlit Dunes, drawn off screen. |
| <img src="screenshots/folio/folio-search.webp" width="220" alt="Search"> | **Search**<br>`folio-search.webp` · README | 4.33<br>24 Nov | Real pictures over Obsidian Coast (the Tray keeps Moonlit Dunes), drawn off screen. |

## Tools

| Picture | Shows | Captured for | Note |
|---|---|---|---|
| <img src="screenshots/tools/converter-poster.webp" width="220" alt="File Converter"> | **File Converter**<br>`converter-poster.webp` · README | 4.32<br>24 Nov | Even gaps between the slices. |
| <img src="screenshots/tools/clipboard.webp" width="220" alt="Clipboard"> | **Clipboard**<br>`clipboard.webp` | 3.9x<br>6 Nov | Kept as approved; captures never replace it. |
| <img src="screenshots/tools/basket.webp" width="220" alt="Basket"> | **Basket**<br>`basket.webp` | 3.9x<br>6 Nov | Kept as approved. |
| <img src="screenshots/tools/basket-closed.webp" width="220" alt="Basket, closed"> | **Basket, closed**<br>`basket-closed.webp` | 3.9x<br>6 Nov | Kept as approved. |

## Themes

| Picture | Shows | Captured for | Note |
|---|---|---|---|
| <img src="screenshots/themes/themes-macspaces.webp" width="220" alt="Editorial pack"> | **Editorial pack**<br>`themes-macspaces.webp` · README | 4.31<br>24 Nov | README only. |
| <img src="screenshots/themes/themes-terminal.webp" width="220" alt="Classics pack"> | **Classics pack**<br>`themes-terminal.webp` · README | 4.31<br>24 Nov | README only. |
| <img src="screenshots/themes/themes-custom.webp" width="220" alt="Search"> | **Search**<br>`themes-custom.webp` · README | 4.31<br>24 Nov | README only. |
