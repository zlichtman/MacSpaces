import SwiftUI
import UniformTypeIdentifiers

/// The Tape page: the switch first, then every setting whether Tape is on or off (off, they're
/// saved for when it starts). Only Displays and Managed Windows, which list what's on screen now,
/// wait for Tape to run. Opening it asks for nothing; Accessibility comes from the switch or the
/// Allow button.
struct TapeSettingsPane: View {
    @ObservedObject private var feature = TapeFeature.shared
    /// Tape's saved settings while it's off; running, the controller's own are used.
    @StateObject private var offSettings = TapeSettings()
    #if DEBUG
    /// Check renders: the On page with a controller that moves nothing.
    var previewController: TapeController?
    #endif

    var body: some View {
        SettingsPage(title: "Tape", subtitle: "Keep your windows side by side in a strip and scroll along it.") {
            #if DEBUG
            if let previewController {
                TapeRunningCards(feature: feature, controller: previewController, settings: previewController.settings)
            }
            #endif
            if let controller = feature.controller, feature.isOn {
                TapeRunningCards(feature: feature, controller: controller, settings: controller.settings)
            } else if !hasPreview {
                TapeSwitchCard(feature: feature, status: feature.isTurningOff ? "Restoring your windows…" : "Off. Changes below apply when it starts.") { EmptyView() }
                TapeDesktopsCard(spaces: AppServices.shared.spaces, settings: offSettings)
                    .onAppear { AppServices.shared.spaces.refresh() }
                TapeSettingsCards(settings: offSettings, conflicts: []) { EmptyView() }
            }
        }
    }
}

private extension TapeSettingsPane {
    var hasPreview: Bool {
        #if DEBUG
        previewController != nil
        #else
        false
        #endif
    }
}

private struct TapeSwitchCard<Details: View>: View {
    @ObservedObject var feature: TapeFeature
    let status: String
    @ViewBuilder let details: Details

    var body: some View {
        SettingsCard("Status", systemImage: "power") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Arrange windows").font(.system(size: 13, weight: .medium))
                    Text(status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("Arrange windows", isOn: Binding(get: { feature.isOn }, set: { feature.setOn($0) }))
                    .toggleStyle(.switch).labelsHidden()
                    .disabled(feature.isTurningOff)
            }
            details
            SettingsCaption("Tape needs Accessibility. macOS asks when you turn it on, and never before.",
                            help: "Tape moves, resizes and focuses windows, so it needs Accessibility. macOS asks when you turn it on, and never before.")
        }
    }
}

private struct TapeRunningCards: View {
    @ObservedObject var feature: TapeFeature
    @ObservedObject var controller: TapeController
    @ObservedObject var settings: TapeSettings

    private var status: String {
        if feature.isTurningOff || controller.isRestoring { return "Restoring your windows…" }
        if feature.separateAppRunning { return "The Tape app is running, so this waits: only one should move your windows." }
        if !controller.hasAccessibility { return "Needs Accessibility access" }
        if controller.isPaused { return "Paused. Your windows are where you left them." }
        return controller.isOffOnThisDesktop ? "Off on this desktop" : controller.displaySummary
    }

    var body: some View {
        switchCard
            .onAppear { AppServices.shared.spaces.refresh() }
        TapeDesktopsCard(spaces: AppServices.shared.spaces, settings: settings)
        if controller.displayChoices.count > 1 { displays }
        TapeSettingsCards(settings: settings, conflicts: controller.shortcutConflicts) { managedWindows }
    }

    private var switchCard: some View {
        TapeSwitchCard(feature: feature, status: status) {
            if let message = controller.message {
                Text(message).font(.caption).foregroundStyle(ThemeStore.shared.settings.accent).fixedSize(horizontal: false, vertical: true)
            }
            if feature.separateAppRunning {
                Button("Quit Tape") { feature.quitSeparateApp() }.buttonStyle(.settings(.primary))
            } else if !controller.hasAccessibility {
                Button("Allow Accessibility") { controller.requestAccessibility() }.buttonStyle(.settings())
            } else if controller.isPaused, !controller.isRestoring, !feature.isTurningOff {
                Button("Start") { controller.resume() }.buttonStyle(.settings())
            }
        }
    }

