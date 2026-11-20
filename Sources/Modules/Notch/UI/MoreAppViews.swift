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
                // Without access the list is empty, not done, so there's no count to show.
                if !service.remindersAccessDenied && !service.remindersNeedAccess {
                    Text(service.reminders.isEmpty ? "All done" : "\(service.reminders.count) open")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
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
            if service.remindersAccessDenied || service.remindersNeedAccess {
                VStack(spacing: 8) {
                    Label("Allow Reminders access to see your list here.", systemImage: "checklist.unchecked")
                        .foregroundStyle(.secondary)
                    if service.remindersNeedAccess {
                        Button("Allow Reminders") { service.allowReminders() }
                            .buttonStyle(WidgetChipStyle(prominent: true, height: 26))
                    } else {
                        Button("Open Permissions") { SettingsWindowController.shared.show(.permissions) }
                            .buttonStyle(WidgetChipStyle(height: 26))
                    }
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
        let overdue = item.isOverdue()
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
                    Text(due, format: item.dueFormat.weekday(.abbreviated))
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

/// One page for every timer. A length starts a new one, which spins out beside the notch; Focus
/// and Notch say how the next one starts, and each card can change its own.
struct TimersAppView: View {
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var pool = AppServices.shared.timerPool
    @ObservedObject private var options = WidgetOptions.shared
    @ObservedObject private var focus = TimerFocus.shared
    @ObservedObject private var theme = ThemeStore.shared
    @AppStorage(WidgetOptions.Keys.timersNextFocus) private var nextFocus = false
    @AppStorage(WidgetOptions.Keys.timersNextHidden) private var nextHidden = false
    @State private var choosingLength = false
    @State private var customMinutes = 10

    private var lengths: [Int] { Array(Set([1, 45] + options.timerPresets)).sorted() }
    private var isFull: Bool { pool.running.count >= TimerService.poolSize }

    var body: some View {
        let running = pool.running
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Timers").font(.system(size: 15, weight: .bold))
                Text(running.isEmpty ? "None running" : "\(running.count) running")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                // Lit only once the two Focus shortcuts exist; without them a tap shows the setup.
                let moonOn = nextFocus && focus.isSetUp
                Button {
                    if moonOn { nextFocus = false } else { focus.turnMoonOn { nextFocus = true } }
                } label: { Label("Focus", systemImage: moonOn ? "moon.fill" : "moon") }
                    .buttonStyle(WidgetChipStyle(prominent: moonOn, height: 22))
                    .help(moonOn ? "The next timer turns on Do Not Disturb" : "Turn on Do Not Disturb with the next timer")
                // Every running timer at once, and how the next one starts; a card's eye is for one.
                Button {
                    nextHidden.toggle()
                    for timer in running { timer.showsInNotch = !nextHidden }
                } label: {
                    Label("Notch", systemImage: nextHidden ? "eye.slash" : "eye")
                }
                .buttonStyle(WidgetChipStyle(height: 22))
                .help(nextHidden ? "Timers stay out of the notch until they end. Click to show them" : "Timers show beside the notch. Click to hide them")
            }
            HStack(spacing: 6) {
                ForEach(lengths, id: \.self) { minutes in
                    Button("\(minutes)m") { start(minutes: minutes) }
                        .buttonStyle(WidgetChipStyle(height: 26))
                        .help("Start a \(minutes)-minute timer")
                }
                Button { choosingLength = true } label: { Label("Custom", systemImage: "plus") }
                    .buttonStyle(WidgetChipStyle(height: 26))
                    .nookPopover(isPresented: $choosingLength, arrowEdge: .bottom) { customLength }
            }
            .disabled(isFull)
            .opacity(isFull ? 0.45 : 1)
            if let problem = focus.problem {
                Text(problem).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(1)
            }
            if running.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "timer").font(.system(size: 20)).foregroundStyle(theme.notch.accent)
                    Text("Pick a length to start a timer").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                cards(running)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { if nextFocus || running.contains(where: \.focus) { focus.checkSetup() } }
        .onDisappear { onEditingChanged(false) }
    }

    /// The cards fill the page: a row or two share its height, so there's no empty space under
    /// them, and one to three timers get large cards. Past two rows, the rest scroll.
    private func cards(_ running: [TimerService]) -> some View {
        GeometryReader { proxy in
            let gap: CGFloat = 8
            let columns = min(3, running.count)
            let rows = (running.count + 2) / 3
            let shared = (proxy.size.height - gap * CGFloat(min(rows, 2) - 1)) / CGFloat(min(rows, 2))
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: columns), spacing: gap) {
                    ForEach(running, id: \.slot) { timer in
                        TimerCard(timer: timer, large: rows == 1, onEditingChanged: onEditingChanged)
                            .frame(height: shared)
                    }
                }
            }
        }
    }

    private func start(minutes: Int) {
        AppServices.shared.startTimer(seconds: TimeInterval(minutes * 60), focus: nextFocus, showsInNotch: !nextHidden)
    }

    /// A length of your own: minutes up to ten, then fives.
    private var customLength: some View {
        HStack(spacing: 6) {
            Button { adjustCustom(-1) } label: { Image(systemName: "minus") }
                .buttonStyle(WidgetChipStyle(height: 26)).help("Shorter")
            Text(customMinutes >= 60 ? String(format: "%d:%02d:00", customMinutes / 60, customMinutes % 60) : "\(customMinutes):00")
                .font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                .frame(minWidth: 64)
            Button { adjustCustom(1) } label: { Image(systemName: "plus") }
                .buttonStyle(WidgetChipStyle(height: 26)).help("Longer")
            Button {
                choosingLength = false
                start(minutes: customMinutes)
            } label: { Image(systemName: "play.fill") }
                .buttonStyle(WidgetChipStyle(prominent: true, height: 26))
                .help("Start")
                .accessibilityLabel("Start timer")
        }
        .padding(12)
    }

    private func adjustCustom(_ direction: Int) {
        let step = (direction > 0 ? customMinutes >= 10 : customMinutes > 10) ? 5 : 1
        customMinutes = min(max(customMinutes + direction * step, 1), 180)
    }
}

