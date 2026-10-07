# MacSpaces 2.88

**2.88** is the current MacSpaces release, for macOS 15 or later on Apple silicon and Intel.

- **Quiet lyric lookup.** Only resolved lyrics appear. Loading, unavailable and caption prompts stay hidden, including for VoiceOver.
- **Stricter song matching.** Partial titles, featured-only artist matches and incompatible timed recordings are rejected. LRCLIB remains the timed provider, with lyrics.ovh as the plain-text fallback.

Previously in 2.87:

- **Softer Settings search.** A rounded pill with a quiet surface fill, more breathing room and a subtle neutral focus highlight replaces the bright accent outline.

Previously in 2.86:

- **Search Settings.** Search across all six pages from the sidebar. Results match section names and option keywords; selecting one opens and highlights its card. Use ⌘F, Up/Down and Return, or Escape to clear. Permission results jump to their read-only status rows. Search stays on your Mac and does not change settings or request access.

Previously in 2.85:

- **Compact closed notch.** Each side fits its own content, keeping music close to the physical camera without mirroring the wider agent lane. Pointer and file-drop regions follow the fitted surface.
- **Grouped agents.** Matching agent types share one icon, with compact stacks of individual thinking, waiting and completion indicators. Groups and sessions keep a stable order.

Previously in 2.84:

- **Every coding agent is visible.** Each session has its own host icon and thinking orb, waiting indicator or completion check. Indicators use equal-sized slots and stable ordering instead of representing extra sessions with “+N”.
- **Snug Music controls.** The middle dock capsule fits the controls available for the current player. The placeholder Open Spotify button is removed.

Spotify queue support and the experimental Soloist Linux companion are excluded from this release. Existing Spotify playback controls and lyrics remain available.

Previously in 2.83:

- **Stable widget removal.** The Nook's SwiftUI content no longer owns the window frame, preventing runaway window resizing during Home edits and opening animations. A native regression opens the Nook during calculator removal with Settings visible.
- **Three dock groups.** App pages (including Home), controls for the active app, and Settings. Music playlist/output controls move into the middle bar; Home profiles appear there only on Home. Pin and Close can each be hidden in Settings → Widgets → Dock. Spotify shows an explicitly labelled Open Spotify button because its Mac queue is not available through the local integration.

Also in 2.82:

- **Find Action and keyboard navigation.** Search pages, tools and Shortcuts with Control–Option–Space. Configure page hotkeys and keep keyboard-opened pages pinned.
- **Shared File Tools.** Saved presets, resize/crop, target-size images and GIF options, cancellable jobs, per-file results and retry. Originals stay untouched; alpha and animated-image handling are explicit.
- **A more useful Tray.** Select and drag several files, preview with Space, paste files/text/images/links, Undo Remove, share, locate offline files and safely recover a damaged list.
- **Automation.** Finder Services and Shortcuts actions stage/process files. Optional folder watching adds new stable files to Tray. Long Shortcuts can finish or be cancelled.
- **Dictation and meetings.** Explicit on-device dictation with editable text; Zoom and Google Meet controls with verified states and English labels. Permissions are requested when used.
- **Music and reliability.** Long song titles no longer collide with output controls. Music can show playlist order; Spotify queue management opens Spotify without API setup. Reminder saves, notification routing during editing, timer/Focus restoration, calculator responses and server Stop checks are corrected.

See Documentation/FEATURE-AUDIT.md for validation scope and provider limits.

Changes in 2.81:

- **A tidier Usage tab.** The Terminal page's Usage tab fits again: the tab bar stays in place and nothing is cut off at the bottom.
- **Real project names.** Work done in Claude Code's agent worktrees and in subfolders now counts toward its project, instead of showing up as "agent-a0318…" or "macos", and Claude Code's internal "<synthetic>" messages are no longer listed as a model.

Also in 2.80:

- **Notifications open where they belong.** If the Messages page is in your dock, a new message opens the Nook on that conversation instead of showing a card. If the Terminal page is there, a coding agent that needs you opens its Agents tab. The Nook closes again after a few seconds unless you move in, and never jumps while you're using it.
- **Snugger cards.** The cards that still slide down under the notch are now only as tall as what they say.

Also in 2.79:

- **A file in the middle of the converter wheel.** Hold Shift while dragging a file and the wheel's centre now shows a file with its type (PNG, PDF, ZIP…) and size, instead of a picture of what's inside. Several files show as a stack.

Also in 2.78:

- **No gap beside the camera.** The icons beside the closed notch now sit right up against the camera, with room left only for the rounded corners.

Also in 2.77:

- **A snugger closed notch.** The icons and counts beside the notch now take only the room they need, so there's no empty stretch around a coding agent, a screenshot or a timer.

Also in 2.76 (fixes from an engineering audit):

- **Replies go where you wrote them.** On the Messages page each conversation keeps its own draft, and Send sends that draft to that conversation, even if you switch chats or use the Nook on another display.
- **Saved scripts and pins are never thrown away.** If your teleprompter scripts or clipboard pins can't be opened, MacSpaces leaves the file as it is instead of saving over it. Start New Library (scripts) or Clear All (clipboard) keeps the old file beside the new one.
- **Voice following stays on your Mac.** The teleprompter follows your voice only with on-device recognition; otherwise it scrolls and tells you why. Audio is never sent anywhere.
- **Maccy imports follow your filters.** Copies from ignored apps, and ones marked private by password managers, stay out.
- **Focus turns back off.** If you switch off "Silence during focus" mid-session, Do Not Disturb still turns off when the session pauses or ends.
- **Steadier Messages page.** It keeps running on one display when you close it on another, and never fills back in after closing.
- **Truer coding stats.** Codex usage is no longer counted twice, and rankings cover only the last 14 days.
- **Hidden apps from the start.** The Nook now stays hidden when an app you excluded is already in front as MacSpaces starts.