    private var displays: some View {
        SettingsCard("Displays", systemImage: "display.2") {
            ForEach(controller.displayChoices) { display in
                HStack {
                    Toggle(display.name, isOn: Binding(get: { display.enabled }, set: { controller.setDisplayEnabled(display.id, $0) }))
                    Spacer()
                    Text(display.windowCount == 1 ? "1 window" : "\(display.windowCount) windows").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var managedWindows: some View {
        SettingsDrawerCard("Managed Windows", systemImage: "rectangle.on.rectangle", openKey: WidgetOptions.Keys.tapeWindowsDrawer) {
            Toggle("Manage only checked windows", isOn: Binding(get: { !controller.manageAllWindows }, set: { controller.setManageAllWindows(!$0) }))
                .disabled(controller.isPaused)
            ForEach(controller.managedWindowChoices) { window in
                Toggle(window.name, isOn: Binding(get: { window.managed }, set: { controller.setWindowManaged(window.id, $0) }))
                    .disabled(controller.isPaused)
            }
            SettingsCaption(controller.isPaused ? "Start Tape to choose open windows." : "Applies to windows open now; new windows stay outside Tape while this is on.")
        }
    }
}

/// Tape's settings that need only what's saved, so they show whether Tape is on or off.
/// `windows` is Managed Windows while Tape runs, placed after Managed Apps.
private struct TapeSettingsCards<Windows: View>: View {
    @ObservedObject var settings: TapeSettings
    /// Shortcuts another app holds, known only while Tape runs.
    let conflicts: [String]
    @ViewBuilder let windows: Windows
    @StateObject private var apps = TapeAppList()
    @State private var showsBackgroundApps = false

    var body: some View {
        layout
        trackpad
        managedApps
        windows
        keyboard
        macSetup
    }

    private var layout: some View {
        SettingsCard("Layout", systemImage: "rectangle.split.3x1") {
            spacing("Window Gap", value: $settings.gap)
            spacing("Edge Gap", value: $settings.edgeGap)
            Divider()
            SettingsSegmentedPicker("Centre the focused column", selection: $settings.centering,
                                    options: [CenteringMode.never, .overflow, .always]) {
                switch $0 {
                case .never: "Never"
                case .overflow: "When it overflows"
                case .always: "Always"
                }
            }
            Divider()
            HStack {
                Text("Width presets")
                Spacer()
                Text("⅓ → ½ → ⅔ → Full").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
            }
            Toggle("Resize columns together", isOn: $settings.sharedWidths)
            SettingsCaption("A lone window fills the screen; new columns open at half width.")
            SettingsCaption("Stack or tab a column from Stacks and Tabs in Tape's menu.",
                            help: "Join a window to the next column to stack it, then switch the column between a stack and tabs. Every command is under Stacks and Tabs in Tape's menu.")
            Divider()
            Toggle("Move windows instantly", isOn: $settings.reduceMotion)
            SettingsCaption("Tape also follows the Mac's Reduce Motion setting.")
        }
    }

    private func spacing(_ title: String, value: Binding<Double>) -> some View {
        SettingsSlider(title: title, value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0.rounded() }),
                       range: 0...40, valueText: "\(Int(value.wrappedValue)) pt")
    }

    private var managedApps: some View {
        SettingsDrawerCard("Managed Apps", systemImage: "app.badge.checkmark", openKey: WidgetOptions.Keys.tapeAppsDrawer) {
            SettingsSegmentedPicker("Manage", selection: $settings.appPolicy.manageAll, options: [true, false]) {
                $0 ? "All apps, with exceptions" : "Only selected apps"
            }
            let primary = apps.apps.filter(\.isPrimary)
            // Helpers and services follow, with the ones lacking an icon of their own last.
            let others = apps.apps.filter { !$0.isPrimary && $0.hasIcon } + apps.apps.filter { !$0.hasIcon }
            ForEach(primary) { appRow($0) }
            if !others.isEmpty {
                // Agents and services rarely have windows; keep them out of the way until asked for.
                DisclosureGroup(isExpanded: $showsBackgroundApps) {
                    VStack(alignment: .leading, spacing: 13) { ForEach(others) { appRow($0) } }.padding(.top, 8)
                } label: {
                    Text("Background and system apps (\(others.count))").foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            if apps.apps.isEmpty { Text("Open an app or add it below.").foregroundStyle(.secondary) }
            HStack {
                Button("Add App") { addApp() }.buttonStyle(.settings())
                RefreshButton("Refresh Open Apps") { apps.refresh(known: knownApps) }.buttonStyle(.settings(.quiet))
            }
        }
        .onAppear { apps.refresh(known: knownApps) }
    }

    private var knownApps: [String: String?] {
        var known: [String: String?] = [:]
        for id in settings.appPolicy.selected.union(settings.appPolicy.excluded) { known[id] = .some(nil) }
        for (id, path) in settings.appPaths { known[id] = path }
        return known
    }

    private func appRow(_ app: TapeAppChoice) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon).resizable().frame(width: 24, height: 24).opacity(app.hasIcon ? 1 : 0.6)
            Toggle(app.name, isOn: Binding(get: { settings.appPolicy.manages(app.id) }, set: {
                settings.appPolicy.setManaged($0, bundleID: app.id)
                settings.appPaths[app.id] = app.path
            }))
            Spacer()
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add to Tape"
        SettingsWindowController.shared.runPanel(panel) { chosen in
            guard chosen else { return }
            for url in panel.urls {
                guard let id = Bundle(url: url)?.bundleIdentifier, id != Bundle.main.bundleIdentifier else { continue }
                settings.appPaths[id] = url.path
                settings.appPolicy.setManaged(true, bundleID: id)
            }
            apps.refresh(known: knownApps)
        }
    }

    private var keyboard: some View {
        SettingsDrawerCard("Keyboard", systemImage: "keyboard", openKey: WidgetOptions.Keys.tapeKeyboardDrawer) {
            ForEach(Array(shortcutRows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider() }
                HStack {
                    Text(row.0)
                    Spacer()
                    Text(row.1).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            if !conflicts.isEmpty {
                Text("Unavailable shortcuts, in use elsewhere\n" + conflicts.joined(separator: "\n"))
                    .foregroundStyle(ThemeStore.shared.settings.accent)
            }
            SettingsCaption("Shortcuts use physical key positions.")
        }
    }

    private var shortcutRows: [(String, String)] {
        var order: [TapeAction] = [], bindings: [TapeAction: [String]] = [:]
        for binding in HotKeyBinding.defaults {
            if bindings[binding.action] == nil { order.append(binding.action) }
            bindings[binding.action, default: []].append(binding.display)
        }
        return order.map { ($0.label, bindings[$0]!.joined(separator: "  /  ")) }
    }

    private var trackpad: some View {
        SettingsCard("Trackpad", systemImage: "hand.draw") {
            Text("⌃⌥ and scroll sideways with two fingers to browse the strip under the pointer.")
                .help("Hold Control–Option and scroll sideways with two fingers to browse the strip under the pointer without switching apps. Ordinary scrolling stays with your apps.")
            SettingsCaption("Ordinary scrolling stays with your apps.")
        }
    }

    private var macSetup: some View {
        SettingsCard("Mac Setup and log", systemImage: "desktopcomputer") {
            SettingsCaption("Turn off Stage Manager, window tiling and other window managers.",
                            help: "Turn off Stage Manager and automatic window tiling, and pause other window managers, so they don't move the same windows.")
            HStack {
                SettingsCaption("The log records events and errors, never window titles.")
                Spacer()
                Button("Reveal Log") { NSWorkspace.shared.activateFileViewerSelecting([TapeLog.shared.url]) }.buttonStyle(.settings())
            }
        }
    }
}

/// Each desktop per display: its number, the name the widget shows too, and a Tape switch.
/// Hidden when macOS doesn't offer the private list, where Tape simply runs everywhere.
/// Your desktops by name, whether or not Tape runs. While it runs, each also has its own switch.
private struct TapeDesktopsCard: View {
    @ObservedObject var spaces: SpacesMonitor
    let settings: TapeSettings?

    var body: some View {
        if !spaces.isUnavailable, !spaces.displays.isEmpty {
            SettingsCard("Desktops", systemImage: "square.stack.3d.down.right") {
                ForEach(spaces.displays, id: \.identifier) { display in
                    if spaces.displays.count > 1 {
                        Text(displayName(display.identifier)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ForEach(display.desktops, id: \.uuid) { desktop in
                        TapeDesktopRow(spaces: spaces, desktop: desktop, isCurrent: display.current == desktop, settings: settings)
                    }
                }
                if settings == nil {
                    SettingsCaption("Names show in the Spaces widget and as you move between desktops.")
                } else {
                    SettingsCaption("New desktops start on. Turning one off puts its windows back.",
                                    help: "New desktops start on. Turning off the desktop you're on puts its windows back now; another desktop's go back when you next visit it.")
                }
            }
        }
    }

    private func displayName(_ identifier: String) -> String {
        NSScreen.screens.first {
            SpacesMonitor.identifier(of: $0)?.caseInsensitiveCompare(identifier) == .orderedSame
        }?.localizedName ?? "Display"
    }
}

/// Tape's switch for one desktop. It watches Tape's settings itself, so a click shows at once:
/// the card above holds them without observing, and once drew the old state after Tape had
/// already turned on for the desktop.
private struct TapeDesktopSwitch: View {
    @ObservedObject var settings: TapeSettings
    let uuid: String
    let number: Int

    var body: some View {
        Toggle("Tape", isOn: Binding(get: { !settings.disabledSpaces.contains(uuid) }, set: { on in
            if on { settings.disabledSpaces.remove(uuid) } else { settings.disabledSpaces.insert(uuid) }
        }))
        .accessibilityLabel("Tape on desktop \(number)")
    }
}

private struct TapeDesktopRow: View {
    @ObservedObject var spaces: SpacesMonitor
    let desktop: SpaceDesktop
    let isCurrent: Bool
    /// Tape's settings while it runs, for this desktop's switch.
    let settings: TapeSettings?
    @State private var draft = ""
    @FocusState private var editing: Bool
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        HStack(spacing: 10) {
            Text("\(desktop.number)")
                .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(isCurrent ? theme.settings.accent : Color.secondary)
                .frame(width: 18, alignment: .trailing)
            // Saved when it's finished: `cleaned` trims, which would eat a space as it's typed.
            TextField("Desktop \(desktop.number)", text: $draft)
                .settingsTextField()
                .focused($editing)
                .frame(maxWidth: 220)
                .accessibilityLabel("Name of desktop \(desktop.number)")
                .onSubmit(save)
            if isCurrent { Text("Showing").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if let settings {
                TapeDesktopSwitch(settings: settings, uuid: desktop.uuid, number: desktop.number)
            }
        }
        .onAppear { draft = spaces.names[desktop.uuid] ?? "" }
        .onChange(of: editing) { if !$0 { save() } }
        .onChange(of: spaces.names[desktop.uuid]) { if !editing { draft = $0 ?? "" } }
        .onDisappear(perform: save)
    }

    private func save() {
        spaces.setName(draft, for: desktop.uuid)
        draft = spaces.names[desktop.uuid] ?? ""
    }
}

struct TapeAppChoice: Identifiable {
    let id: String
    let name: String
    let path: String
    /// Loaded once per refresh rather than on every render.
    let icon: NSImage
    /// System helpers such as Notification Center ship without an icon of their own.
    let hasIcon: Bool
    /// Dock apps and anything installed in an Applications folder; the rest are helpers and services.
    let isPrimary: Bool

    init(id: String, name: String, path: String, regular: Bool = false) {
        self.id = id; self.name = name; self.path = path
        icon = NSWorkspace.shared.icon(forFile: path)
        let info = Bundle(url: URL(fileURLWithPath: path))?.infoDictionary ?? [:]
        hasIcon = info["CFBundleIconFile"] != nil || info["CFBundleIconName"] != nil || info["CFBundleIcons"] != nil
        // Installed in an Applications folder itself, not a helper nested inside another app.
        let folders = ["/Applications/", "/System/Applications/", NSHomeDirectory() + "/Applications/"]
        let installed = folders.contains { folder in
            path.hasPrefix(folder) && !path.dropFirst(folder.count).dropLast(4).contains(".app/")
        }
        isPrimary = hasIcon && (regular || installed)
    }
}

/// Running apps and the ones the rules name, listed on one worker: each app's activation policy
/// and bundle cost a LaunchServices round trip or a disk read. A newer list replaces an older one.
@MainActor
final class TapeAppList: ObservableObject {
    @Published private(set) var apps: [TapeAppChoice] = []
    private static let worker = DispatchQueue(label: "dev.opensource.MacSpaces.tape.apps", qos: .utility)
    private var generation = 0

    /// `known` is each app the rules name, with its saved path if there is one.
    func refresh(known: [String: String?]) {
        generation += 1
        let requested = generation
        Self.worker.async {
            let own = Bundle.main.bundleIdentifier
            var found: [String: TapeAppChoice] = [:]
            for running in NSWorkspace.shared.runningApplications
            where WindowDiscovery.includesApp(policy: running.activationPolicy, isOwnApp: running.processIdentifier == getpid()) {
                guard let id = running.bundleIdentifier, id != own, let url = running.bundleURL else { continue }
                found[id] = TapeAppChoice(id: id, name: running.localizedName ?? url.deletingPathExtension().lastPathComponent, path: url.path,
                                          regular: running.activationPolicy == .regular)
            }
            for (id, path) in known where found[id] == nil && id != own {
                let url = path.map { URL(fileURLWithPath: $0) } ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
                guard let url else { continue }
                found[id] = TapeAppChoice(id: id, name: url.deletingPathExtension().lastPathComponent, path: url.path)
            }
            let sorted = found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == requested else { return }
                self.apps = sorted
            }
        }
    }
}
