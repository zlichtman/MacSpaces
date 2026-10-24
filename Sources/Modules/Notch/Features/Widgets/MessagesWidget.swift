import SwiftUI

struct MessagesWidget: View {
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var service = AppServices.shared.messages
    @FocusState private var composing: Bool
    @State private var showDetails = false
    private var recipientMenuWidth: CGFloat {
        let title = service.reply.recipient?.title ?? "Reply to…"
        let textWidth = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
        return min(180, ceil(textWidth) + 22)
    }
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right").accessibilityLabel("Messages")
            if service.sessionHidden {
                Text("Messages hidden while locked").foregroundStyle(.secondary)
                Spacer()
            } else {
                if let incoming = service.incoming.first, !composing, service.reply.draft.isEmpty {
                    Button {
                        if service.selectIncoming(incoming) { composing = true } else { showDetails = true }
                    } label: {
                        HStack(spacing: 6) {
                            Text(service.incomingTitle(incoming)).fontWeight(.semibold).lineLimit(1)
                            Text(incoming.text).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).help("Reply to incoming message")
                    if service.incoming.count > 1 { Text("+\(service.incoming.count - 1)").foregroundStyle(.secondary) }
                    Button { service.dismissIncoming(incoming) } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss message")
                } else if service.conversations.isEmpty {
                    Button("Connect Messages") { service.connect() }.disabled(service.loading)
                    Text(service.status).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                } else {
                    Menu {
                        ForEach(service.conversations) { conversation in
                            Button(conversation.title + " · " + conversation.participantLabels.joined(separator: ", ")) {
                                if service.reply.select(conversation) { composing = true }
                            }
                        }
                    } label: {
                        Text(service.reply.recipient?.title ?? "Reply to…").lineLimit(1)
                    }.menuStyle(.borderlessButton)
                    .frame(width: recipientMenuWidth, alignment: .leading)
                    .disabled(service.reply.phase != .editing || !service.reply.draft.isEmpty)
                    if service.reply.phase == .editing {
                        TextField("Quick reply…", text: $service.reply.draft).textFieldStyle(.plain)
                            .focused($composing).disabled(service.reply.recipient == nil)
                            .onSubmit { service.send() }
                        Button { service.send() } label: { Image(systemName: "arrow.up.circle.fill") }
                            .disabled(service.reply.recipient == nil || service.reply.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityLabel("Send reply")
                    } else {
                        Text(service.status).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        if service.reply.phase != .sending {
                            Button(service.reply.phase == .uncertain ? "Discard draft" : "New reply") { service.reply.newDraft() }
                        }
                    }
                }
                if service.incomingEnabled && service.incomingNeedsAttention {
                    Button { showDetails = true } label: {
                        Label(service.incomingNeedsAccess ? "Set up incoming" : "Incoming unavailable", systemImage: "exclamationmark.circle")
                    }.help(service.incomingStatus)
                }
                Button { showDetails.toggle() } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("Messages status and access")
                    .popover(isPresented: $showDetails) { receptionDetails }
            }
        }.privacySensitive()
            .onChange(of: composing) { onEditingChanged($0) }
            .onDisappear { onEditingChanged(false) }
    }
    var receptionDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Messages", systemImage: "bubble.left.and.bubble.right")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { showDetails = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Close Messages options")
            }
            Toggle("Receive messages", isOn: Binding(get: { service.incomingEnabled }, set: service.setIncomingEnabled))
                .toggleStyle(.switch).controlSize(.small)
            if service.incomingEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Label(service.incomingNeedsAccess ? "Allow incoming messages" : service.incomingNeedsAttention ? "Reception needs attention" : "Incoming messages",
                          systemImage: service.incomingNeedsAttention ? "exclamationmark.circle" : "bubble.left")
                        .fontWeight(.medium)
                    Text(service.incomingNeedsAccess
                         ? "Enable MacSpaces in Full Disk Access, then quit and reopen the app. Sending uses a separate permission."
                         : service.incomingStatus)
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if service.incomingNeedsAccess {
                        HStack {
                            Button("Open Settings") { service.openIncomingAccessSettings() }
                                .buttonStyle(.borderedProminent)
                            Button("Check Access") { service.retryIncoming() }
                        }
                    } else if service.incomingNeedsAttention {
                        Button("Try Again") { service.retryIncoming() }
                    }
                }.padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
            if service.reply.phase == .uncertain || service.reply.phase == .sending {
                Text(service.status).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Open Messages") { service.openMessages() }
                Spacer()
                Button("Refresh Contacts") { service.connect() }.disabled(service.loading)
            }.buttonStyle(.borderless)
            Text("Only new arrivals while enabled. No history imported.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.font(.system(size: 12)).controlSize(.small).padding(16).frame(width: 310)
    }
}
