#!/bin/bash
# Timers and timelines that stall or redraw for nothing. Every repeating timer runs in
# .common run-loop modes (Timer.scheduledTimer uses the default mode only, so it stops
# while a menu is open or a drag is tracking), and every TimelineView uses a .periodic
# (or custom) schedule: .animation schedules pause while macOS reports the panel hidden
# and redraw at the display's rate.
set -euo pipefail
cd "$(dirname "$0")/.."
failed=0
# Default-mode timers whose move would change what the feature does (the Converter wheel
# would hide during an in-app drag, the Teleprompter would scroll under an open menu):
# left for the owner to decide.
waiting='^Sources/Modules/(Converter/ConverterWheel|Prompter/ScriptPrompter)\.swift:'

if matches=$(grep -rn --include='*.swift' -E 'Timer\.scheduledTimer|Timer\.publish\([^)]*in: \.default' Sources | grep -v '^Sources/Debug/' | grep -vE "$waiting"); then
  echo "Timers outside .common modes (use Timer(...) and RunLoop.main.add(timer, forMode: .common)):"
  echo "$matches"
  failed=1
fi

if matches=$(grep -rn --include='*.swift' -E 'TimelineView\(\.animation' Sources); then
  echo "TimelineView with an .animation schedule (use .periodic):"
  echo "$matches"
  failed=1
fi

# Each file that makes a Timer(...) also adds it to the run loop in .common modes.
for file in $(grep -rl --include='*.swift' -E '\bTimer\(timeInterval:' Sources | grep -v '^Sources/Debug/'); do
  made=$(grep -cE '\bTimer\(timeInterval:' "$file")
  added=$(grep -cE 'RunLoop\.main\.add\([^)]*forMode: \.common\)' "$file" || true)
  if [ "$added" -lt "$made" ]; then
    echo "$file makes $made timer(s) but adds $added in .common modes"
    failed=1
  fi
done

[ "$failed" = 0 ] && echo "Timer and timeline checks passed"
exit "$failed"
