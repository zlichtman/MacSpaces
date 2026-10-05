import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Clipboard: the history shortcut and popup, what's recorded, and what's left out.
struct ClipboardSettingsPane: View {
    @ObservedObject private var preferences = ClipboardPreferences.shared
    @ObservedObject private var popup = ClipboardPopup.shared
    @State private var newPattern = ""
    @State private var newType = ""

    var body: some View {
        SettingsPage(title: "Clipboard", subtitle: "History you can open anywhere, and what it keeps.") {
            SettingsCard("History shortcut", systemImage: "keyboard") {
                Picker("Open history with", selection: $preferences.shortcut) {
                    ForEach(ClipboardHistoryShortcut.allCases) { Text($0.title).tag($0) }
                }
                if let problem = popup.shortcutProblem {
                    Text(problem).font(.caption).foregroundStyle(.orange)
                }
                Picker("Opens", selection: $preferences.popupPosition) {
                    ForEach(ClipboardPopupPosition.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Return pastes into the app you were using", isOn: $preferences.pasteOnSelect)
                Toggle("Paste as plain text", isOn: $preferences.plainTextByDefault)
                Toggle("Show a preview of the selected clip", isOn: $preferences.showsPreview)
                Toggle("Show the app each clip came from", isOn: $preferences.showsAppIcons)
                Text("Type to search; ↑↓ to choose (⇧ to choose several); ↩ to copy and ⌥↩ to paste (the other way round with the switch above); ⌥⇧↩ pastes as plain text; ⌘1–9 copies and ⌥1–9 pastes; ⌥P pins; ⌥⌫ deletes; ⌥⌘⌫ clears history. Pasting into other apps needs Accessibility.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SettingsCard("History", systemImage: "clock.arrow.circlepath") {
                Picker("Keep", selection: $preferences.historyLimit) {
                    ForEach(ClipboardPreferences.historyLimits, id: \.self) { Text("\($0) clips").tag($0) }
                }
                Picker("Sort by", selection: $preferences.sortOrder) {
                    ForEach(ClipboardSortOrder.allCases) { Text($0.title).tag($0) }
                }
                Picker("Pins", selection: $preferences.pinsOnTop) {
                    Text("At the top").tag(true)
                    Text("At the bottom").tag(false)
                }
                Picker("Search", selection: $preferences.searchMode) {
                    ForEach(ClipboardSearchMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Clear history when MacSpaces quits", isOn: $preferences.clearsOnQuit)
                Toggle("Clearing history also empties the clipboard", isOn: $preferences.clearsSystemClipboard)
                Text("Pins are kept when history is cleared. History stays in memory unless you choose to keep it after quitting (on the Clipboard page).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SettingsCard("Recording", systemImage: "record.circle") {
                Toggle("Pause recording", isOn: $preferences.paused)
                Toggle("Text and links", isOn: $preferences.filter.recordsText)
                Toggle("Images", isOn: $preferences.filter.recordsImages)
                Toggle("Files", isOn: $preferences.filter.recordsFiles)
                Text("Copies that password managers mark as private, and text shaped like a private key or access token, are never recorded.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SettingsCard("Ignore", systemImage: "eye.slash") {
                Picker("Apps", selection: $preferences.filter.onlyListedApps) {
                    Text("Ignore copies from these apps").tag(false)
                    Text("Only record copies from these apps").tag(true)
                }
                ForEach(preferences.filter.apps.sorted(), id: \.self) { bundleID in
                    HStack(spacing: 8) {
                        AppIcon(bundleID: bundleID).frame(width: 18, height: 18)
                        Text(appName(bundleID)).lineLimit(1)
                        Spacer()
                        removeButton { preferences.filter.apps.remove(bundleID) }
                    }
                }
                Button("Add App…") { chooseApp() }

                Divider().padding(.vertical, 4)
                Text("Text matching a pattern (a regular expression) isn't recorded.").font(.caption).foregroundStyle(.secondary)
                ForEach(preferences.filter.ignoredPatterns, id: \.self) { pattern in
                    HStack {
                        Text(pattern).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                        Spacer()
                        removeButton { preferences.filter.ignoredPatterns.removeAll { $0 == pattern } }
                    }
                }
                HStack {
                    TextField("For example ^\\d{6}$", text: $newPattern).textFieldStyle(.roundedBorder)
                        .onSubmit(addPattern)
                    Button("Add", action: addPattern)
                        .disabled((try? NSRegularExpression(pattern: newPattern)) == nil || newPattern.isEmpty)
                }

                Divider().padding(.vertical, 4)
                Text("Copies carrying one of these clipboard formats aren't recorded.").font(.caption).foregroundStyle(.secondary)
                ForEach(preferences.filter.ignoredTypes.sorted(), id: \.self) { type in
                    HStack {
                        Text(type).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                        Spacer()
                        removeButton { preferences.filter.ignoredTypes.remove(type) }
                    }
                }
                HStack {
                    TextField("Format, such as com.example.private", text: $newType).textFieldStyle(.roundedBorder)
                        .onSubmit(addType)
                    Button("Add", action: addType).disabled(newType.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Reset") { preferences.filter.ignoredTypes = ClipboardFilter.defaultIgnoredTypes }
                }
            }
        }
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
            .buttonStyle(.plain).accessibilityLabel("Remove")
    }

    private func addPattern() {
        let pattern = newPattern.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty, (try? NSRegularExpression(pattern: pattern)) != nil,
              !preferences.filter.ignoredPatterns.contains(pattern) else { return }
        preferences.filter.ignoredPatterns.append(pattern)
        newPattern = ""
    }

    private func addType() {
        let type = newType.trimmingCharacters(in: .whitespaces)
        guard !type.isEmpty else { return }
        preferences.filter.ignoredTypes.insert(type)
        newType = ""
    }

    private func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { preferences.filter.apps.insert(id) }
        }
    }
}
