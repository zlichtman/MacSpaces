import SwiftUI
import AppKit

/// A section of the multi-card app pages, titled only where its content doesn't
/// already say what it is.
private struct PageCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: Content
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.3)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 11)
                    .padding(.top, 9)
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Sections sit straight on the Nook, set apart by spacing alone (owner, 2.100).
    }
}

// MARK: - Reminders

struct RemindersAppView: View {
    @ObservedObject var service: CalendarService
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var theme = ThemeStore.shared
    @State private var newTitle = ""
    @State private var completing: Set<String> = []
    @FocusState private var addFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Reminders").font(.system(size: 15, weight: .bold))
                Text(service.reminders.isEmpty ? "All done" : "\(service.reminders.count) open")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(WidgetChipStyle(height: 22)).help("Open Reminders")
            }
            if let error = service.reminderError {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if service.remindersAccessDenied {
                VStack(spacing: 8) {
                    Label("Allow Reminders access to see your list here.", systemImage: "checklist.unchecked")
                        .foregroundStyle(.secondary)
                    Button("Open Permissions") { SettingsWindowController.shared.show(.permissions) }
                        .buttonStyle(WidgetChipStyle(height: 26))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(theme.notch.accent)
                    TextField("New reminder", text: $newTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($addFocused)
                        .onSubmit(add)
                    if !newTitle.isEmpty {
                        Button("Add", action: add).buttonStyle(WidgetChipStyle(prominent: true, height: 22))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                if service.reminders.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle").font(.system(size: 20)).foregroundStyle(theme.notch.accent)
                        Text("Nothing left to do").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 4) {
                            ForEach(service.reminders) { row($0) }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .nookAfterOpening { service.startRemindersIfNeeded() }
        .onChange(of: addFocused) { onEditingChanged($0) }
        .onDisappear { onEditingChanged(false) }
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if service.addReminder(title: title) { newTitle = "" }
    }

    private func row(_ item: TodoItem) -> some View {
        let done = completing.contains(item.id)
        let overdue = item.dueDate.map { $0 < Date() } ?? false
        return HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { _ = completing.insert(item.id) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    service.complete(item)
                    completing.remove(item.id)
                }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(done ? theme.notch.accent : .secondary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(item.title)")
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13)).lineLimit(1)
                    .strikethrough(done).foregroundStyle(done ? .secondary : .primary)
                if let due = item.dueDate {
                    Text(due, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                        .font(.system(size: 10)).foregroundStyle(overdue ? Color.red : .secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Timers

struct TimersAppView: View {
    @ObservedObject var service: TimerService
    /// How many timer cards show (1–3); extra timers keep their state when hidden.
    @AppStorage("timers.count") private var count = 1

    @AppStorage("timers.pageFocus") private var focus = false
    var body: some View {
        let timers = Array(AppServices.shared.allTimers.prefix(max(1, min(3, count))))
        VStack(spacing: 8) {
            HStack { Button("Timers") { focus = false }.buttonStyle(WidgetChipStyle(prominent: !focus)); Button("Focus") { focus = true }.buttonStyle(WidgetChipStyle(prominent: focus)); Spacer() }
            if focus { PomodoroWidget() } else {
        HStack(spacing: 12) {
            ForEach(timers, id: \.slot) { timer in
                TimerCard(timer: timer, removable: timer.slot > 0 && timer.slot == timers.count - 1) {
                    timer.cancel(); count -= 1
                }
            }
            if timers.count < 3 {
                Button { count = timers.count + 1 } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                        Text("Add Timer").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: timers.count == 1 ? .infinity : 120, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add another timer (up to three)")
            }
        }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

/// A timer card, without a header: the time says what it is. A running timer is the Home
/// widget's compact timer (its ring, the time, pause, +1 and ×) centred on a quiet tile; a
/// stopped one keeps the full picker (a length, Start and the presets).
private struct TimerCard: View {
    @ObservedObject var timer: TimerService
    let removable: Bool
    let remove: () -> Void

    var body: some View {
        Group {
            if timer.isRunning {
                NookTimerWidget(service: timer, compact: true)
                    .fixedSize()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                NookTimerWidget(service: timer, compact: false)
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contextMenu {
                if removable { Button("Remove Timer", role: .destructive, action: remove) }
            }
    }
}

// MARK: - Clipboard

struct ClipboardAppView: View {
    @ObservedObject var monitor: ClipboardMonitor
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var theme = ThemeStore.shared
    /// Sort order, search mode and pin position change the list.
    @ObservedObject private var preferences = ClipboardPreferences.shared
    @State private var query = ""
    @State private var favoritesOnly = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        let matches = monitor.matching(query, favoritesOnly: favoritesOnly)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search, or @image, @link, @app, #collection", text: $query)
                        .textFieldStyle(.plain).font(.system(size: 13))
                        .focused($searchFocused)
                }
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Button { favoritesOnly.toggle() } label: {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                }
                .buttonStyle(WidgetChipStyle(prominent: favoritesOnly, height: 30))
                .help("Favorites only")
                Button { monitor.setQueueEnabled(!monitor.queueEnabled) } label: {
                    Image(systemName: "list.number")
                }
                .buttonStyle(WidgetChipStyle(prominent: monitor.queueEnabled, height: 30))
                .help("Paste queue: copy several clips, then each ⌘V pastes the next")
                .accessibilityLabel(monitor.queueEnabled ? "Turn off paste queue" : "Turn on paste queue")
                Menu {
                    Button("New Snippet") { ClipboardActions.newSnippet(monitor) }
                    Button("Pick Colour from Screen") { monitor.pickColor() }
                    Divider()
                    Toggle("Keep history after quitting", isOn: Binding(
                        get: { monitor.persistenceEnabled }, set: { monitor.setPersistence($0) }))
                    Divider()
                    Button("Clear Recent Clips") { monitor.clear(keepingFavorites: true) }
                    Button("Clear All, Including Favorites", role: .destructive) { monitor.clear() }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Clipboard options")
            }
            if monitor.queueEnabled { PasteQueueCard(monitor: monitor) }
            if matches.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 20)).foregroundStyle(.secondary)
                    Text(monitor.entries.isEmpty ? "Copied text and links appear here." : "No matching clips.")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(matches) { ClipListRow(entry: $0, monitor: monitor, detailed: true) }
                    }
                }
            }
            if let notice = monitor.notice {
                Text(notice).font(.caption2).foregroundStyle(.secondary)
            }
            if let error = monitor.storageError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: searchFocused) { onEditingChanged($0) }
        .onDisappear { onEditingChanged(false) }
    }
}

/// The paste queue's clips in the order ⌘V will paste them.
struct PasteQueueCard: View {
    @ObservedObject var monitor: ClipboardMonitor
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        let ordered = monitor.queue.order == .inOrder ? monitor.queue.items : monitor.queue.items.reversed()
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "list.number").foregroundStyle(theme.notch.accent)
                Text(monitor.queue.isEmpty ? "Copy clips to queue them" : "\(monitor.queue.count) to paste")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker("Order", selection: Binding(get: { monitor.queue.order }, set: { monitor.setQueueOrder($0) })) {
                    ForEach(PasteQueue.Order.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                if !monitor.queue.isEmpty {
                    Button("Clear") { monitor.clearQueue() }.buttonStyle(WidgetChipStyle(height: 22))
                }
            }
            if monitor.queueNeedsAccess {
                HStack(spacing: 8) {
                    Text("Allow MacSpaces in Accessibility so ⌘V moves to the next clip.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Open Settings") { monitor.openAccessibilitySettings() }.buttonStyle(WidgetChipStyle(height: 22))
                }
            }
            if !ordered.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(Array(ordered.enumerated()), id: \.element.id) { index, entry in
                            HStack(spacing: 5) {
                                Text("\(index + 1)").font(.system(size: 9, weight: .bold)).monospacedDigit()
                                    .foregroundStyle(index == 0 ? theme.notch.accent : .secondary)
                                Text(entry.preview).font(.system(size: 11)).lineLimit(1).frame(maxWidth: 140, alignment: .leading)
                                Button { monitor.removeFromQueue(entry) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Remove from queue")
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.primary.opacity(index == 0 ? 0.1 : 0.05), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.notch.accent.opacity(0.35)))
    }
}

// MARK: - System

struct SystemAppView: View {
    @ObservedObject var stats: SystemStatsService
    @ObservedObject var power: PowerSourceMonitor
    @ObservedObject var bluetooth: BluetoothMonitor
    @ObservedObject var keepAwake: KeepAwakeService
    /// The battery popover is open (the Nook stays open while it is).
    var onDetailsChanged: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                OvertimeCard(alert: AgentPowerAlert.shared, lid: LidClosedAwake.shared, keepAwake: keepAwake, compact: true)
                    .frame(maxWidth: .infinity)
                CableManagementCard(power: power, input: power.input, bluetooth: bluetooth, compact: true)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            Divider().opacity(0.35)
            SystemStatsWidget(service: stats, detailed: true, horizontal: true, power: power,
                              bluetooth: bluetooth, onBatteryDetailsChanged: onDetailsChanged)
                .frame(height: 82, alignment: .top)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

}

/// Everything that keeps work going: agents warned at low battery, running with the
/// lid closed, and keeping this Mac (and optionally its display) awake for a while.
struct OvertimeCard: View {
    @ObservedObject var alert: AgentPowerAlert
    @ObservedObject var lid: LidClosedAwake
    @ObservedObject var keepAwake: KeepAwakeService
    var compact = false
    @ObservedObject private var theme = ThemeStore.shared
    @State private var minutes = 60
    @State private var displayToo = false

    private static let durations: [(label: String, minutes: Int)] = [("15m", 15), ("1h", 60), ("2h", 120), ("∞", 0)]

    var body: some View {
        VStack(spacing: 0) {
            row(symbol: "bell", title: "Low battery",
                detail: alert.alertLevel.map { "Agents warned at \($0)%" } ?? "Agents wrap up at \(AgentPowerAlert.threshold)%",
                warning: alert.alertLevel != nil,
                isOn: Binding(get: { alert.isEnabled }, set: { alert.setEnabled($0) }),
                help: "On battery at \(AgentPowerAlert.threshold)% or less, running Claude Code and Codex sessions are told to save and commit their work and not start long jobs. Codex asks you to trust the hook once with /hooks.")
            Divider().opacity(0.5)
            row(symbol: "laptopcomputer", title: "Agents keep running",
                detail: lidDetail,
                warning: false,
                isOn: Binding(get: { lid.isEnabled }, set: { lid.setEnabled($0) }),
                help: lidHelp) {
                    switch lid.helper {
                    case .notInstalled:
                        Button("Skip the password") { lid.installHelper() }
                            .buttonStyle(WidgetChipStyle(prominent: false, height: 18))
                            .help("Adds a small MacSpaces helper that you allow once in System Settings → General → Login Items. After that this switch changes without your password.")
                    case .needsApproval:
                        Button("Allow in Login Items") { lid.openLoginItems() }
                            .buttonStyle(WidgetChipStyle(prominent: true, height: 18))
                            .help("Turn on MacSpaces in System Settings → General → Login Items (Allow in the Background) so this switch needs no password.")
                    case .ready, .unavailable:
                        EmptyView()
                    }
                }
                .disabled(lid.isChanging)
                .contextMenu {
                    if lid.helper == .ready || lid.helper == .needsApproval {
                        Button("Open Login Items") { lid.openLoginItems() }
                        Button("Remove Helper") { lid.removeHelper() }
                    } else if lid.helper == .notInstalled {
                        Button("Set Up Helper") { lid.installHelper() }
                    }
                }
                .onAppear { lid.refresh() }
            Divider().opacity(0.5)
            row(symbol: keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer", title: "Keep awake",
                detail: nil, warning: false,
                isOn: Binding(get: { keepAwake.isActive },
                              set: { on in on ? keepAwake.start(mode: displayToo ? .display : .system, minutes: minutes == 0 ? nil : minutes) : keepAwake.stop() }),
                help: "Stops this Mac from going to sleep while idle, for the time you choose.") {
                    if keepAwake.isActive {
                        Group {
                            if let end = keepAwake.expiresAt { Text(end, style: .timer) } else { Text("Until you stop it") }
                        }
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    } else {
                        HStack(spacing: 4) {
                            ForEach(Self.durations, id: \.minutes) { option in
                                Button(option.label) { minutes = option.minutes }
                                    .buttonStyle(WidgetChipStyle(prominent: minutes == option.minutes, height: 18))
                                    .help(option.minutes == 0 ? "Until you stop it" : "For \(option.label)")
                            }
                            Button { displayToo.toggle() } label: {
                                Image(systemName: "display")
                            }
                            .buttonStyle(WidgetChipStyle(prominent: displayToo, height: 18))
                            .help(displayToo ? "The display stays on too" : "Keep the display on too")
                            .accessibilityLabel("Keep display on")
                        }
                    }
                }
            if let error = alert.error ?? lid.error ?? keepAwake.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2).padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 8)
    }

    private var lidDetail: String {
        if lid.isChanging { return lid.helper == .ready ? "Switching…" : "Waiting for your password…" }
        return lid.isEnabled ? "Working with the lid closed" : "Off: closing the lid sleeps"
    }

    private var lidHelp: String {
        let how = lid.helper == .ready
            ? "The MacSpaces helper (allowed in Login Items) changes it without a password; right-click to remove it."
            : "macOS asks for your administrator password each time this changes, unless you set up the helper."
        return "Keeps this Mac and its agents working with the lid closed, like lid-closed keep-awake apps. \(how) It stays on until you turn it off or quit MacSpaces, and turns itself off on battery at \(AgentPowerAlert.threshold)%."
    }

    private func row(symbol: String, title: String, detail: String?, warning: Bool, isOn: Binding<Bool>, help: String) -> some View {
        row(symbol: symbol, title: title, detail: detail, warning: warning, isOn: isOn, help: help) { EmptyView() }
    }

    private func row<Extra: View>(symbol: String, title: String, detail: String?, warning: Bool, isOn: Binding<Bool>,
                                  help: String, @ViewBuilder extra: () -> Extra) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOn.wrappedValue ? AnyShapeStyle(warning ? Color.orange : theme.notch.accent) : AnyShapeStyle(.secondary))
                .frame(width: compact ? 26 : 30, height: compact ? 26 : 30)
                .background((isOn.wrappedValue ? theme.notch.accent.opacity(0.14) : Color.primary.opacity(0.06)), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .semibold))
                if let detail {
                    Text(detail).font(.system(size: compact ? 10 : 11)).foregroundStyle(warning ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
                extra()
            }
            Spacer(minLength: 4)
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }
        .padding(.vertical, compact ? 4 : 6)
        .frame(height: compact ? 64 : nil)
        .contentShape(Rectangle())
        .help(help)
    }
}

// MARK: - Shortcuts

/// Every Apple Shortcut with search, beside the Mac quick actions.
struct ShortcutsAppView: View {
    @ObservedObject var service: ShortcutsService
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var theme = ThemeStore.shared
    @State private var search = ""

    private var matches: [String] {
        search.isEmpty ? service.names : service.names.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HStack(spacing: 12) {
            PageCard(title: "Shortcuts") {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.secondary)
                        TextField("Search shortcuts", text: $search)
                            .textFieldStyle(.plain).font(.system(size: 11))
                        RefreshButton { service.refresh() }
                            .buttonStyle(.plain)
                            .help("Refresh shortcuts")
                    }
                    .padding(.horizontal, 9).frame(height: 26)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                    if let name = service.runningName {
                        HStack { Text("Running " + name).font(.caption).lineLimit(1); Spacer(); Button("Cancel") { service.cancel() } }
                    }
                    list
                }
                .padding(.horizontal, 10).padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity)
            PageCard(title: "Quick actions") {
                QuickActionsWidget(columns: 2, showsAll: true)
            }
            .frame(width: 210)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .nookAfterOpening { service.startIfNeeded() }
        .onChange(of: search) { value in onEditingChanged(!value.isEmpty) }
        .onDisappear { onEditingChanged(false) }
    }

    @ViewBuilder
    private var list: some View {
        if service.isLoading && service.names.isEmpty {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if matches.isEmpty {
            Text(service.errorText ?? (service.names.isEmpty ? "No shortcuts yet" : "No matches"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(matches, id: \.self) { name in
                        Button { service.run(name) } label: {
                            HStack(spacing: 7) {
                                Image(systemName: service.runningName == name ? "progress.indicator" : "play.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(theme.notch.accent)
                                Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10).frame(height: 30)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(PremiumPressButtonStyle())
                        .disabled(service.runningName != nil)
                        .help("Run \(name)")
                    }
                }
            }
        }
    }
}

// MARK: - Mirror

/// A larger camera preview for a quick check before a call. The camera runs
/// only while this page is showing.
struct MirrorAppView: View {
    var body: some View {
        MirrorView()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20).padding(.vertical, 12)
    }
}
