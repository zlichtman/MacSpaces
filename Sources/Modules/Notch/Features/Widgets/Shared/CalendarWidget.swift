import SwiftUI

struct CalendarWidget: View {
    @ObservedObject var service: CalendarService
    @State private var showingList = false

    var body: some View {
        Button {
            showingList.toggle()
        } label: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingList, arrowEdge: .top) {
            eventList
        }
        .onAppear { service.startEventsIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if service.eventsAccessDenied {
            deniedView
        } else if let event = service.nextEvent {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(calendarColor(for: event))
                    .frame(width: 4)
                    .padding(.vertical, 14)

                VStack(alignment: .leading, spacing: 3) {
                    Text("NEXT UP")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(event.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(event.startDate, format: .dateTime.hour().minute())
                            .foregroundStyle(.secondary)
                        Text(event.startDate, style: .relative)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                calendarColor(for: event).opacity(0.14),
                                in: Capsule()
                            )
                    }
                    .font(.system(size: 10))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
        } else {
            WidgetEmptyState(
                systemImage: "calendar",
                caption: "No more events today",
                captionSize: 10
            )
        }
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
