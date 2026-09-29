import SwiftUI
import AppKit

/// Year progress and a month grid beside the selected day's agenda.
/// The grid and year bar follow Aaron Lichtman's DayDrop.
struct CalendarAppView: View {
    @ObservedObject var service: CalendarService
    @ObservedObject private var theme = ThemeStore.shared
    @State private var month = Date()
    @State private var selected = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if service.eventsAccessDenied {
                VStack(spacing: 10) {
                    YearProgressHeader(progress: YearProgress(date: context.date)).frame(width: 320)
                    Spacer()
                    Label("Allow Calendar access to see your events here.", systemImage: "calendar.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                    Button("Open Permissions") { SettingsWindowController.shared.show(.permissions) }
                        .buttonStyle(WidgetChipStyle(height: 26))
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
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            service.startEventsIfNeeded()
            service.loadMonth(containing: month)
        }
        .onChange(of: month) { service.loadMonth(containing: $0) }
    }

    private func agenda(now: Date) -> some View {
        let events = service.events(on: selected)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayTitle).font(.system(size: 15, weight: .bold))
                Text(selected, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(WidgetChipStyle(height: 22))
                    .help("Open Calendar")
            }
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
    @State private var selected: UUID?
    @State private var draft = ""
    @State private var revision: UUID?
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Notes").font(.headline)
                    Spacer()
                    Button { if save(), let id = service.create() { load(id) } } label: { Image(systemName: "plus") }
                        .help("New note").accessibilityLabel("New note")
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(service.active) { note in
                            Button { if save() { load(note.id) } } label: {
                                Text(note.title.isEmpty ? "Untitled note" : note.title).lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                    .background(selected == note.id ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.frame(width: 150)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if selected != nil {
                    TextEditor(text: $draft).font(.system(size: 13)).scrollContentBackground(.hidden)
                        .accessibilityLabel("Note text")
                    HStack {
                        Text(service.active.first(where: { $0.id == selected })?.current.text == draft ? "Saved on this Mac" : "Unsaved changes").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Save") { _ = save() }
                    }
                } else {
                    Spacer()
                    Text("Create a note to start writing.").foregroundStyle(.secondary)
                    Spacer()
                }
                if let error = service.error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }.padding(12)
            .onAppear { if selected == nil, let first = service.active.first { load(first.id) } }
            .onDisappear { _ = save() }
    }
    private func load(_ id: UUID) {
        guard let note = service.active.first(where: { $0.id == id }) else { return }
        selected = id; draft = note.current.text; revision = note.current.id
    }
    private func save() -> Bool {
        guard let selected else { return true }
        guard service.save(selected, text: draft, base: revision) else { return false }
        revision = service.active.first(where: { $0.id == selected })?.current.id
        return true
    }
}

struct CodingUsageView: View {
    @ObservedObject var service: CodingUsageService
    @State private var provider = "All"
    private var rows: [CodingUsageRow] { service.snapshot.rows.filter { provider == "All" || $0.provider == provider } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Coding").font(.headline)
                Text("Last 30 days").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("Provider", selection: $provider) {
                    ForEach(["All", "Codex", "Claude"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 205)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(rows.reduce(Int64(0)) { $0 + $1.total }.formatted()).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("recorded tokens").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if service.isLoading { ProgressView().controlSize(.small) }
            }
            if let error = service.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            if rows.isEmpty {
                Text(service.isLoading ? "Reading local usage records…" : "No recorded usage for this provider in the available local logs.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(rows) { row in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.model).font(.system(size: 12, weight: .medium))
                                    Text("\(row.provider) · \(row.input.formatted()) input · \(row.output.formatted()) output · \(row.cached.formatted()) cached input")
                                        .font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(row.total.formatted()).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            }.padding(9).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            HStack {
                Text(service.snapshot.limited ? "Partial coverage · scan limit or unreadable logs" : "Local CLI records · cached tokens included in input")
                Spacer()
                if let date = service.updatedAt { Text(date, style: .time) }
            }.font(.system(size: 9)).foregroundStyle(.secondary)
        }.padding(12)
    }
}

/// A weather page that uses the whole panel: now, the next hours and the
/// next days, in the Nook theme.
struct WeatherAppView: View {
    @ObservedObject var service: WeatherService
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
        .onAppear { service.startIfNeeded() }
    }

    private func current(_ weather: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(service.locationName ?? "Local weather", systemImage: "location.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            HStack(spacing: 12) {
                Image(systemName: weather.symbolName)
                    .font(.system(size: 42))
                    .symbolRenderingMode(.multicolor)
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
