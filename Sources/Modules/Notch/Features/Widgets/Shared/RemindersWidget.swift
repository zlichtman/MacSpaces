import SwiftUI

struct RemindersWidget: View {
    @ObservedObject var service: CalendarService
    var compact = false
    @State private var showingList = false
    @State private var completing: Set<String> = []

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .popover(isPresented: $showingList, arrowEdge: .top) {
                TodoListPopover(service: service)
            }
            .onAppear { service.startRemindersIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if service.remindersAccessDenied {
            WidgetEmptyState(systemImage: "checklist.unchecked", caption: "Allow Reminders in System Settings", captionSize: 9)
                .padding(6)
        } else if service.reminders.isEmpty {
            Button { showingList = true } label: {
                VStack(spacing: 5) {
                    Image(systemName: "checkmark.circle").font(.system(size: 16)).foregroundStyle(.green)
                    Text("All done · Add a reminder").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            let limit = compact ? 1 : 3
            VStack(alignment: .leading, spacing: 5) {
                ForEach(service.reminders.prefix(limit)) { item in
                    row(item)
                }
                Spacer(minLength: 0)
                HStack {
                    Text(service.reminders.count > limit ? "+\(service.reminders.count - limit) more" : "\(service.reminders.count) open")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    Spacer()
                    Button { showingList = true } label: { Image(systemName: "plus") }
                        .buttonStyle(WidgetChipStyle(height: 20)).help("Add or view reminders")
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, compact ? 6 : 8)
        }
    }

    /// Checking the circle completes the reminder right from the tile.
    private func row(_ item: TodoItem) -> some View {
        let done = completing.contains(item.id)
        return HStack(spacing: 7) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { _ = completing.insert(item.id) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    service.complete(item)
                    completing.remove(item.id)
                }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(done ? Color.green : .secondary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(item.title)")
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(.system(size: 11)).lineLimit(1)
                    .strikethrough(done).foregroundStyle(done ? .secondary : .primary)
                if let due = item.dueDate, !compact {
                    Text(due, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(size: 8)).foregroundStyle(due < Date() ? Color.red : .secondary)
                }
            }
        }
    }
}

private struct TodoListPopover: View {
    @ObservedObject var service: CalendarService
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Todos")
                .font(.headline)

            if service.reminders.isEmpty {
                Text("Nothing to do")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(service.reminders) { item in
                            HStack(spacing: 8) {
                                Button {
                                    service.complete(item)
                                } label: {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                    if let due = item.dueDate {
                                        Text(due, format: .dateTime.month(.abbreviated).day().hour().minute())
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            HStack {
                TextField("New reminder…", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addReminder)
                Button("Add", action: addReminder)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func addReminder() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        service.addReminder(title: title)
        newTitle = ""
    }
}
