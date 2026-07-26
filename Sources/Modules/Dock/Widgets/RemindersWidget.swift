import SwiftUI

struct RemindersWidget: View {
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
            TodoListPopover(service: service)
        }
        .onAppear { service.startRemindersIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if service.remindersAccessDenied {
            VStack(spacing: 4) {
                Image(systemName: "checklist.unchecked")
                    .foregroundStyle(.secondary)
                Text("Grant reminders access in System Settings")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(6)
        } else if service.reminders.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)
                Text("All done!")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(service.reminders.prefix(2)) { item in
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(item.title)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                }
                if service.reminders.count > 2 {
                    Text("+\(service.reminders.count - 2) more")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
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
