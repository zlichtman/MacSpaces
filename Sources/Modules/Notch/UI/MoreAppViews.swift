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
        service.addReminder(title: title)
        newTitle = ""
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

    var body: some View {
        HStack(spacing: 12) {
            PageCard(title: "Timer", symbol: "timer") {
                NookTimerWidget(service: service, compact: false)
            }
            PageCard(title: "Focus", symbol: "timer.circle") {
                PomodoroWidget(compact: false)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

// MARK: - Clipboard

struct ClipboardAppView: View {
    @ObservedObject var monitor: ClipboardMonitor
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var theme = ThemeStore.shared
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var copiedID: ClipboardEntry.ID?
    @FocusState private var searchFocused: Bool

    var body: some View {
        let matches = monitor.matching(query, favoritesOnly: favoritesOnly)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search clipboard", text: $query)
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
                Menu {
                    Toggle("Keep history after quitting", isOn: Binding(
                        get: { monitor.persistenceEnabled }, set: { monitor.setPersistence($0) }))
                    Divider()
                    Button("Clear Recent Clips") { monitor.clear(keepingFavorites: true) }
                    Button("Clear All, Including Favorites", role: .destructive) { monitor.clear() }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Clipboard options")
            }
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
                        ForEach(matches) { row($0) }
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

    private func row(_ entry: ClipboardEntry) -> some View {
        HStack(spacing: 10) {
            Button {
                monitor.copyToPasteboard(entry)
                withAnimation(.easeOut(duration: 0.15)) { copiedID = entry.id }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if copiedID == entry.id { withAnimation { copiedID = nil } }
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.preview).font(.system(size: 12)).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text([entry.sourceName, entry.date.formatted(date: .omitted, time: .shortened)]
                                .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if copiedID == entry.id {
                        Label("Copied", systemImage: "checkmark").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy again")
            Button { _ = monitor.toggleFavorite(entry) } label: {
                Image(systemName: entry.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(entry.isFavorite ? AnyShapeStyle(theme.notch.accent) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.isFavorite ? "Unfavorite clip" : "Favorite clip")
            Button { monitor.remove(entry) } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }
                .buttonStyle(.plain).accessibilityLabel("Remove clip")
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
