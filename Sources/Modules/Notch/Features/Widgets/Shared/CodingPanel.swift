import SwiftUI

/// The Terminal page: a thin rail of tabs on the left (the shell, your coding day:
/// agents, Homebrew, today's tokens, usage and limits, GitHub, dev servers), each tab
/// full height beside it. The shell stays mounted while another tab shows, so switching
/// never resets it. A dot on Agents means one needs you; a number on Homebrew counts
/// outdated packages once the tab has read them.
struct TerminalPage: View {
    @ObservedObject var shell: QuickShell
    var onEditingChanged: (Bool) -> Void = { _ in }
    @AppStorage("terminal.tab") private var tab: CodingPanel.Tab = .shell
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var agents = AgentActivityMonitor.shared
    @ObservedObject private var homebrew = HomebrewStore.shared
    /// The tile whose name shows beside the rail (after a short hover).
    @State private var hovered: CodingPanel.Tab?
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            rail
                // Centred down the page, above the tab so a hovered tile's name can sit over its edge.
                .frame(maxHeight: .infinity, alignment: .center)
                .zIndex(1)
            ZStack {
                // Always mounted, its header included, so the terminal keeps its host,
                // scrollback and size while another tab shows.
                VStack(alignment: .leading, spacing: TerminalTabMetrics.gap) {
                    TerminalTabHeader("Shell", details: shellDetails)
                    TerminalWidget(shell: shell, isPage: true, onEditingChanged: onEditingChanged)
                }
                .opacity(tab == .shell ? 1 : 0)
                .allowsHitTesting(tab == .shell)
                .accessibilityHidden(tab != .shell)
                if tab == .homebrew {
                    HomebrewPanel(store: homebrew) { line in runInShell(line) }
                    .transition(.opacity.combined(with: .offset(x: 6)))
                } else if tab != .shell {
                    CodingPanel(tab: tab, history: shell.history, runInShell: runInShell)
                        .id(tab)
                        .transition(.opacity.combined(with: .offset(x: 6)))
                }
            }
            // Every tab fills the space beside the rail, so each ends at the same inset;
            // taller ones stay inside the page instead of pushing it.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        // The page's frame sits 7 pt inside the panel's visible sides and 12 pt above its
        // bottom; this makes all three 16 pt, the same as above the content.
        .padding(.horizontal, 9)
        .padding(.bottom, 4)
        .onDisappear { hoverTask?.cancel(); hovered = nil }
    }

    /// What the shell is running (its window title), else what it is.
    private var shellDetails: [String] {
        let title = shell.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let login = (QuickShell.loginShell as NSString).lastPathComponent
        return [title, "\(login) · keeps running when the Nook closes", login].filter { !$0.isEmpty }
    }

    /// Types a line into the shell (nil just shows it) and switches to the Shell tab.
    private func runInShell(_ line: String?) {
        if let line { shell.run(line) }
        select(.shell)
    }

    private func select(_ item: CodingPanel.Tab) {
        hoverTask?.cancel(); hovered = nil
        withAnimation(theme.reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { tab = item }
    }

    // MARK: Rail

    private static let tile: CGFloat = 30
    private static let spacing: CGFloat = 4
    private static let groupGap: CGFloat = 10

    /// Where a tile starts: tiles `spacing` apart, each later group a further `groupGap` down.
    private static func top(of item: CodingPanel.Tab) -> CGFloat {
        let index = CGFloat(CodingPanel.Tab.allCases.firstIndex(of: item) ?? 0)
        return index * (tile + spacing) + CGFloat(item.group) * groupGap
    }

    private var rail: some View {
        VStack(spacing: Self.spacing) {
            ForEach(CodingPanel.Tab.allCases) { item in
                if item == .agents || item == .homebrew { Color.clear.frame(width: Self.tile, height: Self.groupGap - Self.spacing) }
                Button { select(item) } label: { railItem(item) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                    .onHover { inside in hover(item, inside) }
                    .overlay(alignment: .leading) { if hovered == item { railName(item) } }
            }
        }
        // One highlight that slides between tiles, its accent bar always inside it.
        .background(alignment: .top) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.1))
                Capsule().fill(theme.notch.accent).frame(width: 3, height: 14).padding(.leading, 2)
            }
            .frame(width: Self.tile, height: Self.tile)
            .offset(y: Self.top(of: tab))
            .animation(theme.reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: tab)
        }
        .frame(width: Self.tile, alignment: .top)
    }

    private func railItem(_ item: CodingPanel.Tab) -> some View {
        let selected = tab == item
        return Image(systemName: item.symbol)
            .font(.system(size: 13, weight: .medium))
            .imageScale(.medium)
            .frame(width: 18, height: 18)
            .foregroundStyle(selected ? theme.notch.accent : theme.nookForeground.opacity(0.55))
            .frame(width: Self.tile, height: Self.tile)
            .overlay(alignment: .topTrailing) { badge(item) }
            .contentShape(Rectangle())
    }

    /// The tab's name to the right of the rail, clear of every tile, after a short hover.
    private func railName(_ item: CodingPanel.Tab) -> some View {
        Text(item.title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.nookForeground)
            .padding(.horizontal, 8).frame(height: 22)
            .background(theme.notch.surface, in: Capsule())
            .background(Color.primary.opacity(0.12), in: Capsule().inset(by: -0.5))
            .fixedSize()
            .offset(x: Self.tile + 6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
    }

    private func hover(_ item: CodingPanel.Tab, _ inside: Bool) {
        hoverTask?.cancel()
        guard inside else {
            if hovered == item { hovered = nil }
            return
        }
        if hovered != nil { hovered = item; return }
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            withAnimation(theme.reduceMotion ? nil : .easeOut(duration: 0.12)) { hovered = item }
        }
    }

    @ViewBuilder
    private func badge(_ item: CodingPanel.Tab) -> some View {
        switch item {
        case .agents where agents.sessions.contains { $0.state == .needsYou }:
            Circle().fill(Color.orange).frame(width: 6, height: 6).padding(4)
        case .homebrew:
            if let count = homebrew.outdatedCount, count > 0 {
                Text("\(count)")
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 3)
                    .frame(minWidth: 13, minHeight: 13)
                    .background(theme.notch.accent, in: Capsule())
                    .padding(1)
            }
        default:
            EmptyView()
        }
    }
}

