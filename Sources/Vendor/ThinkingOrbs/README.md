# Thinking orbs (vendored)

Animated loading orbs from [Libraries.dev](https://libraries.dev/orbs) by Jakub Antalik, MIT License (see `LICENSE`).

- Copied unmodified from KemoSabe's vendored copy (source `github.com/Jakubantalik/Libraries.dev`, `packages/thinking-orbs/ports/ios/ThinkingOrbsKit/Sources/ThinkingOrbsKit`, commit `f20116327f4e3b28d0fb70b04437dfd092bf88fe`).
- Pure math and SwiftUI `Canvas` drawing: no networking, file access or processes.
- MacSpaces drives it from its own timer-scheduled TimelineView through `orbFrozenTime`, since `.animation` timelines pause in the menu-bar panel.