/// One running timer: its ring, time and name, then what it can do. `large` when there's a row of
/// them to fill the page, the time inside the ring. Each control is the same small square, so a
/// row of them never shifts as one changes.
private struct TimerCard: View {
    @ObservedObject var timer: TimerService
    var large = false
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var focus = TimerFocus.shared
    @State private var choosingColour = false
    @State private var choosingCustom = false
    @FocusState private var editingName: Bool

    private var nameField: some View {
        TextField("Timer", text: $timer.name)
            .textFieldStyle(.plain)
            .font(.system(size: large ? 12 : 11, weight: .medium))
            .multilineTextAlignment(large ? .center : .leading)
            .foregroundStyle(.secondary)
            .focused($editingName)
            .onSubmit { editingName = false }
    }

    private var time: some View {
        Text(timer.remainingText)
            .font(.system(size: large ? 26 : 19, weight: .semibold, design: .rounded)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.7)
            .opacity(timer.isPaused ? 0.55 : 1)
    }

    var body: some View {
        VStack(alignment: large ? .center : .leading, spacing: 8) {
            if large {
                Spacer(minLength: 0)
                ZStack {
                    WidgetRing(progress: timer.progress, tint: timer.tint, lineWidth: 6)
                    time.padding(10)
                }
                .frame(maxWidth: 104, maxHeight: 104)
                nameField
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                HStack(spacing: 9) {
                    WidgetRing(progress: timer.progress, tint: timer.tint, lineWidth: 4).frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        time
                        nameField
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 2) {
                Button { choosingColour = true } label: {
                    Circle().fill(timer.tint).frame(width: 12, height: 12)
                }
                .buttonStyle(TimerControlStyle())
                .help("Colour")
                .accessibilityLabel("Colour")
                .nookPopover(isPresented: $choosingColour, arrowEdge: .bottom) { palette }
                Button { timer.showsInNotch.toggle() } label: {
                    Image(systemName: timer.showsInNotch ? "eye" : "eye.slash")
                }
                .buttonStyle(TimerControlStyle())
                .help(timer.showsInNotch ? "Showing beside the notch" : "Stays out of the notch until it ends")
                .accessibilityLabel("Show beside the notch")
                .accessibilityValue(timer.showsInNotch ? "On" : "Off")
                let moonOn = timer.focus && focus.isSetUp
                Button {
                    if moonOn { timer.focus = false } else { focus.turnMoonOn { timer.focus = true } }
                } label: { Image(systemName: moonOn ? "moon.fill" : "moon") }
                    .buttonStyle(TimerControlStyle(on: moonOn))
                    .help(moonOn ? "Do Not Disturb while this runs" : "Turn on Do Not Disturb while this runs")
                    .accessibilityLabel("Do Not Disturb")
                    .accessibilityValue(moonOn ? "On" : "Off")
                NookMenu {
                    NookMenuHeading("When done")
                    ForEach(TimerWhenDone.allCases) { choice in
                        NookMenuRow(choice.title, selected: timer.whenDone == choice) { timer.whenDone = choice }
                    }
                } label: { Image(systemName: timer.whenDone == .nothing ? "bell" : "bell.fill") }
                    .buttonStyle(TimerControlStyle(on: timer.whenDone != .nothing))
                    .help("When done: \(timer.whenDone.title)")
                    .accessibilityLabel("When done, \(timer.whenDone.title)")
                Spacer(minLength: 0)
                Button { timer.togglePause() } label: { Image(systemName: timer.isPaused ? "play.fill" : "pause.fill") }
                    .buttonStyle(TimerControlStyle())
                    .help(timer.isPaused ? "Resume" : "Pause")
                    .accessibilityLabel(timer.isPaused ? "Resume" : "Pause")
                Button { timer.extend(by: 60) } label: { Text("+1") }
                    .buttonStyle(TimerControlStyle())
                    .help("Add a minute")
                Button { timer.cancel() } label: { Image(systemName: "xmark") }
                    .buttonStyle(TimerControlStyle())
                    .help("Remove")
                    .accessibilityLabel("Remove timer")
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onChange(of: editingName) { onEditingChanged($0) }
    }

    /// One row: Theme, Clear and the eyedropper for anything else, then three quick colours.
    private var palette: some View {
        VStack(alignment: .leading, spacing: 8) {
            if choosingCustom {
                ThemeColourEditor(title: "Timer colour", current: { timer.tintChoice.flatMap { $0.count == 6 && Color(themeHex: $0) != nil ? $0 : nil } ?? "FFFFFF" },
                                  apply: { timer.tintChoice = $0 })
            } else {
                HStack(spacing: 6) {
                    swatch("Theme", ThemeStore.shared.notch.accent, symbol: "paintpalette.fill", chosen: timer.tintChoice == "theme") { timer.tintChoice = "theme" }
                    swatch("Clear", ThemeStore.shared.nookForeground, symbol: "circle.slash", chosen: timer.tintChoice == "clear") { timer.tintChoice = "clear" }
                    swatch("Choose any colour", .clear, symbol: "eyedropper", chosen: timer.tintChoice?.count == 6, keepsOpen: true) { choosingCustom = true }
                    Spacer().frame(width: 6)
                    ForEach(0..<3, id: \.self) { index in
                        swatch("Colour \(index + 1)", TimerService.palette[index], chosen: timer.tintChoice == nil && index == timer.tintIndex) {
                            timer.tintChoice = nil
                            timer.tintIndex = index
                        }
                    }
                }
            }
        }
        .padding(10)
        .onDisappear { choosingCustom = false }
    }

    private func swatch(_ title: String, _ colour: Color, symbol: String? = nil, chosen: Bool, keepsOpen: Bool = false,
                        action: @escaping () -> Void) -> AnyView {
        AnyView(Button {
            action()
            if !keepsOpen { choosingColour = false }
        } label: {
            Circle().fill(symbol == nil ? colour : Color.primary.opacity(0.1))
                .overlay {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(colour == .clear ? Color.primary : colour)
                    } else if chosen {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.black.opacity(0.8))
                    }
                }
                .overlay { if chosen, symbol != nil { Circle().strokeBorder(Color.primary.opacity(0.8), lineWidth: 1.5) } }
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title))
    }
}

/// The small square control on a timer card.
private struct TimerControlStyle: ButtonStyle {
    var on = false
    @ObservedObject private var theme = ThemeStore.shared

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(on ? Color.black.opacity(0.82) : Color.primary)
            .frame(width: 22, height: 22)
            .background(on ? AnyShapeStyle(theme.notch.accent) : AnyShapeStyle(Color.primary.opacity(0.09)),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Clipboard

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
                NookMenuChip(options: Array(PasteQueue.Order.allCases),
                             selection: Binding(get: { monitor.queue.order }, set: { monitor.setQueueOrder($0) })) { $0.title }
                    .accessibilityLabel("Order")
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
    /// Kept between openings and shared with the other Keep awake control.
    @AppStorage(WidgetOptions.Keys.keepAwakeMinutes) private var minutes = 60
    @AppStorage(WidgetOptions.Keys.keepAwakeDisplayToo) private var displayToo = false

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
        let until = lid.helper == .ready
            ? "It stays on until you turn it off or quit MacSpaces, and turns itself off on battery at \(AgentPowerAlert.threshold)%."
            : "Without the helper it stays on after MacSpaces quits, and turning it off on battery at \(AgentPowerAlert.threshold)% needs your password."
        return "Keeps this Mac and its agents working with the lid closed, like lid-closed keep-awake apps. \(how) \(until)"
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
