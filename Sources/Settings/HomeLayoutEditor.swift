import SwiftUI
import UniformTypeIdentifiers

/// Settings → Widgets: profiles, a to-scale preview of Home, the selected
/// widget's size and options, and the widget library.
struct NookSettingsPane: View {
    @ObservedObject private var settings = NookSettings.shared
    @State private var selected: NookWidgetKind?
    @State private var showingLibrary = false

    var body: some View {
        SettingsPage(title: "Widgets", subtitle: "Arrange Home. Small widgets stack in pairs; everything updates live.") {
            ProfileBar(settings: settings)

            SettingsCard("Home layout", systemImage: "square.grid.2x2") {
                HomeLayoutPreview(settings: settings, selected: $selected)
                HStack {
                    Text(settings.widgets.isEmpty
                         ? "This profile is empty. Add a widget to get started."
                         : "Click a widget to change its size or options. Drag to reorder.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { showingLibrary = true } label: { Label("Add Widgets", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                }
            }

            if let selected, settings.widgets.contains(selected) {
                WidgetInspector(kind: selected, settings: settings) { self.selected = nil }
                    .id(selected)
            }

            DockAppsCard(settings: settings)
        }
        .sheet(isPresented: $showingLibrary) {
            WidgetLibrarySheet(settings: settings) { added in
                if let added { selected = added }
                showingLibrary = false
            }
        }
        .onChange(of: settings.activeProfileID) { _ in selected = nil }
    }
}

// MARK: - Profiles

private struct ProfileBar: View {
    @ObservedObject var settings: NookSettings
    @State private var renamingID: UUID?
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        SettingsCard("Profiles", systemImage: "rectangle.3.group") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(settings.profiles) { profile in
                        if renamingID == profile.id {
                            TextField("Profile name", text: $draftName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 150)
                                .focused($nameFocused)
                                .onSubmit(commitRename)
                                .onExitCommand { renamingID = nil }
                        } else {
                            chip(profile)
                        }
                    }
                    Menu {
                        Button("New Empty Profile") {
                            settings.addProfile(named: uniqueName("Profile"))
                        }
                        Button("Duplicate \(settings.activeProfile.name)") {
                            settings.addProfile(named: uniqueName(settings.activeProfile.name + " Copy"), copyingCurrent: true)
                        }
                    } label: {
                        Image(systemName: "plus").frame(width: 28, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("New profile")
                }
                .padding(.vertical, 2)
            }
            Text("Each profile keeps its own widgets and sizes. With two or more, the Nook gets a dock with one button per profile. Right-click a profile to rename it, change its icon or delete it.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func chip(_ profile: NookProfile) -> some View {
        let active = profile.id == settings.activeProfileID
        let count = profile.widgets.count
        return Button { settings.activeProfileID = profile.id } label: {
            HStack(spacing: 6) {
                Image(systemName: settings.symbol(for: profile)).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(active ? ThemeStore.shared.notch.accent : .secondary)
                Text(profile.name).font(.system(size: 12, weight: active ? .semibold : .medium)).lineLimit(1)
                Text("\(count)").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.primary.opacity(0.10), in: Capsule())
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(active ? ThemeStore.shared.notch.selected : Color.primary.opacity(0.05), in: Capsule())
            .overlay { Capsule().strokeBorder(active ? ThemeStore.shared.notch.accent : .clear, lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename…") { beginRename(profile) }
            Menu("Icon") {
                ForEach(NookProfile.symbols, id: \.self) { symbol in
                    Button { settings.setSymbol(symbol, for: profile) } label: {
                        Label(symbol == settings.symbol(for: profile) ? "Current" : " ", systemImage: symbol)
                    }
                }
            }
            Button("Duplicate") {
                settings.activeProfileID = profile.id
                settings.addProfile(named: uniqueName(profile.name + " Copy"), copyingCurrent: true)
            }
            Divider()
            Button("Delete", role: .destructive) { settings.removeProfile(profile) }
                .disabled(settings.profiles.count == 1)
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { beginRename(profile) })
        .help(active ? "Active profile. Double-click to rename." : "Switch to \(profile.name)")
    }

    private func beginRename(_ profile: NookProfile) {
        draftName = profile.name
        renamingID = profile.id
        DispatchQueue.main.async { nameFocused = true }
    }

    private func commitRename() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = renamingID, !name.isEmpty, let profile = settings.profiles.first(where: { $0.id == id }) {
            settings.renameProfile(profile, to: name)
        }
        renamingID = nil
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(settings.profiles.map(\.name))
        guard names.contains(base) else { return base }
        var index = 2
        while names.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }
}

// MARK: - Preview

/// A miniature of Home drawn from the same layout rules as the Nook, so
/// stacks and widths match what opens from the notch.
private struct HomeLayoutPreview: View {
    @ObservedObject var settings: NookSettings
    @Binding var selected: NookWidgetKind?
    @ObservedObject private var theme = ThemeStore.shared
    @State private var dragged: NookWidgetKind?

    private let spacing: CGFloat = 10
    private let tileHeight: CGFloat = 250

    var body: some View {
        let tiles = settings.widgets.filter { !$0.isQuickBar }
        let bars = settings.widgets.filter(\.isQuickBar)
        let columns = tiles.nookLayoutItems(sizes: settings.widgetSizes)
        let natural = columns.reduce(CGFloat.zero) { $0 + $1.width } + CGFloat(max(0, columns.count - 1)) * spacing

        GeometryReader { proxy in
            let available = proxy.size.width - 28
            let scale = natural > 0 ? min(0.62, available / natural) : 0.62
            VStack(spacing: 8 * scale) {
                if columns.isEmpty {
                    Text("No widgets")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(alignment: .top, spacing: spacing * scale) {
                        ForEach(columns) { column in
                            VStack(spacing: spacing * scale) {
                                ForEach(column.kinds) { kind in
                                    tile(kind, width: column.width * scale,
                                         height: (column.isStack ? (tileHeight - spacing) / 2 : tileHeight) * scale,
                                         scale: scale)
                                }
                            }
                        }
                    }
                    ForEach(bars) { kind in
                        tile(kind, width: max(natural * scale, 200), height: 26, scale: scale)
                    }
                }
            }
            .padding(14)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(theme.notch.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(theme.notch.border.opacity(0.6), lineWidth: 1)
            }
            .environment(\.colorScheme, theme.notch.colorScheme)
            .foregroundStyle(theme.nookForeground)
            .animation(Design.spring(), value: settings.widgets)
            .animation(Design.spring(), value: settings.widgetSizes)
        }
        .frame(height: 210 + CGFloat(bars.count) * 32)
    }

    private func tile(_ kind: NookWidgetKind, width: CGFloat, height: CGFloat, scale: CGFloat) -> some View {
        let isSelected = selected == kind
        let size = settings.size(for: kind)
        return Button { selected = isSelected ? nil : kind } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: kind.systemImage).foregroundStyle(theme.notch.accent)
                    if width > 70 {
                        Text(kind.title).lineLimit(1).minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10, weight: .semibold))
                Spacer(minLength: 0)
                if height > 40, !kind.isQuickBar {
                    Text(size.title.uppercased())
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .frame(width: width, height: height, alignment: .topLeading)
            .background(theme.notch.tile, in: RoundedRectangle(cornerRadius: 12 * max(scale, 0.6), style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12 * max(scale, 0.6), style: .continuous)
                    .strokeBorder(isSelected ? theme.notch.accent : theme.notch.border.opacity(0.5), lineWidth: isSelected ? 2 : 1)
            }
            .opacity(dragged == kind ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind.title), \(size.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onDrag {
            dragged = kind
            return NSItemProvider(object: kind.rawValue as NSString)
        }
        .onDrop(of: [UTType.text], delegate: PreviewDropDelegate(target: kind, dragged: $dragged, settings: settings))
    }
}

private struct PreviewDropDelegate: DropDelegate {
    let target: NookWidgetKind
    @Binding var dragged: NookWidgetKind?
    let settings: NookSettings

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target else { return }
        withAnimation(Design.spring()) { settings.moveWidget(dragged, to: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}

// MARK: - Inspector

private struct WidgetInspector: View {
    let kind: NookWidgetKind
    @ObservedObject var settings: NookSettings
    let onRemove: () -> Void
    @ObservedObject private var options = WidgetOptions.shared
    @ObservedObject private var clipboard = AppServices.shared.clipboard

    var body: some View {
        SettingsCard(kind.title, systemImage: kind.systemImage) {
            Text(kind.descriptor.summary).font(.caption).foregroundStyle(.secondary)

            if kind.supportedSizes.count > 1 {
                HStack {
                    Text("Size")
                    Spacer()
                    Picker("Size", selection: Binding(
                        get: { settings.size(for: kind) },
                        set: { size in withAnimation(Design.spring()) { settings.setSize(size, for: kind) } }
                    )) {
                        ForEach(kind.supportedSizes) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                Text(sizeHint).font(.caption).foregroundStyle(.secondary)
            }

            kindOptions

            Divider()
            HStack {
                Button { settings.moveWidget(kind, offset: -1) } label: { Label("Earlier", systemImage: "arrow.left") }
                    .disabled(settings.widgets.first == kind)
                Button { settings.moveWidget(kind, offset: 1) } label: { Label("Later", systemImage: "arrow.right") }
                    .disabled(settings.widgets.last == kind)
                Spacer()
                Button("Remove from Home", role: .destructive) {
                    settings.setEnabled(false, for: kind)
                    onRemove()
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private var sizeHint: String {
        switch settings.size(for: kind) {
        case .small: return "Small widgets share a column with the small widget next to them."
        case .medium: return "Medium takes a full-height column."
        case .large: return "Large is wider and shows more detail where the widget supports it."
        }
    }

    @ViewBuilder
    private var kindOptions: some View {
        switch kind {
        case .clock:
            Toggle("24-hour time", isOn: $options.clockUses24Hour)
            Toggle("Show seconds", isOn: $options.clockShowsSeconds)
            Picker("Second clock", selection: $options.clockSecondTimeZone) {
                Text("None").tag("")
                ForEach(WidgetOptions.worldClockZones.filter { $0.identifier != TimeZone.current.identifier }, id: \.identifier) {
                    Text($0.title).tag($0.identifier)
                }
            }
            Text("The second clock appears on Medium and Large clocks.").font(.caption).foregroundStyle(.secondary)
        case .weather:
            Picker("Temperature", selection: $options.temperatureUnit) {
                ForEach(WidgetOptions.TemperatureUnit.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Large weather shows the next four days.").font(.caption).foregroundStyle(.secondary)
        case .pomodoro:
            Picker("Focus length", selection: $options.focusMinutes) {
                ForEach([15, 20, 25, 30, 45, 50, 60, 90], id: \.self) { Text("\($0) minutes").tag($0) }
            }
            Picker("Break length", selection: $options.breakMinutes) {
                ForEach([3, 5, 10, 15, 20], id: \.self) { Text("\($0) minutes").tag($0) }
            }
        case .timer:
            ForEach(0..<3, id: \.self) { index in
                Picker("Preset \(index + 1)", selection: Binding(
                    get: { options.timerPresets[safe: index] ?? 5 },
                    set: { value in
                        var presets = options.timerPresets
                        while presets.count < 3 { presets.append(5) }
                        presets[index] = value
                        options.timerPresets = presets
                    }
                )) {
                    ForEach(WidgetOptions.timerPresetChoices, id: \.self) { Text("\($0) min").tag($0) }
                }
            }
        case .clipboard:
            Toggle("Keep history after quitting", isOn: Binding(
                get: { clipboard.persistenceEnabled }, set: { clipboard.setPersistence($0) }))
            Text("Password-manager and other concealed copies are never recorded.")
                .font(.caption).foregroundStyle(.secondary)
        case .media:
            Text("Click the artwork to open the playing app. The Music tab in the dock has the full player and lyrics.")
                .font(.caption).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Library

private struct WidgetLibrarySheet: View {
    @ObservedObject var settings: NookSettings
    let done: (NookWidgetKind?) -> Void
    @State private var search = ""
    @State private var lastAdded: NookWidgetKind?

    private static let groups: [(String, [NookWidgetKind])] = [
        ("Listen", [.media]),
        ("Plan", [.calendar, .todos, .weather, .clock]),
        ("Focus", [.timer, .pomodoro, .notes, .keepAwake]),
        ("Tools", [.terminal, .clipboard, .shortcuts, .quickActions]),
        ("Status", [.battery, .systemStats, .mirror]),
        ("In development", [.notifications])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Add Widgets").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { done(lastAdded) }.keyboardShortcut(.defaultAction)
            }
            TextField("Search widgets", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Self.groups, id: \.0) { group in
                        let kinds = group.1.filter(matches)
                            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                        if !kinds.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.0).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(kinds) { row($0) }
                            }
                        }
                    }
                }
            }
            Text("Widgets are added to \(settings.activeProfile.name) and appear on Home right away.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 560, height: 520)
    }

    private func matches(_ kind: NookWidgetKind) -> Bool {
        search.isEmpty || kind.title.localizedCaseInsensitiveContains(search)
            || kind.descriptor.summary.localizedCaseInsensitiveContains(search)
    }

    private func row(_ kind: NookWidgetKind) -> some View {
        let included = settings.widgets.contains(kind)
        return HStack(spacing: 12) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ThemeStore.shared.notch.accent)
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.system(size: 13, weight: .medium))
                Text(kind.descriptor.summary + permissionNote(kind))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button(included ? "Remove" : "Add") {
                settings.setEnabled(!included, for: kind)
                if !included { lastAdded = kind }
            }
            .buttonStyle(.bordered)
            .tint(included ? .secondary : ThemeStore.shared.notch.accent)
        }
        .padding(.vertical, 3)
    }

    private func permissionNote(_ kind: NookWidgetKind) -> String {
        let names = kind.descriptor.permissions.compactMap { permission -> String? in
            switch permission {
            case .camera: return "Camera"
            case .calendar: return "Calendars"
            case .reminders: return "Reminders"
            case .location: return "Location (optional)"
            case .automation: return "Automation"
            case .audioCapture: return "Audio capture"
            case .fullDiskAccess: return "Full Disk Access"
            default: return nil
            }
        }.sorted()
        return names.isEmpty ? "" : " Asks for: " + names.joined(separator: ", ") + "."
    }
}

// MARK: - Dock

/// Which app pages sit in the dock under the Nook, and in what order.
private struct DockAppsCard: View {
    @ObservedObject var settings: NookSettings
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        SettingsCard("Dock", systemImage: "dock.rectangle") {
            Text("Choose the app pages under the Nook. Home and Settings are always there.")
                .font(.caption).foregroundStyle(.secondary)
            let shown = settings.dockApps
            let hidden = NotchTab.appPages.filter { !shown.contains($0) }
            ForEach(shown) { page in row(page, shown: true) }
            if !hidden.isEmpty {
                Text("More pages").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
                ForEach(hidden) { page in row(page, shown: false) }
            }
        }
    }

    private func row(_ page: NotchTab, shown: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: page.systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(shown ? theme.notch.accent : .secondary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title).font(.system(size: 13, weight: .medium))
                Text(page.summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if shown {
                Button { withAnimation { settings.moveDockApp(page, offset: -1) } } label: { Image(systemName: "chevron.up") }
                    .disabled(settings.dockApps.first == page).help("Move earlier")
                Button { withAnimation { settings.moveDockApp(page, offset: 1) } } label: { Image(systemName: "chevron.down") }
                    .disabled(settings.dockApps.last == page).help("Move later")
            }
            Toggle("", isOn: Binding(get: { shown }, set: { value in
                withAnimation { settings.setDockApp(page, shown: value) }
            }))
            .toggleStyle(.switch).labelsHidden().controlSize(.small)
            .accessibilityLabel("Show \(page.title) in the dock")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 2)
    }
}
