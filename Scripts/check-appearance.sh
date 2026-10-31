#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
checks_dir=$(mktemp -d)
trap 'rm -rf "$checks_dir"' EXIT
swiftc -parse-as-library Sources/DesignSystem/ThemeFamily.swift Sources/DesignSystem/CustomTheme.swift Sources/DesignSystem/GhosttyThemes.swift Sources/DesignSystem/ThemeMotif.swift Sources/DesignSystem/Design.swift Sources/DesignSystem/LyricStyle.swift Sources/DesignSystem/ThemeStore.swift Tests/AppearanceBaseline.swift Tests/AppearanceChecks.swift -o "$checks_dir/appearance-checks"
"$checks_dir/appearance-checks"
