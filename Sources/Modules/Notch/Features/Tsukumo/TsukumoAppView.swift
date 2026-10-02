import AppKit
import SwiftUI

/// The Tsukumo page: Tsukumo's bots in the notch. A crew row, the Together thread (or one
/// bot), approvals, a composer and the review sheet. Tsukumo does the work; this page only
/// shows it and sends what the person types or clicks. Approvals and accepting changes are
/// explicit clicks only: no default key, and hover never acts.
struct TsukumoAppView: View {
    @ObservedObject var client: TsukumoAgentsClient
    var onEditingChanged: (Bool) -> Void = { _ in }

    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var composing: Bool
    @State private var note = ""

    var body: some View {
        Group {
            if client.availability != .available && client.agents.isEmpty {
                unavailable
            } else if let review = client.review {
                reviewSheet(review)
            } else {
                VStack(spacing: 8) {
                    crewRow
                    if let agent = client.agent(client.focused) { botPage(agent) } else { thread(client.feed, partials: true) }
                    if let message = client.error { Text(message).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(1) }
                    if let approval = client.approvals.first { approvalBar(approval) }
                    if client.pendingSend != nil { pendingBar } else { composer }
                }
            }
        }
        .onAppear { client.refreshAvailability(force: true); client.start() }
        .onDisappear { client.stop(); onEditingChanged(false) }
        .onChange(of: composing) { onEditingChanged($0) }
    }

    // MARK: Crew

