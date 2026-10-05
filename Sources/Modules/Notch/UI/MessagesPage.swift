import SwiftUI

/// The Messages page: an inbox of recent conversations, the open thread as
/// bubbles, and a reply bar that sends to that exact conversation through
/// Messages. It updates as messages arrive and reads nothing while closed.
struct MessagesPage: View {
    @ObservedObject var service: MessagesReplyService
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var theme = ThemeStore.shared
    @State private var draft = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if service.inboxNeedsAccess {
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill").font(.system(size: 22)).foregroundStyle(.secondary)
                    Text("Messages needs Full Disk Access to show your conversations here.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Open Privacy Settings") { service.openIncomingAccessSettings() }
                        .buttonStyle(WidgetChipStyle(prominent: true, height: 28))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 12) {
                    inboxList.frame(width: 210)
                    threadView.frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .onAppear { service.startInbox() }
        .onDisappear { service.stopInbox(); onEditingChanged(false) }
        .onChange(of: focused) { _, value in onEditingChanged(value) }
    }

    private var inboxList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(service.inbox) { chat in
                    let selected = service.selectedChat == chat.id
                    Button { service.selectedChat = chat.id } label: {
                        HStack(spacing: 9) {
                            Avatar(name: service.title(for: chat), group: !chat.groupName.isEmpty, photo: service.contactPhotos[chat.handle])
                            VStack(alignment: .leading, spacing: 1) {
                                HStack {
                                    Text(service.title(for: chat)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(chat.lastDate, format: Self.shortTime(chat.lastDate))
                                        .font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                                Text((chat.lastFromMe ? "You: " : "") + chat.lastText)
                                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(selected ? theme.notch.accent.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if service.inbox.isEmpty {
                    Text("Your conversations appear here.").font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 20)
                }
            }
        }
    }

    private var threadView: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(service.thread) { line in
                            HStack {
                                if line.fromMe { Spacer(minLength: 40) }
                                Text(line.text)
                                    .font(.system(size: 12))
                                    .foregroundStyle(line.fromMe ? Color.white : theme.nookForeground)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(line.fromMe ? Color(red: 0.2, green: 0.5, blue: 1) : Color.primary.opacity(0.1),
                                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .textSelection(.enabled)
                                if !line.fromMe { Spacer(minLength: 40) }
                            }
                            .id(line.id)
                        }
                    }
                }
                .onChange(of: service.thread.last?.id) { _, last in
                    if let last { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) } }
                }
                .onAppear { if let last = service.thread.last?.id { proxy.scrollTo(last, anchor: .bottom) } }
            }
            HStack(spacing: 8) {
                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 12)).lineLimit(1...3)
                    .focused($focused)
                    .onSubmit(send)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                Button(action: send) {
                    Image(systemName: sending ? "ellipsis" : "arrow.up").font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(draft.isEmpty ? Color.primary.opacity(0.12) : Color(red: 0.2, green: 0.5, blue: 1), in: Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || sending || service.selectedChat == nil)
                .accessibilityLabel("Send")
            }
        }
    }

    private func send() {
        guard let chat = service.selectedChat, !sending else { return }
        sending = true
        service.quickReply(draft, toChat: chat) { accepted in
            sending = false
            if accepted { draft = "" }
        }
    }

    private static func shortTime(_ date: Date) -> Date.FormatStyle {
        Calendar.current.isDateInToday(date) ? .dateTime.hour().minute() : .dateTime.month(.abbreviated).day()
    }
}

/// Initials in a circle, or a people symbol for a group.
private struct Avatar: View {
    let name: String
    let group: Bool
    var photo: NSImage?

    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()
        if let photo, !group {
            Image(nsImage: photo).resizable().scaledToFill().frame(width: 30, height: 30).clipShape(Circle())
        } else {
            placeholder(initials)
        }
    }

    private func placeholder(_ initials: String) -> some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.38)], startPoint: .top, endPoint: .bottom))
            if group || initials.isEmpty || initials.first?.isLetter == false {
                Image(systemName: group ? "person.2.fill" : "person.fill").font(.system(size: 13)).foregroundStyle(.white)
            } else {
                Text(initials.uppercased()).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: 30, height: 30)
    }
}
