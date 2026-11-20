import SwiftUI
import AppKit

/// Year progress and a month grid beside the selected day's agenda.
/// The grid and year bar follow Aaron Lichtman's DayDrop.
struct CalendarAppView: View {
    @ObservedObject var service: CalendarService
    @ObservedObject private var theme = ThemeStore.shared
    @State private var month = Date()
    @State private var selected = Date()
    /// The Life view (your life in weeks) instead of the month and agenda.
    @AppStorage("calendar.showsLife") private var showsLife = false

    var body: some View {
        Group {
            if showsLife { LifeView() } else { calendar }
        }
        .overlay(alignment: .topTrailing) { viewSwitch.offset(y: -4) }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .nookAfterOpening {
            service.startEventsIfNeeded()
            service.loadMonth(containing: month, keeping: selected)
        }
        // Browsing keeps the selected day loaded, so its agenda stays filled.
        .onChange(of: month) { service.loadMonth(containing: $0, keeping: selected) }
    }

    /// Calendar or Life, in the page's top corner.
    private var viewSwitch: some View {
        HStack(spacing: 2) {
            ForEach([false, true], id: \.self) { life in
                Button(life ? "Life" : "Calendar") { withAnimation(Design.spring()) { showsLife = life } }
                    .buttonStyle(WidgetChipStyle(prominent: showsLife == life, height: 20))
            }
        }
        .font(.system(size: 10, weight: .semibold))
    }

