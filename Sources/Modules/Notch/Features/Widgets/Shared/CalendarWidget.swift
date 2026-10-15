import SwiftUI
import AppKit

struct CalendarWidget: View {
    @ObservedObject var service: CalendarService
    var compact = false
    /// Large adds a mini month beside the events.
    var large = false
    @State private var showingList = false
    @State private var month = Date()
    @State private var selected = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 6) {
                HStack(alignment: .top, spacing: 4) {
                    if large && !service.eventsAccessDenied {
                        MonthGrid(month: $month, selected: $selected, events: service.monthEvents,
                                  cellHeight: 19, showsNavigation: false)
                            .frame(width: 150)
                            .padding(.leading, 10)
                            .allowsHitTesting(false)
                    }
                    content(now: context.date)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // How far through the year we are, after Aaron's DayDrop.
                if !compact {
                    YearProgressHeader(progress: YearProgress(date: context.date), compact: true)
                        .padding(.horizontal, 11)
                        .padding(.bottom, 9)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showingList.toggle() }
        .popover(isPresented: $showingList, arrowEdge: .top) {
            eventList
        }
        .onAppear {
            service.startEventsIfNeeded()
            if large { service.loadMonth(containing: Date()) }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if service.eventsAccessDenied {
            deniedView
        } else if let event = service.todayEvents.first(where: { $0.endDate > now }) {
            let later = service.todayEvents.filter { $0.endDate > now && $0.id != event.id }
            VStack(alignment: .leading, spacing: 6) {
                eventCard(event, now: now)
                if !compact {
                    ForEach(later.prefix(2)) { item in
                        HStack(spacing: 6) {
                            Circle().fill(calendarColor(for: item)).frame(width: 6, height: 6)
                            Text(item.title).font(.system(size: 10)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(item.startDate, format: .dateTime.hour().minute())
                                .font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    if later.count > 2 {
                        Text("+\(later.count - 2) more today").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, compact ? 0 : 8)
        } else if let tomorrow = service.tomorrowEvents.first {
            VStack(alignment: .leading, spacing: 3) {
                Text(compact ? "Clear today" : "Nothing else today")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(calendarColor(for: tomorrow)).frame(width: 3, height: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tomorrow.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Text("Tomorrow, \(tomorrow.startDate.formatted(.dateTime.hour().minute()))")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
        } else {
            WidgetEmptyState(systemImage: "calendar", caption: "No more events today", captionSize: 10)
        }
    }

    /// The current or next event, with its time, a live progress bar while
    /// it runs, and a Join button when it carries a video-call link.
    private func eventCard(_ event: CalendarEventItem, now: Date) -> some View {
        let color = calendarColor(for: event)
        let inProgress = event.isInProgress(at: now)
        return HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.system(size: compact ? 11 : 12, weight: .semibold)).lineLimit(compact ? 1 : 2)
                HStack(spacing: 5) {
                    if inProgress {
                        Text("Now · ends \(event.endDate.formatted(.dateTime.hour().minute()))")
                    } else {
                        Text(event.startDate, format: .dateTime.hour().minute())
                        Text(event.startDate, style: .relative).fontWeight(.semibold).foregroundStyle(color)
                    }
                }
                .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                if inProgress {
                    ProgressView(value: event.progress(at: now)).tint(color).controlSize(.mini)
                }
            }
            Spacer(minLength: 0)
            if let meeting = event.meetingURL,
               inProgress || event.startDate.timeIntervalSince(now) < 15 * 60 {
                Button("Join") { NSWorkspace.shared.open(meeting) }
                    .buttonStyle(WidgetChipStyle(prominent: true, height: 22))
                    .help("Join \(meeting.host ?? "the call")")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(7)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func calendarColor(for event: CalendarEventItem) -> Color {
        guard let color = event.color else { return .accentColor }
        return Color(
            red: color.red,
            green: color.green,
            blue: color.blue,
            opacity: color.alpha
        )
    }

    private var deniedView: some View {
        WidgetEmptyState(
            systemImage: "calendar.badge.exclamationmark",
            caption: "Grant calendar access in System Settings",
            iconSize: nil
        )
        .padding(6)
    }

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.headline)

            if service.todayEvents.isEmpty {
                Text("No events today")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(service.todayEvents) { event in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(calendarColor(for: event))
                            .frame(width: 8, height: 8)
                        Text(event.title)
                            .lineLimit(1)
                        Spacer()
                        Text(event.startDate, format: .dateTime.hour().minute())
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                }
            }
        }
        .padding(14)
        .frame(width: 260)
    }
}