struct CodingPanel: View {
    var tab: Tab = .today
    /// The shell's past commands, newest last: Servers offers the dev servers among them.
    var history: [String] = []
    /// Types a line into the page's shell (nil just shows it) and switches to Shell.
    var runInShell: ((String?) -> Void)?
    @ObservedObject private var stats = CodingStats.shared
    @ObservedObject private var agents = AgentActivityMonitor.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var editingUser = false
    enum Tab: String, CaseIterable, Identifiable {
        // Three groups set apart by gaps: your stats (Today, Usage, GitHub), Agents alone
        // in the middle, then your Mac (Homebrew, Servers, and Shell nearest the bottom).
        case today, usage, github, agents, homebrew, servers, shell
        var id: String { rawValue }
        /// 0 for the stats, 1 for Agents, 2 for the Mac tools.
        var group: Int {
            switch self {
            case .today, .usage, .github: return 0
            case .agents: return 1
            case .homebrew, .servers, .shell: return 2
            }
        }
        var symbol: String {
            switch self {
            case .shell: return "apple.terminal"
            case .agents: return "brain.head.profile"
            case .homebrew: return "mug"
            case .today: return "sun.max"
            case .usage: return "chart.bar"
            case .github: return "square.grid.3x3"
            case .servers: return "server.rack"
            }
        }
        var title: String {
            switch self {
            case .shell: return "Shell"
            case .agents: return "Agents"
            case .homebrew: return "Homebrew"
            case .today: return "Today"
            case .usage: return "Usage"
            case .github: return "GitHub"
            case .servers: return "Servers"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TerminalTabMetrics.gap) {
            header
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    // MARK: Header

    /// The tab's shared header. Servers draws its own (it holds the scan), and the page
    /// draws Shell's and Homebrew's.
    @ViewBuilder
    private var header: some View {
        switch tab {
        case .shell, .homebrew, .servers:
            EmptyView()
        case .agents:
            TerminalTabHeader("Agents", details: agentDetails)
        case .today:
            TerminalTabHeader("Today", details: todayDetails)
        case .usage:
            TerminalTabHeader("Usage", details: usageDetails)
        case .github:
            TerminalTabHeader("GitHub", details: githubDetails) {
                if stats.contributions != nil, !editingUser, !stats.githubUser.isEmpty {
                    Button("@\(stats.githubUser)") { editingUser = true }
                        .buttonStyle(TerminalButtonStyle())
                        .help("Change the GitHub account")
                }
            }
        }
    }

    /// How many sessions need you, are working and finished.
    private var agentDetails: [String] {
        guard agents.isEnabled else { return ["Off"] }
        guard !agents.sessions.isEmpty else { return ["No sessions"] }
        let counts = Dictionary(grouping: agents.sessions, by: \.state).mapValues(\.count)
        let parts = [AgentActivityMonitor.Session.State.needsYou, .working, .done].compactMap { state in
            counts[state].flatMap { $0 > 0 ? "\($0) \(summaryLabel(state))" : nil }
        }
        let total = agents.sessions.count
        return [parts.joined(separator: " · "), "\(total) \(total == 1 ? "session" : "sessions")"]
    }

    private var todayDetails: [String] {
        let claude = stats.summary.today["claude"] ?? .init(), codex = stats.summary.today["codex"] ?? .init()
        let total = claude.total + codex.total
        guard total > 0 else { return ["Claude Code and Codex"] }
        return ["\(CodingStats.format(total)) tokens so far · \(CodingStats.format(claude.output + codex.output)) written",
                "\(CodingStats.format(total)) tokens so far"]
    }

    private var usageDetails: [String] {
        // The total is under By day; the line says what the cards cover.
        let projects = stats.summary.projects.count, models = stats.summary.models.count
        guard projects + models > 0 else { return ["Last two weeks"] }
        return ["Last two weeks · \(projects) \(projects == 1 ? "project" : "projects") · \(models) \(models == 1 ? "model" : "models")",
                "Last two weeks"]
    }

    private var githubDetails: [String] {
        if let calendar = stats.contributions, !editingUser {
            return ["\(calendar.total.formatted()) contributions in the last year", "\(calendar.total.formatted()) contributions"]
        }
        return [stats.githubUser.isEmpty || editingUser ? "Public contributions" : "@\(stats.githubUser)"]
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
            switch tab {
            case .shell, .homebrew:
                // The page shows these itself.
                EmptyView()
            case .agents:
                agentSection
            case .today where stats.summary.today.isEmpty && stats.summary.projects.isEmpty
                && stats.summary.models.isEmpty && stats.summary.codexLimits.isEmpty:
                EmptyTabMessage(systemImage: "sun.max", title: "Nothing yet today",
                                detail: "Today's tokens from Claude Code and Codex, and Codex's limits, show here once either runs on this Mac.",
                                action: openShell)
            case .today:
                // Two full-height columns: today's tokens, then the limits and what was used most.
                HStack(alignment: .top, spacing: TerminalTabMetrics.gap) {
                    tokenSection.frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: TerminalTabMetrics.gap) {
                        if !stats.summary.codexLimits.isEmpty { limitSection }
                        topSection
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .usage:
                if stats.summary.projects.isEmpty && stats.summary.models.isEmpty && stats.summary.days.isEmpty {
                    EmptyTabMessage(systemImage: "chart.bar", title: "No coding activity yet",
                                    detail: "Usage comes from Claude Code's and Codex's logs on this Mac. Use either and the last two weeks show here.",
                                    action: openShell)
                } else {
                    HStack(alignment: .top, spacing: TerminalTabMetrics.gap) {
                        VStack(spacing: TerminalTabMetrics.gap) {
                            // Four projects and three models fit the page with the tab bar.
                            ranking("Projects", stats.summary.projects, count: 4) { $0 }
                            ranking("Models", stats.summary.models, count: 3) { $0.replacingOccurrences(of: "claude-", with: "") }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        daysSection.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            case .github:
                if let calendar = stats.contributions, !editingUser {
                    VStack(spacing: TerminalTabMetrics.gap) {
                        githubSection(calendar)
                        githubStats(stats.contributionStats ?? calendar.stats())
                    }
                } else {
                    githubSetup
                }
            case .servers:
                serversSection
            }
    }

    /// "Open Shell" for an empty tab, when the page has a shell.
    private var openShell: (title: String, perform: () -> Void)? {
        guard let runInShell else { return nil }
        return ("Open Shell", { runInShell(nil) })
    }

    // MARK: Sections

    /// Every session, the ones that need you first: a permission request with Allow,
    /// Deny and Answer in App; then what each working agent is doing, what it was asked,
    /// how long and how many steps; then finished ones with their last reply.
    /// Click a session to go to its app.
    @ViewBuilder
    private var agentSection: some View {
        if !agents.isEnabled {
            EmptyTabMessage(peek: true, title: "See your coding agents here",
                            detail: "Each Claude Code or Codex session: what it's doing, its answers, and Allow or Deny when it asks for permission. This is Settings → Activities → Coding agents that need you.",
                            action: ("Turn On", { agents.setEnabled(true) }))
        } else if agents.sessions.isEmpty {
            VStack(spacing: TerminalTabMetrics.gap) {
                CodexHookNotice()
                EmptyTabMessage(peek: true, title: "No agents running",
                                detail: "Start Claude Code or Codex anywhere. Each session shows here while it works, and one that needs you comes first.",
                                action: openShell)
            }
        } else {
            // A "needs you" bubble scrolls to its session and outlines it.
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: TerminalTabMetrics.rowGap) {
                        CodexHookNotice().padding(.bottom, TerminalTabMetrics.gap - TerminalTabMetrics.rowGap)
                        ForEach(orderedSessions) { session in
                            Group {
                                if session.state == .needsYou { waitingCard(session) } else { agentRow(session) }
                            }
                            .id(session.id)
                        }
                    }
                }
                .onAppear { if let id = agents.spotlight { proxy.scrollTo(id, anchor: .top) } }
                .onChange(of: agents.spotlight) { id in
                    if let id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) } }
                }
            }
        }
    }