    private var crewRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(client.agents) { agent in crewTile(agent) }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 64)
    }

    private func crewTile(_ agent: MacSpacesAgents.Agent) -> some View {
        let tagged = client.tagged.contains(agent.id) || client.focused == agent.id
        return VStack(spacing: 1) {
            ZStack {
                if tagged {
                    Circle().strokeBorder(theme.notch.accent, lineWidth: 2).frame(width: 50, height: 50)
                }
                if let progress = agent.work?.progress, agent.state == "working" {
                    Circle().trim(from: 0, to: progress).stroke(theme.notch.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 50, height: 50)
                }
                AgentCharacterView(character: agent.character, state: agent.state, size: 44,
                                   animated: !reduceMotion, avatar: client.avatar)
                    .scaleEffect(x: 1, y: tagged ? 1.04 : 1, anchor: .bottom)
            }
            .frame(width: 52, height: 50)
            .overlay(alignment: .topTrailing) {
                if agent.state == "needsYou" { badge("exclamationmark", .orange) }
            }
            .overlay(alignment: .bottomTrailing) {
                if agent.work?.ready == true { badge("magnifyingglass", .blue) }
                else if agent.state == "done" { badge("checkmark", .green) }
            }
            .overlay(alignment: .topLeading) {
                if let tests = agent.work?.tests {
                    badge("flask.fill", tests == "passed" ? .green : tests == "failed" ? .red : .orange)
                }
            }
            Text(agent.name).font(.system(size: 10, weight: tagged ? .semibold : .regular))
                .lineLimit(1).frame(maxWidth: 58)
                .foregroundStyle(tagged ? theme.notch.accent : theme.nookForeground.opacity(0.75))
        }
        .contentShape(Rectangle())
        // Tap tags or untags for Together; a double tap opens the bot on its own.
        .onTapGesture(count: 2) { client.focused = agent.id }
        .onTapGesture {
            if client.focused != nil { client.focused = agent.id } else { client.toggleTag(agent.id) }
        }
        .help("\(agent.name): \(agent.job) (\(agent.engineName))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(agent.name), \(stateDescription(agent.state))")
        .accessibilityAddTraits(tagged ? .isSelected : [])
        .accessibilityAction { client.toggleTag(agent.id) }
        .accessibilityAction(named: "Open") { client.focused = agent.id }
    }

    private func badge(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 7, weight: .heavy)).foregroundStyle(.white)
            .frame(width: 14, height: 14).background(color, in: Circle())
            .overlay(Circle().strokeBorder(theme.notch.surface, lineWidth: 1.5))
    }

    // MARK: Thread

    private func thread(_ items: [MacSpacesAgents.FeedItem], partials: Bool, only agent: UUID? = nil) -> some View {
        let streaming = client.agents.filter { $0.partial != nil && (agent == nil || $0.id == agent) && partials }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    if items.isEmpty && streaming.isEmpty {
                        Text(agent == nil ? "Tag bots above, then say something to them together." : "No messages yet.")
                            .font(.system(size: 12)).foregroundStyle(theme.nookForeground.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .center).padding(.top, 30)
                    }
                    ForEach(items) { item in feedRow(item).id(item.id) }
                    ForEach(streaming) { bot in
                        line(for: bot, text: (bot.partial ?? "") + " …", style: .plain).id(bot.id)
                    }
                }
                .padding(.vertical, 2)
            }
            // Older lines fade out under the crew row instead of being cut off.
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08), .init(color: .black, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .onAppear { scrollToEnd(proxy, items, streaming) }
            .onChange(of: items.count) { _ in scrollToEnd(proxy, items, streaming) }
        }
        .frame(maxHeight: .infinity)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, _ items: [MacSpacesAgents.FeedItem], _ streaming: [MacSpacesAgents.Agent]) {
        if let last = streaming.last { proxy.scrollTo(last.id, anchor: .bottom) }
        else if let last = items.last { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    private enum LineStyle { case plain, chirp, problem }

    @ViewBuilder private func feedRow(_ item: MacSpacesAgents.FeedItem) -> some View {
        if item.kind == "owner" {
            HStack {
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: 2) {
                    let names = (item.to ?? []).compactMap { client.agent($0)?.name }
                    if !names.isEmpty {
                        Text("To " + names.joined(separator: ", ")).font(.system(size: 9)).foregroundStyle(theme.nookForeground.opacity(0.5))
                    }
                    Text(item.text).font(.system(size: 12)).textSelection(.enabled)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(theme.notch.accent.opacity(0.22), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
        } else if let agent = client.agent(item.agent) {
            line(for: agent, text: item.text, style: item.kind == "chirp" ? .chirp : item.kind == "problem" ? .problem : .plain)
        }
    }

    private func line(for agent: MacSpacesAgents.Agent, text: String, style: LineStyle) -> some View {
        HStack(alignment: .top, spacing: 7) {
            AgentCharacterView(character: agent.character, state: "idle", size: 22, avatar: client.avatar)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.nookForeground.opacity(0.6))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if style == .problem { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 10)) }
                    Text(text).font(.system(size: 12)).textSelection(.enabled)
                        .foregroundStyle(style == .problem ? Color.orange : theme.nookForeground)
                }
                .padding(.horizontal, style == .chirp ? 9 : 0).padding(.vertical, style == .chirp ? 5 : 0)
                .background(style == .chirp ? theme.notch.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Spacer(minLength: 40)
        }
    }

    // MARK: One bot

    private func botPage(_ agent: MacSpacesAgents.Agent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { client.focused = nil } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).help("Back to Together")
                Text(agent.name).font(.system(size: 13, weight: .semibold))
                Text("\(agent.engineName) · \(agent.job)").font(.system(size: 11)).foregroundStyle(theme.nookForeground.opacity(0.55)).lineLimit(1)
                Spacer()
                Button("Open in Tsukumo") { client.openInTsukumo(agent.id) }.buttonStyle(.borderless).font(.system(size: 11))
            }
            if let work = agent.work { workStrip(agent, work) }
            thread(client.feed.filter { $0.agent == agent.id || ($0.to ?? []).contains(agent.id) }, partials: true, only: agent.id)
        }
    }

    private func workStrip(_ agent: MacSpacesAgents.Agent, _ work: MacSpacesAgents.Work) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(theme.nookForeground.opacity(0.15), lineWidth: 3)
                Circle().trim(from: 0, to: work.progress ?? 0).stroke(theme.notch.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(work.headline).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if let file = work.file { Text(file).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.nookForeground.opacity(0.55)) }
            }
            Spacer()
            if let tests = work.tests {
                Label(tests.capitalized, systemImage: "flask.fill").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(tests == "passed" ? .green : tests == "failed" ? .red : .orange)
            }
            Toggle("Follow", isOn: Binding(get: { work.follow }, set: { client.setFollow(agent.id, on: $0) }))
                .toggleStyle(.switch).controlSize(.mini).font(.system(size: 10))
                .help("Follow its edits in your editor")
            if work.ready {
                Button("Review") { client.openReview(for: agent.id) }.buttonStyle(AccentPillButtonStyle(accent: theme.notch.accent)).controlSize(.small)
            }
        }
        .padding(.horizontal, 10).frame(height: 38)
        .background(theme.notch.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // MARK: Approvals

    private func approvalBar(_ approval: MacSpacesAgents.Approval) -> some View {
        HStack(spacing: 8) {
            if let agent = client.agent(approval.agent) {
                AgentCharacterView(character: agent.character, state: "needsYou", size: 22, avatar: client.avatar)
            }
            Text(approval.text).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                .help(approval.text)
            Spacer(minLength: 6)
            if client.approvals.count > 1 {
                Text("+\(client.approvals.count - 1)").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.nookForeground.opacity(0.5))
            }
            if approval.canAnswerHere {
                Button("Deny") { client.answer(approval, allow: false) }
                Button("Allow") { client.answer(approval, allow: true) }.buttonStyle(AccentPillButtonStyle(accent: theme.notch.accent))
            } else {
                if let reason = approval.reason { Text("It \(reason)").font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1) }
                Button("Deny") { client.answer(approval, allow: false) }
                Button("Open in Tsukumo") { client.openInTsukumo(approval.agent) }.buttonStyle(AccentPillButtonStyle(accent: theme.notch.accent))
            }
        }
        .controlSize(.small)
        .disabled(client.busy)
        .quickActionBar()
    }

    // MARK: Composer

    private var placeholder: String {
        if let agent = client.agent(client.focused) { return "Message \(agent.name)" }
        let names = client.tagged.compactMap { client.agent($0)?.name }
        return names.isEmpty ? "Message Together" : "Message " + names.joined(separator: " and ")
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $client.draft)
                .textFieldStyle(.plain).focused($composing)
                .onSubmit { client.send() }
            Button { client.send() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 17)) }
                .disabled(client.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || client.busy)
                .help("Send")
            Menu {
                Button("Open Tsukumo") { client.openInTsukumo() }
                if let agent = client.agent(client.focused) { Button("Open \(agent.name) in Tsukumo") { client.openInTsukumo(agent.id) } }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .quickActionBar()
    }

    private var pendingBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle").foregroundStyle(.orange)
            Text("Your last message may not have arrived.").lineLimit(1)
            Spacer()
            Button("Check") { client.checkPendingSend() }.help("Asks Tsukumo again. It never sends the same message twice.")
            Button("Discard") { client.discardPendingSend() }
        }
        .controlSize(.small)
        .quickActionBar()
    }

    // MARK: Review

    private func reviewSheet(_ review: MacSpacesAgents.Review) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Review").font(.system(size: 13, weight: .semibold))
                if let agent = client.agent(review.agent) { Text(agent.name).font(.system(size: 12)).foregroundStyle(theme.nookForeground.opacity(0.6)) }
                Text("+\(review.additions)").foregroundStyle(.green).font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text("−\(review.deletions)").foregroundStyle(.red).font(.system(size: 11, weight: .semibold, design: .monospaced))
                Spacer()
                Button { client.closeReview() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).help("Close review")
            }
            HStack(alignment: .top, spacing: 10) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(review.files, id: \.path) { file in
                            VStack(alignment: .leading, spacing: 1) {
                                Text((file.path as NSString).lastPathComponent).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                HStack(spacing: 6) {
                                    Text("+\(file.additions)").foregroundStyle(.green)
                                    Text("−\(file.deletions)").foregroundStyle(.red)
                                    Text(file.change).foregroundStyle(theme.nookForeground.opacity(0.45))
                                }
                                .font(.system(size: 10, design: .monospaced))
                            }
                            .help(file.path)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 170)
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(review.excerpt.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                            Text(String(line).isEmpty ? " " : String(line))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(line.hasPrefix("+") ? Color.green : line.hasPrefix("-") ? Color.red : theme.nookForeground.opacity(line.hasPrefix("@@") ? 0.5 : 0.8))
                                .fixedSize()
                        }
                        if review.truncated {
                            Text("Shows the first part; open in Tsukumo for all.").font(.system(size: 10)).foregroundStyle(theme.nookForeground.opacity(0.5)).padding(.top, 6)
                        }
                    }
                    .padding(8)
                }
                .background(theme.notch.control.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 8) {
                TextField("A note asking for changes", text: $note)
                    .textFieldStyle(.plain).focused($composing)
                Button("Request changes") { client.requestChanges(note); note = "" }
                    .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.count > MacSpacesAgents.maxNoteCharacters)
                Button("Accept") { client.acceptReview() }.buttonStyle(AccentPillButtonStyle(accent: theme.notch.accent))
                    .disabled(!review.canAccept)
                    .help(review.canAccept ? "Accepts exactly the changes shown" : "It's still working")
            }
            .controlSize(.small)
            .disabled(client.busy)
            .quickActionBar()
        }
    }

    // MARK: Not available

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.3.sequence.fill").font(.system(size: 26)).foregroundStyle(theme.notch.accent)
            Text(client.availability == .unknown ? "Looking for Tsukumo…" : "Your bots live in Tsukumo")
                .font(.system(size: 14, weight: .semibold))
            Text("Open an up-to-date Tsukumo and sign in to chat with your bots here.")
                .font(.system(size: 12)).foregroundStyle(theme.nookForeground.opacity(0.6))
            Button("Open Tsukumo") {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.zlichtman.kemosabe.mac") {
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                }
                Task { try? await Task.sleep(for: .seconds(3)); client.refreshAvailability(force: true) }
            }
            .buttonStyle(AccentPillButtonStyle(accent: theme.notch.accent))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stateDescription(_ state: String) -> String {
        switch state {
        case "working": return "working"
        case "thinking": return "thinking"
        case "talking": return "answering"
        case "chirping": return "has something to tell you"
        case "needsYou": return "needs you"
        case "done": return "done"
        case "sleeping": return "asleep"
        default: return "idle"
        }
    }
}

/// The page's main actions (Allow, Accept, Review) in the theme's accent. The Nook's panel is
/// usually not the key window, where the system's prominent style turns grey.
private struct AccentPillButtonStyle: ButtonStyle {
    let accent: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11).padding(.vertical, 4)
            .background(accent.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35), in: Capsule())
    }
}
