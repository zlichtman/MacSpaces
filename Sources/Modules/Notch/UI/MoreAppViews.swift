import SwiftUI
import AppKit

/// A titled, rounded section used by the multi-card app pages.
private struct PageCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title.uppercased(), systemImage: symbol)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .padding(.top, 9)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        Image(systemName: "checkmark.circle").font(.system(size: 20)).foregroundStyle(.green)
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
        .onAppear { service.startRemindersIfNeeded() }
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
                    .foregroundStyle(done ? Color.green : .secondary)
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

/// The original timer card, without a header: the time says what it is.
private struct TimerCard: View {
    @ObservedObject var timer: TimerService
    let removable: Bool
    let remove: () -> Void

    var body: some View {
        NookTimerWidget(service: timer, compact: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    Button("New Snippet…") { ClipboardActions.newSnippet(monitor) }
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

    var body: some View {
        HStack(spacing: 12) {
            PageCard(title: "System stats", symbol: "chart.xyaxis.line") {
                SystemStatsWidget(service: stats)
            }
            PageCard(title: "Agent power alert", symbol: "bolt.badge.clock") {
                AgentPowerAlertCard(alert: AgentPowerAlert.shared, power: power)
            }
            PageCard(title: "Keep awake", symbol: "cup.and.saucer") {
                KeepAwakeWidget(service: keepAwake)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

/// The switch for the low-battery agent alert, with what it will do and
/// where it's installed.
struct AgentPowerAlertCard: View {
    @ObservedObject var alert: AgentPowerAlert
    @ObservedObject var power: PowerSourceMonitor
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { alert.isEnabled }, set: { alert.setEnabled($0) })) {
                Text("Warn at \(AgentPowerAlert.threshold)%").font(.system(size: 12, weight: .semibold))
            }
            .toggleStyle(.switch).controlSize(.small)
            Text("When this Mac is on battery at \(AgentPowerAlert.threshold)% or less, running Claude Code and Codex sessions are told to save and commit their work and not start long jobs.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let level = alert.alertLevel {
                Label("Agents warned · \(level)%", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
            } else if power.hasBattery && power.hasReading {
                Label("\(power.batteryLevel)% · \(power.statusLabel)", systemImage: power.isCharging ? "bolt.fill" : "battery.75percent")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            if alert.isEnabled {
                VStack(alignment: .leading, spacing: 2) {
                    status("Claude Code", alert.claudeInstalled, "active in open sessions")
                    status("Codex", alert.codexInstalled, "trust once with /hooks; new sessions")
                }
            }
            if let error = alert.error {
                Text(error).font(.system(size: 9)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 10)
    }

    private func status(_ name: String, _ installed: Bool, _ note: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: installed ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(installed ? AnyShapeStyle(theme.notch.accent) : AnyShapeStyle(.tertiary))
            Text(name).fontWeight(.semibold)
            Text(installed ? note : "not found").foregroundStyle(.secondary).lineLimit(1)
        }
        .font(.system(size: 9))
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
            PageCard(title: "Shortcuts", symbol: "bolt.fill") {
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
            PageCard(title: "Quick actions", symbol: "bolt") {
                QuickActionsWidget(columns: 2, showsAll: true)
            }
            .frame(width: 210)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .onAppear { service.startIfNeeded() }
        .onChange(of: search) { _, value in onEditingChanged(!value.isEmpty) }
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