    /// Waiting first (longest wait on top), then working, then finished (newest first).
    private var orderedSessions: [AgentActivityMonitor.Session] {
        let rank: [AgentActivityMonitor.Session.State: Int] = [.needsYou: 0, .working: 1, .done: 2]
        return agents.sessions.sorted { a, b in
            if a.state != b.state { return rank[a.state, default: 3] < rank[b.state, default: 3] }
            return a.state == .needsYou ? a.updated < b.updated : a.updated > b.updated
        }
    }

    /// A session waiting on you: what it wants to do, and the answer buttons while its
    /// hook is waiting; otherwise why it's waiting and a way to its app.
    private func waitingCard(_ session: AgentActivityMonitor.Session) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            agentHeader(session)
            if let request = session.request {
                Text(request.title).font(.system(size: 12, weight: .semibold))
                if let detail = request.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced)).lineLimit(3).truncationMode(.tail)
                        .textSelection(.enabled)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                HStack(spacing: 6) {
                    Button("Allow") { agents.answer(session, .allow) }
                        .buttonStyle(TerminalButtonStyle(prominent: true))
                        .help("Allow this one request")
                    Button("Deny") { agents.answer(session, .deny) }
                        .buttonStyle(TerminalButtonStyle())
                        .help("Deny it; \(session.name) is told and carries on")
                    Button("Answer in \(session.appName ?? session.name)") { agents.answer(session, .app) }
                        .buttonStyle(TerminalButtonStyle())
                    Spacer(minLength: 0)
                    Text(session.updated.addingTimeInterval(AgentActivityMonitor.answerWait), style: .timer)
                        .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                        .help("Then \(session.appName ?? session.name)'s own prompt takes over")
                }
            } else {
                Text(session.note.map { $0 == "Needs permission" ? "Waiting for permission in \(session.appName ?? session.name)" : $0 } ?? "Waiting for you")
                    .font(.system(size: 12, weight: .semibold)).lineLimit(2)
                if let prompt = session.prompt { promptLine(prompt) }
                HStack(spacing: 6) {
                    Button("Go to \(session.appName ?? session.name)") { agents.reveal(session) }
                        .buttonStyle(TerminalButtonStyle(prominent: true))
                        .disabled(session.appBundleID.isEmpty)
                    Spacer(minLength: 0)
                    Text(session.updated, style: .relative).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .padding(TerminalTabMetrics.cardPadding)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: TerminalTabMetrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TerminalTabMetrics.cardRadius, style: .continuous)
                .strokeBorder(session.id == agents.spotlight ? theme.notch.accent : Color.orange.opacity(0.35),
                              lineWidth: session.id == agents.spotlight ? 1.5 : 1)
        }
    }

    /// A working or finished session as a list row: its app's icon, the project and
    /// agent, what it's doing (or its last reply) with what it was asked, and its state,
    /// time and steps.
    private func agentRow(_ session: AgentActivityMonitor.Session) -> some View {
        let line = session.state == .done ? (session.reply.flatMap { $0.isEmpty ? nil : $0 } ?? session.headline) : session.headline
        let subtitle = [line, session.prompt.map { "“\($0)”" }].compactMap { $0 }.joined(separator: "  ")
        return Button { agents.reveal(session) } label: {
            TerminalRow(session.project.isEmpty ? session.name : session.project,
                        label: [session.name, session.appLabel].compactMap { $0 }.joined(separator: " · "),
                        subtitle: subtitle) {
                agentIcon(session)
            } trailing: {
                VStack(alignment: .trailing, spacing: 2) {
                    statePill(session.state)
                    HStack(spacing: 6) {
                        if session.state == .done {
                            Text(session.updated, style: .relative).monospacedDigit()
                        } else if let started = session.started {
                            Text(started, style: .relative).monospacedDigit()
                        }
                        if session.steps > 0 { Text("\(session.steps) steps").monospacedDigit() }
                    }
                    .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                .fixedSize()
            }
            .opacity(session.state == .done ? 0.85 : 1)
        }
        .buttonStyle(.plain)
        .help([session.appName.map { "Go to \($0)" }, session.state == .done ? session.reply : nil].compactMap { $0 }.joined(separator: "\n\n"))
    }

    /// The session's own app icon; a plain glyph when it isn't known.
    private func agentIcon(_ session: AgentActivityMonitor.Session) -> some View {
        // The app it runs in, else the agent's own app: never a stand-in symbol.
        Image(nsImage: AgentActivityMonitor.icon(for: session) ?? AgentActivityMonitor.agentIcon(for: session))
            .resizable()
            .frame(width: 20, height: 20)
    }

    private func statePill(_ state: AgentActivityMonitor.Session.State) -> some View {
        Text(label(state))
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(color(state))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color(state).opacity(0.14), in: Capsule())
    }

    /// Icon, project, agent (and its app when that adds something) and state.
    private func agentHeader(_ session: AgentActivityMonitor.Session) -> some View {
        HStack(spacing: 8) {
            agentIcon(session)
            Text(session.project.isEmpty ? session.name : session.project).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text([session.name, session.appLabel].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            statePill(session.state)
        }
    }

    private func promptLine(_ prompt: String) -> some View {
        Text("“\(prompt)”").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
    }

    /// Today's totals large in the middle of their card, what each agent wrote under
    /// them, and Claude's five-hour window at the foot.
    private var tokenSection: some View {
        section("Tokens", fill: true) {
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 22) {
                stat(stats.summary.today["claude"] ?? .init(), "Claude Code")
                stat(stats.summary.today["codex"] ?? .init(), "Codex")
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            Text("Claude, last 5 hours: \(CodingStats.format(stats.summary.claudeWindow.total)) tokens · \(CodingStats.format(stats.summary.claudeWindow.output)) written")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var limitSection: some View {
        section("Codex limits") {
            ForEach(stats.summary.codexLimits, id: \.name) { limit in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(limit.name).font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text("\(Int(limit.usedPercent.rounded()))%").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(limit.usedPercent >= 90 ? .orange : .primary)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(limit.usedPercent >= 90 ? Color.orange : theme.notch.accent)
                                .frame(width: proxy.size.width * min(1, max(0, limit.usedPercent / 100)))
                        }
                    }
                    .frame(height: 5)
                    if let reset = limit.resetsAt {
                        Text("Resets \(reset, format: .relative(presentation: .named))").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var daysSection: some View {
        let calendar = Calendar.current
        let days = (0..<14).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: Date())) }
        let values = days.map { stats.summary.days[$0]?.total ?? 0 }
        let peak = max(values.max() ?? 1, 1)
        return section("By day", fill: true) {
            GeometryReader { proxy in
                // Room for the weekday letters under the bars.
                let room = max(2, proxy.size.height - 14)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(zip(days, values)), id: \.0) { day, value in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(calendar.isDateInToday(day) ? theme.notch.accent : theme.notch.accent.opacity(0.45))
                                .frame(height: max(2, room * CGFloat(value) / CGFloat(peak)))
                            Text(String(day.formatted(.dateTime.weekday(.narrow))))
                                .font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .help("\(day.formatted(.dateTime.weekday().day())): \(CodingStats.format(value)) tokens")
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            }
            .frame(minHeight: 60, maxHeight: .infinity)
            HStack {
                Text("\(CodingStats.format(values.reduce(0, +))) tokens").monospacedDigit()
                Spacer()
                Text("peak \(CodingStats.format(peak))").monospacedDigit()
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var topSection: some View {
        section("Most used", fill: true) {
            if stats.summary.projects.isEmpty && stats.summary.models.isEmpty {
                Text("Nothing in the last two weeks").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(top(stats.summary.projects, 3), id: \.0) { name, value in row(name, value) }
            }
            if !stats.summary.models.isEmpty { Divider().opacity(0.5) }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(top(stats.summary.models, 3), id: \.0) { name, value in row(name.replacingOccurrences(of: "claude-", with: ""), value) }
            }
        }
    }

    private func githubSection(_ calendar: CodingStats.ContributionCalendar) -> some View {
        // The total and the account are in the tab's header.
        section("Last 53 weeks") {
            ContributionStrip(days: Array(calendar.days.suffix(7 * 53)), accent: theme.notch.accent)
        }
    }

    /// No calendar yet: the account field, and why nothing shows (loading, unknown, offline).
    private var githubSetup: some View {
        let status: String
        if let problem = stats.contributionsProblem {
            status = problem
        } else if !stats.githubUser.isEmpty && !editingUser {
            status = "Loading contributions…"
        } else {
            status = "Your public contribution calendar, streaks and busiest months. No token needed."
        }
        return EmptyTabMessage(systemImage: "square.grid.3x3", title: "Your year on GitHub", detail: status) {
            if stats.githubUser.isEmpty || editingUser || stats.contributionsProblem != nil {
                HStack(spacing: 6) {
                    TextField("GitHub username", text: $stats.githubUser)
                        .textFieldStyle(.plain).font(.system(size: 11))
                        .padding(.horizontal, 10)
                        .frame(width: 200, height: TerminalTabMetrics.controlHeight)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .onSubmit { editingUser = false }
                    if editingUser && stats.contributions != nil {
                        Button("Done") { editingUser = false }.buttonStyle(TerminalButtonStyle())
                    }
                }
            }
        }
    }

    /// Running servers with Open and Stop; with none, the dev servers you've started
    /// from this shell before, each a click from running again.
    private var serversSection: some View {
        let recent = DevServers.startCommands(in: history)
        return DevServersWidget(page: true, empty: AnyView(
            EmptyTabMessage(systemImage: "server.rack", title: "No dev servers running",
                            detail: recent.isEmpty
                                ? "Start one in Shell, such as npm run dev, and it shows here with Open and Stop."
                                : "Start one again, or another in Shell; it shows here with Open and Stop.",
                            action: openShell) {
                if !recent.isEmpty, let runInShell {
                    VStack(spacing: TerminalTabMetrics.rowGap) {
                        ForEach(recent, id: \.self) { line in
                            TerminalRow(line, monospacedTitle: true) {
                                Button("Run") { runInShell(line) }
                                    .buttonStyle(TerminalButtonStyle(prominent: true))
                                    .help("Types \(line) into Shell")
                            }
                        }
                    }
                    .frame(maxWidth: 360)
                }
            }
        ))
    }

    /// A ranked list with a bar for each, scaled to the first.
    private func ranking(_ title: String, _ values: [String: Int], count: Int, name: @escaping (String) -> String) -> some View {
        let rows = top(values, count)
        let peak = max(rows.first?.1 ?? 1, 1)
        return section(title, fill: true) {
            if rows.isEmpty {
                Text("Nothing in the last two weeks").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.0) { key, value in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(name(key)).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(CodingStats.format(value)).font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    GeometryReader { proxy in
                        Capsule().fill(theme.notch.accent.opacity(0.75))
                            .frame(width: max(3, proxy.size.width * CGFloat(value) / CGFloat(peak)))
                    }
                    .frame(height: 4)
                }
            }
        }
    }

    /// The year in numbers: streaks, this week, the best day, and a bar per month.
    private func githubStats(_ numbers: CodingStats.ContributionCalendar.Stats) -> some View {
        HStack(alignment: .top, spacing: TerminalTabMetrics.gap) {
            // The four tiles and the Months card share the row's full height.
            VStack(spacing: TerminalTabMetrics.gap) {
                HStack(spacing: TerminalTabMetrics.gap) {
                    statTile("\(numbers.currentStreak)", "day streak")
                    statTile("\(numbers.longestStreak)", "longest streak")
                }
                HStack(spacing: TerminalTabMetrics.gap) {
                    statTile("\(numbers.thisWeek)", "this week")
                    statTile("\(numbers.bestDayCount)", numbers.bestDay.flatMap(Self.dayLabel).map { "best day · \($0)" } ?? "best day")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            section("Months", fill: true) {
                let peak = max(numbers.monthTotals.max() ?? 1, 1)
                GeometryReader { proxy in
                    let room = max(2, proxy.size.height - 14)
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(Array(zip(numbers.months.indices, numbers.months)), id: \.0) { index, month in
                            VStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(index == numbers.months.count - 1 ? theme.notch.accent : theme.notch.accent.opacity(0.45))
                                    .frame(height: max(2, room * CGFloat(numbers.monthTotals[index]) / CGFloat(peak)))
                                Text(String(month.prefix(1))).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .help("\(month): \(numbers.monthTotals[index]) contributions")
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
                }
                .frame(minHeight: 40, maxHeight: .infinity)
                HStack {
                    Text("\(numbers.activeDays) active days").monospacedDigit()
                    Spacer()
                    if let weekday = numbers.busiestWeekday { Text("Busiest on \(weekday)s") }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(theme.notch.accent)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(TerminalTabMetrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(TerminalTabMetrics.fill, in: RoundedRectangle(cornerRadius: TerminalTabMetrics.cardRadius, style: .continuous))
    }

    private static func dayLabel(_ key: String) -> String? {
        let parser = DateFormatter(); parser.dateFormat = "yyyy-MM-dd"; parser.locale = Locale(identifier: "en_US_POSIX")
        return parser.date(from: key).map { $0.formatted(.dateTime.month(.abbreviated).day()) }
    }

    // MARK: Pieces

    /// A titled card. `fill` stretches it to the height it's offered, content at the top,
    /// so cards in a row line up and the tab ends at the page's bottom inset.
    private func section<Content: View>(_ title: String, fill: Bool = false, @ViewBuilder _ content: @escaping () -> Content) -> some View {
        TerminalCard(title: title, fill: fill, content: content)
    }

    private func stat(_ tokens: CodingStats.Tokens, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(CodingStats.format(tokens.total)).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(theme.notch.accent)
            Text(label).font(.system(size: 11, weight: .semibold))
            Text("\(CodingStats.format(tokens.output)) written").font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func row(_ name: String, _ value: Int) -> some View {
        HStack {
            Text(name).font(.system(size: 11)).lineLimit(1)
            Spacer()
            Text(CodingStats.format(value)).font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func top(_ values: [String: Int], _ count: Int) -> [(String, Int)] {
        Array(values.sorted { $0.value > $1.value }.prefix(count)).map { ($0.key, $0.value) }
    }

    private func color(_ state: AgentActivityMonitor.Session.State) -> Color {
        switch state { case .needsYou: return .orange; case .done: return .green; case .working: return theme.notch.accent }
    }

    private func label(_ state: AgentActivityMonitor.Session.State) -> String {
        switch state { case .needsYou: return "Needs you"; case .done: return "Done"; case .working: return "Working" }
    }

    private func summaryLabel(_ state: AgentActivityMonitor.Session.State) -> String {
        switch state { case .needsYou: return "need you"; case .done: return "finished"; case .working: return "working" }
    }
}

/// A Terminal tab with nothing to show: a compact, centred message with what to do
/// next, never an empty card. `extra` sits between the words and the button.
struct EmptyTabMessage<Extra: View>: View {
    var systemImage: String?
    var peek = false
    let title: String
    let detail: String
    var action: (title: String, perform: () -> Void)?
    @ViewBuilder var extra: () -> Extra

    init(systemImage: String? = nil, peek: Bool = false, title: String, detail: String,
         action: (title: String, perform: () -> Void)? = nil, @ViewBuilder extra: @escaping () -> Extra) {
        self.systemImage = systemImage
        self.peek = peek
        self.title = title
        self.detail = detail
        self.action = action
        self.extra = extra
    }

    var body: some View {
        VStack(spacing: 6) {
            if peek {
                Image(systemName: "brain.head.profile").font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary).padding(.bottom, 2)
            } else if let systemImage {
                Image(systemName: systemImage).font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary).padding(.bottom, 2)
            }
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 380).fixedSize(horizontal: false, vertical: true)
            extra().padding(.top, 4)
            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(TerminalButtonStyle(prominent: true))
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyTabMessage where Extra == EmptyView {
    init(systemImage: String? = nil, peek: Bool = false, title: String, detail: String,
         action: (title: String, perform: () -> Void)? = nil) {
        self.init(systemImage: systemImage, peek: peek, title: title, detail: detail, action: action) { EmptyView() }
    }
}

/// The last weeks of GitHub contributions, in the theme's accent.
struct ContributionStrip: View {
    let days: [(String, Int)]
    let accent: Color
    @State private var hovered: Int?

    /// One Canvas for the whole year (371 squares), with a single tooltip for the day under
    /// the pointer: a view and a tooltip per square made the tab slow to open.
    var body: some View {
        let columns = max(1, (days.count + 6) / 7)
        GeometryReader { proxy in
            let cell = min((proxy.size.width - CGFloat(columns - 1) * 2) / CGFloat(columns), (proxy.size.height + 2) / 7 - 2)
            let step = cell + 2
            let left = (proxy.size.width - (CGFloat(columns) * step - 2)) / 2
            Canvas { context, _ in
                for (index, day) in days.enumerated() {
                    let rect = CGRect(x: left + CGFloat(index / 7) * step, y: CGFloat(index % 7) * step, width: cell, height: cell)
                    let fill = day.1 == 0 ? Color.primary.opacity(0.08) : accent.opacity(0.25 + 0.75 * Double(day.1) / 4)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(fill))
                }
            }
            .onContinuousHover { phase in
                guard case let .active(point) = phase, cell > 0 else { hovered = nil; return }
                let column = Int((point.x - left) / step), row = Int(point.y / step)
                let index = column * 7 + row
                hovered = point.x >= left && (0..<7).contains(row) && days.indices.contains(index) ? index : nil
            }
            .help(hovered.map { days[$0].0 } ?? "")
        }
        .aspectRatio(CGFloat(max(1, (days.count + 6) / 7)) / 7, contentMode: .fit)
    }
}

/// Codex runs a hook only after it's reviewed in Codex's /hooks, and again after it
/// changes; until then Codex sessions never reach MacSpaces. Says so, with the fix.
struct CodexHookNotice: View {
    /// Settings → Activities shows it too, with Settings' own button.
    var inSettings = false
    @ObservedObject private var review = CodexHookReview.shared

    var body: some View {
        Group {
            if review.needsReview > 0 {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Codex hasn't approved MacSpaces' hooks yet").font(.system(size: 11, weight: .semibold))
                        Text("Codex runs a hook only after you review it, so its sessions can't show here. In Codex, type /hooks and trust the \(review.needsReview) MacSpaces \(review.needsReview == 1 ? "hook" : "hooks"), then restart Codex.")
                            .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if inSettings {
                        Button("Check Again") { review.check(force: true) }.buttonStyle(.settings())
                    } else {
                        Button("Check Again") { review.check(force: true) }.buttonStyle(TerminalButtonStyle())
                    }
                }
                .padding(TerminalTabMetrics.cardPadding)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: TerminalTabMetrics.cardRadius, style: .continuous))
            }
        }
        .onAppear { review.check() }
    }
}