    private var calendar: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if service.eventsAccessDenied || service.eventsNeedAccess {
                VStack(spacing: 10) {
                    YearProgressHeader(progress: YearProgress(date: context.date)).frame(width: 320)
                    Spacer()
                    Label("Allow Calendar access to see your events here.", systemImage: "calendar.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                    if service.eventsNeedAccess {
                        Button("Allow Calendar") { service.allowEvents() }
                            .buttonStyle(WidgetChipStyle(prominent: true, height: 26))
                    } else {
                        Button("Open Permissions") { SettingsWindowController.shared.show(.permissions) }
                            .buttonStyle(WidgetChipStyle(height: 26))
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        YearProgressHeader(progress: YearProgress(date: context.date))
                        MonthGrid(month: $month, selected: $selected, events: service.monthEvents)
                    }
                    .frame(width: 290)
                    agenda(now: context.date)
                }
            }
        }
    }

    private func agenda(now: Date) -> some View {
        let events = service.events(on: selected)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(dayTitle).font(.system(size: 15, weight: .bold))
                    .lineLimit(1).fixedSize()
                Text(selected, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    .lineLimit(1).fixedSize()
                Button {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(WidgetChipStyle(height: 22))
                    .help("Open Calendar")
                Spacer(minLength: 0)
                // The Calendar/Life switch sits at the end of this row (the page's top corner);
                // a hidden copy keeps exactly its width free, so the date never wraps.
                viewSwitch.hidden().accessibilityHidden(true)
            }
            .offset(y: -4)
            if events.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "sun.max").font(.system(size: 18)).foregroundStyle(.secondary)
                    Text("Nothing scheduled").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(events) { event in row(event, now: now) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var dayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selected) { return "Today" }
        if calendar.isDateInTomorrow(selected) { return "Tomorrow" }
        if calendar.isDateInYesterday(selected) { return "Yesterday" }
        return selected.formatted(.dateTime.weekday(.wide))
    }

    private func row(_ event: CalendarEventItem, now: Date) -> some View {
        let color = event.color.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? theme.notch.accent
        let past = event.endDate < now
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                if event.isAllDay {
                    Text("All day")
                } else {
                    Text(event.startDate, format: .dateTime.hour().minute())
                    Text(event.endDate, format: .dateTime.hour().minute()).foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 10, weight: .medium)).monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 58, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if let location = event.location, !location.isEmpty, event.meetingURL == nil {
                    Text(location).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                } else if event.isInProgress(at: now), !event.isAllDay {
                    ProgressView(value: event.progress(at: now)).tint(color).controlSize(.mini)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            if let meeting = event.meetingURL, !past, event.startDate.timeIntervalSince(now) < 15 * 60 {
                Button("Join") { NSWorkspace.shared.open(meeting) }
                    .buttonStyle(WidgetChipStyle(prominent: true, height: 22))
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(color.opacity(event.isInProgress(at: now) ? 0.14 : 0.06),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(past ? 0.5 : 1)
    }
}

struct NotesAppView: View {
    @ObservedObject var service: NotesService
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var draft: NoteDraft?
    @State private var autosave: Task<Void, Never>?
    @State private var showDeleted = false
    @State private var query = ""
    /// The notes that match `query`, worked out off the main thread; nil lists them all.
    @State private var matches: Set<UUID>?
    @State private var search: Task<Void, Never>?
    @State private var menuOpen = false
    @FocusState private var editorFocused: Bool
    @FocusState private var searchFocused: Bool
    #if DEBUG
    /// What Feature QA's `notes-page` scope starts the page on.
    static var qaStart = (query: "", showsDeleted: false)
    #endif

    var body: some View {
        let listed = listedNotes
        let hasDeleted = !service.deleted.isEmpty
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(showDeleted ? "Recently Deleted" : "Notes").font(.headline).lineLimit(1)
                    Spacer()
                    if !showDeleted {
                        Button { newNote() } label: { Image(systemName: "plus") }
                            .help("New note").accessibilityLabel("New note")
                    }
                }
                // The same height with or without New, so the list doesn't jump between views.
                .frame(height: 24)
                if !listed.isEmpty || !query.isEmpty { searchField }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(listed) { note in
                            Button { if commit() { load(note.id) } } label: {
                                Text(note.title.isEmpty ? "Untitled note" : note.title).lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                    .background(draft?.id == note.id ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                        if listed.isEmpty, !query.isEmpty {
                            Text("No matching notes").font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(8)
                        }
                    }
                }
                if showDeleted || hasDeleted {
                    Button(showDeleted ? "Back to Notes" : "Recently Deleted") { toggleDeleted() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(width: 150)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let draft {
                    TextEditor(text: draftText).font(.system(size: 13)).scrollContentBackground(.hidden)
                        .accessibilityLabel("Note text")
                        .focused($editorFocused)
                        .disabled(showDeleted)
                        .id(draft.id)
                    HStack {
                        Text(showDeleted ? "Deleted" : draft.isDirty ? "Unsaved changes" : "Saved on this Mac")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        if showDeleted {
                            Button("Restore") { restore(draft.id) }
                        }
                        if let note = service.notes.first(where: { $0.id == draft.id }), !showDeleted || !note.conflicts.isEmpty {
                            noteMenu(note)
                        }
                    }
                } else {
                    Spacer()
                    Text(placeholder).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: .infinity)
                    Spacer()
                }
                if let error = service.error { Text(error).font(.caption).foregroundStyle(.red).lineLimit(1).help(error) }
            }
        }.padding(12)
            .onAppear {
                #if DEBUG
                query = Self.qaStart.query
                showDeleted = Self.qaStart.showsDeleted
                #endif
                if draft == nil { load(listedNotes.first?.id) }
            }
            .onDisappear {
                _ = commit()
                search?.cancel()
                onEditingChanged(false)
            }
            // Quitting (or relaunching for an update) never runs onDisappear.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in _ = commit() }
            // The menu can reach below the Nook, so the pointer leaves it on the way to an item.
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in menuOpen = true }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in menuOpen = false }
            .onChange(of: editorFocused || searchFocused || menuOpen) { onEditingChanged($0) }
            .onChange(of: draft?.text) { _ in scheduleAutosave() }
            .onChange(of: query) { _ in runSearch() }
            .onChange(of: service.notes) { _ in notesChanged() }
    }

    private var listedNotes: [StoredNote] {
        let notes = showDeleted ? service.deleted : service.active
        guard let matches else { return notes }
        return notes.filter { matches.contains($0.id) }
    }

    private var placeholder: String {
        if showDeleted { return "Choose a note to restore." }
        return service.active.isEmpty ? "Create a note to start writing." : "Choose a note."
    }

    private var draftText: Binding<String> {
        Binding(get: { draft?.text ?? "" }, set: { draft?.text = $0 })
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain).font(.system(size: 12))
                .focused($searchFocused)
            if !query.isEmpty {
                Button { clearSearch() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Clear search").accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func noteMenu(_ note: StoredNote) -> some View {
        NookMenu {
            if !showDeleted {
                NookMenuRow("Delete", destructive: true) { deleteNote() }
            }
            NoteVersionRows(note: note, service: service, prepare: commit) {
                let deleted = service.notes.first { $0.id == note.id }?.current.deleted ?? false
                if deleted != showDeleted { clearSearch(); showDeleted = deleted }
                load(note.id)
            }
        } label: { Image(systemName: "ellipsis") }
            .buttonStyle(WidgetChipStyle(height: 24))
            .accessibilityLabel("Note options")
    }

    private func load(_ id: UUID?) {
        autosave?.cancel()
        editorFocused = false
        draft = id.flatMap(service.draft(of:))
    }

    /// Saves the draft now; a failed save leaves it as typed, with the error on the page.
    private func commit() -> Bool {
        autosave?.cancel()
        guard var saving = draft else { return true }
        guard service.commit(&saving) else { return false }
        draft = saving
        return true
    }

    /// Saves about a second after typing stops.
    private func scheduleAutosave() {
        autosave?.cancel()
        guard draft?.isDirty == true else { return }
        autosave = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            _ = commit()
        }
    }

    private func newNote() {
        guard commit(), let id = service.blankNote() else { return }
        clearSearch()
        load(id)
        DispatchQueue.main.async { editorFocused = true }
    }

    /// Moves to the note after this one (or before, at the end of the list).
    private func deleteNote() {
        autosave?.cancel()
        guard let draft else { return }
        let listed = listedNotes
        let position = listed.firstIndex { $0.id == draft.id }
        let next = position.flatMap { index in
            index + 1 < listed.count ? listed[index + 1].id : index > 0 ? listed[index - 1].id : nil
        }
        guard service.trash(draft.id, text: draft.text, base: draft.base) else { return }
        // With a stale base the note stays, and the deletion waits under Other versions.
        load(service.notes.first { $0.id == draft.id }?.current.deleted == true ? next : draft.id)
    }

    private func restore(_ id: UUID) {
        guard service.restore(id) else { return }
        clearSearch()
        showDeleted = false
        load(id)
    }

    private func toggleDeleted() {
        guard commit() else { return }
        clearSearch()
        showDeleted.toggle()
        load(listedNotes.first?.id)
    }

    private func clearSearch() {
        query = ""
        search?.cancel()
        matches = nil
    }

    /// Reads no note text on the main thread: at the limits that's 2,000 notes and 16 MB. A later
    /// keystroke cancels this one, so a superseded result never lands.
    private func runSearch() {
        search?.cancel()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { matches = nil; return }
        let notes = showDeleted ? service.deleted : service.active
        search = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
            let work = Task.detached(priority: .userInitiated) { [notes, needle] in StoredNote.ids(matching: needle, in: notes) }
            let found = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled else { return }
            matches = found
        }
    }

    /// The notes changed, here or elsewhere (the widget, Wisp, another screen's Nook). An edit in
    /// progress stays as typed: its next save finds the stale base and goes to Other versions.
    private func notesChanged() {
        runSearch()
        guard let draft, !draft.isDirty else { return }
        guard let note = service.notes.first(where: { $0.id == draft.id }), note.current.deleted == showDeleted else {
            load(listedNotes.first?.id)
            return
        }
        if note.current.id != draft.base { self.draft = service.draft(of: draft.id) }
    }
}

