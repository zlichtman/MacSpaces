MacSpaces **1.14** — the stable release for macOS 13 and later.

1.14 is the release previously published as 1.0.0 (build 14), renamed to the
`major.build` version scheme. The app is unchanged.

- Stops SwiftUI from resizing the Nook host window during AppKit layout, addressing the captured layout-loop crash and resize churn.
- Tray keeps the Nook profile width instead of expanding to the maximum width.
- Settings window size is owned by AppKit, preventing competing ideal-size updates.
- Preserves the desktop-click anchoring fix, existing preferences, profiles and Tray files.

**macOS 13 or later · Apple silicon and Intel · Signed and notarized**

MacSpaces 2.x is a separate pre-release for macOS 26 on Apple silicon.
