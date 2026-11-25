import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Folio's Clipboard card, one card for everything the clipboard's history does: Folio's
/// Clipboard place, the history shortcut and popup, what's kept and recorded, importing from
/// Maccy, and what's left out (the Ignore list, folded away until opened).
struct ClipboardSettingsCards: View {
    @ObservedObject private var nook = NookSettings.shared
    @AppStorage(WidgetOptions.Keys.clipboardIgnoreDrawer) private var ignoreOpen = false
    @ObservedObject private var preferences = ClipboardPreferences.shared
    @ObservedObject private var popup = ClipboardPopup.shared
    @ObservedObject private var clipboard = AppServices.shared.clipboard
    @State private var newPattern = ""
    @State private var newType = ""
    @State private var importResult: String?

    var body: some View {
        SettingsCard("Clipboard", systemImage: "doc.on.clipboard") {
            SettingsSection("In Folio") {
                Toggle("Keep history for Folio's Clipboard", isOn: $nook.folioClipboardHistory)
                Toggle("Open Folio on Clipboard", isOn: $nook.folioOpensOnClipboard)
                SettingsCaption("Folio's Clipboard place shows your history; the popup works either way.")
            }
            Divider()
            SettingsSection("History shortcut") {
                Picker("Open history with", selection: $preferences.shortcut) {
                    ForEach(ClipboardHistoryShortcut.allCases) { Text($0.title).tag($0) }
                }
                .fixedSize()
                if let problem = popup.shortcutProblem { SettingsCaption(problem, colour: .orange) }
                SettingsSegmentedPicker("Opens", selection: $preferences.popupPosition,
                                        options: ClipboardPopupPosition.allCases) { $0.title }
                Toggle("Return pastes into the app you were using", isOn: $preferences.pasteOnSelect)
                Toggle("Paste as plain text", isOn: $preferences.plainTextByDefault)
                Toggle("Show a preview of the selected clip", isOn: $preferences.showsPreview)
                Toggle("Show the app each clip came from", isOn: $preferences.showsAppIcons)
                SettingsCaption("Type to search, ↩ to copy, ⌥↩ to paste. Hover here for every key.",
                                help: "Type to search; ↑↓ to choose (⇧ to choose several); ↩ to copy and ⌥↩ to paste (the other way round with the switch above); ⌥⇧↩ pastes as plain text; ⌘1–9 copies and ⌥1–9 pastes; ⌥P pins; ⌥⌫ deletes; ⌥⌘⌫ clears history. Pasting into other apps needs Accessibility.")
            }
            Divider()
            SettingsSection("History") {
                Toggle("Keep history after quitting", isOn: Binding(
                    get: { clipboard.persistenceEnabled }, set: { clipboard.setPersistence($0) }))
                // Why the switch turned itself back off, or why saving failed.
                if let error = clipboard.storageError { SettingsCaption(error, colour: .red) }
                Picker("Keep", selection: $preferences.historyLimit) {
                    ForEach(ClipboardPreferences.historyLimits, id: \.self) { Text("\($0) clips").tag($0) }
                }
                .fixedSize()
                SettingsSegmentedPicker("Sort by", selection: $preferences.sortOrder,
                                        options: ClipboardSortOrder.allCases) { $0.title }
                SettingsSegmentedPicker("Pins", selection: $preferences.pinsOnTop, options: [true, false]) {
                    $0 ? "At the top" : "At the bottom"
                }
                Picker("Search", selection: $preferences.searchMode) {
                    ForEach(ClipboardSearchMode.allCases) { Text($0.title).tag($0) }
                }
                .fixedSize()
                Picker("Delete clips not copied in", selection: $preferences.autoDeleteDays) {
                    Text("Never").tag(0)
                    ForEach(ClipboardPreferences.autoDeleteChoices.filter { $0 > 0 }, id: \.self) { Text($0 == 1 ? "1 day" : "\($0) days").tag($0) }
                }
                .fixedSize()
                Toggle("Keep pins and snippets after quitting", isOn: $preferences.keepsPins)
                Toggle("Clear history when MacSpaces quits", isOn: $preferences.clearsOnQuit)
                Toggle("Clearing history also empties the clipboard", isOn: $preferences.clearsSystemClipboard)
                SettingsCaption("Pins stay when history is cleared. Saved history is encrypted on this Mac.",
                                help: "Pins are kept when history is cleared. History stays in memory unless Keep history after quitting is on; saved history, pins and snippets are encrypted on this Mac.")
            }
            Divider()
            SettingsSection("Recording") {
                Toggle("Pause recording", isOn: $preferences.paused)
                Toggle("Text and links", isOn: $preferences.filter.recordsText)
                Toggle("Images", isOn: $preferences.filter.recordsImages)
                Toggle("Files", isOn: $preferences.filter.recordsFiles)
                SettingsCaption("Private copies and text shaped like a key or token are never recorded.",
                                help: "Copies that password managers mark as private, and text shaped like a private key or access token, are never recorded.")
            }
            Divider()
            SettingsSection("Switching from Maccy") {
                HStack {
                    Button("Import Maccy History") {
                        Task { @MainActor in
                            if let message = await clipboard.importFromMaccy().message { importResult = message }
                        }
                    }
                    .buttonStyle(.settings())
                    .disabled(clipboard.importingMaccy)
                    if clipboard.importingMaccy {
                        ProgressView().controlSize(.small)
                        SettingsCaption("Importing")
                    } else if let importResult {
                        SettingsCaption(importResult)
                    }
                }
                SettingsCaption("Brings in Maccy's clips and pins. Then set the shortcut to ⇧⌘C and quit Maccy.",
                                help: "Brings in Maccy's text, links, images and files, keeping pins and copy counts. Your newer clips stay; Maccy's are kept up to the history size and 50 pins. Anything shaped like a password or token is left out. Then set the history shortcut above to ⇧⌘C and quit Maccy.")
            }
            Divider()
            SettingsDisclosure("Ignore", isOpen: $ignoreOpen) { ignoreList }
        }
    }

    /// What isn't recorded: apps, patterns and clipboard formats.
    @ViewBuilder private var ignoreList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSegmentedPicker("Apps", selection: $preferences.filter.onlyListedApps, options: [false, true]) {
                $0 ? "Only record these apps" : "Ignore these apps"
            }
            ForEach(preferences.filter.apps.sorted(), id: \.self) { bundleID in
                HStack(spacing: 8) {
                    AppIcon(bundleID: bundleID).frame(width: 18, height: 18)
                    Text(appName(bundleID)).lineLimit(1)
                    Spacer()
                    removeButton { preferences.filter.apps.remove(bundleID) }
                }
            }
            Button("Add App") { chooseApp() }.buttonStyle(.settings())

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
                TextField("For example ^\\d{6}$", text: $newPattern).settingsTextField()
                    .onSubmit(addPattern)
                Button("Add", action: addPattern).buttonStyle(.settings())
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
                TextField("Format, such as com.example.private", text: $newType).settingsTextField()
                    .onSubmit(addType)
                Button("Add", action: addType).buttonStyle(.settings())
                    .disabled(newType.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Reset") { preferences.filter.ignoredTypes = ClipboardFilter.defaultIgnoredTypes }
                    .buttonStyle(.settings(.quiet))
                    .help("Back to the formats left out by default")
            }
        }
        .padding(.top, 6)
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        SettingsRemoveButton(action: action)
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
        SettingsWindowController.shared.runPanel(panel) { chosen in
            guard chosen else { return }
            for url in panel.urls {
                if let id = Bundle(url: url)?.bundleIdentifier { preferences.filter.apps.insert(id) }
            }
        }
    }
}