/// A weather page that uses the whole panel: now, the next hours and the
/// next days, in the Nook theme.
struct WeatherAppView: View {
    @ObservedObject var service: WeatherService
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var options = WidgetOptions.shared
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        Group {
            if let weather = service.snapshot {
                VStack(spacing: 14) {
                    HStack(alignment: .top, spacing: 16) {
                        current(weather)
                        Spacer(minLength: 8)
                        details(weather)
                    }
                    if !weather.hourly.isEmpty { hourly(weather) }
                    if !weather.upcoming.isEmpty { daily(weather) }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                VStack(spacing: 10) {
                    if let error = service.errorText {
                        Label(error, systemImage: "cloud.slash").foregroundStyle(.secondary)
                        Button("Try Again") { service.stop(); service.startIfNeeded() }
                            .buttonStyle(WidgetChipStyle(height: 26))
                    } else {
                        ProgressView().controlSize(.small)
                        Text("Loading local weather…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Location is asked for only from Settings → Permissions or Try Again; until then, IP location.
        .nookAfterOpening { service.startIfNeeded(allowLocationPrompt: false) }
    }

    private func current(_ weather: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            WeatherPlaceMenu(service: service, onEditingChanged: onEditingChanged)
            HStack(spacing: 12) {
                // A fixed box: a wide symbol or a tall one never moves the temperature.
                Image(systemName: weather.symbolName)
                    .font(.system(size: 42))
                    .symbolRenderingMode(.multicolor)
                    .frame(width: 54, height: 54)
                Text("\(Int(weather.temperature.rounded()))°")
                    .font(.system(size: 58, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
            Text("\(weather.conditionName) · H \(Int(weather.high.rounded()))°  L \(Int(weather.low.rounded()))°")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if let sunEvent = nextSunEvent(weather) {
                Label(sunEvent.text, systemImage: sunEvent.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            } else {
                // Keeps the rows below where they were, wherever the sun has no next event.
                Text(" ").font(.system(size: 11, weight: .medium)).padding(.top, 2).accessibilityHidden(true)
            }
        }
    }

    private func details(_ weather: WeatherSnapshot) -> some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                detail("Feels like", weather.feelsLike.map { "\(Int($0.rounded()))°" }, "thermometer.medium")
                detail("Wind", weather.windSpeed.map { "\(Int($0.rounded())) \(options.temperatureUnit == .fahrenheit ? "mph" : "km/h")" }, "wind")
            }
            GridRow {
                detail("Humidity", weather.humidity.map { "\($0)%" }, "humidity")
                detail("Rain", weather.precipitationChance.map { "\($0)%" }, "umbrella")
            }
        }
        .frame(width: 236)
    }

    private func detail(_ title: String, _ value: String?, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func hourly(_ weather: WeatherSnapshot) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(weather.hourly.prefix(10).enumerated()), id: \.element.id) { index, hour in
                VStack(spacing: 6) {
                    Text(index == 0 ? "Now" : hour.date.formatted(.dateTime.hour()))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(index == 0 ? AnyShapeStyle(theme.notch.accent) : AnyShapeStyle(.secondary))
                    Image(systemName: hour.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 15))
                        .frame(height: 18)
                    Text("\(Int(hour.temperature.rounded()))°")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func daily(_ weather: WeatherSnapshot) -> some View {
        HStack(spacing: 8) {
            ForEach(weather.upcoming.prefix(4)) { day in
                HStack(spacing: 6) {
                    Text(day.date, format: .dateTime.weekday(.abbreviated))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1).fixedSize()
                    Image(systemName: day.symbolName).symbolRenderingMode(.multicolor).font(.system(size: 13))
                    Spacer(minLength: 2)
                    (Text("\(Int(day.high.rounded()))°").font(.system(size: 12, weight: .semibold))
                        + Text("  \(Int(day.low.rounded()))°").font(.system(size: 12)).foregroundColor(.secondary))
                        .lineLimit(1).fixedSize()
                }
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
    }

    /// The next of today's sunrise or sunset, if it hasn't passed.
    private func nextSunEvent(_ weather: WeatherSnapshot) -> (text: String, symbol: String)? {
        let now = Date()
        if let sunrise = weather.sunrise, sunrise > now {
            return ("Sunrise \(sunrise.formatted(date: .omitted, time: .shortened))", "sunrise.fill")
        }
        if let sunset = weather.sunset, sunset > now {
            return ("Sunset \(sunset.formatted(date: .omitted, time: .shortened))", "sunset.fill")
        }
        return nil
    }
}
