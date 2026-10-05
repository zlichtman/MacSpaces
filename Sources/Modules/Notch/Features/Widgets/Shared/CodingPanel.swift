import SwiftUI

/// The Terminal page: one tab bar for the shell and your coding day (agents and
/// today's tokens, usage and limits, GitHub, dev servers), each full width. The
/// shell stays mounted while another tab shows, so switching never resets it.
struct TerminalPage: View {
    @ObservedObject var shell: QuickShell
    var onEditingChanged: (Bool) -> Void = { _ in }
    @AppStorage("terminal.tab") private var tab: CodingPanel.Tab = .shell
    @ObservedObject private var theme = ThemeStore.shared
    @Namespace private var pill

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(CodingPanel.Tab.allCases) { item in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tab = item }
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .foregroundStyle(tab == item ? Color.black.opacity(0.85) : theme.nookForeground.opacity(0.75))
                            .background {
                                if tab == item {
                                    Capsule().fill(theme.notch.accent).matchedGeometryEffect(id: "pill", in: pill)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.06), in: Capsule())
            ZStack {
                // Always mounted: the terminal view keeps its host and scrollback.
                TerminalWidget(shell: shell, isPage: true, onEditingChanged: onEditingChanged)
                    .opacity(tab == .shell ? 1 : 0)
                    .allowsHitTesting(tab == .shell)
                if tab != .shell {
                    CodingPanel(tab: tab)
                        .id(tab)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct CodingPanel: View {
    var tab: Tab = .today
    @ObservedObject private var stats = CodingStats.shared
    @ObservedObject private var agents = AgentActivityMonitor.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var editingUser = false
    enum Tab: String, CaseIterable, Identifiable {
        case shell, agents, today, usage, github, servers
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .shell: return "apple.terminal"
            case .agents: return "sparkles"
            case .today: return "sparkle"
            case .usage: return "chart.bar.fill"
            case .github: return "square.grid.3x3.fill"
            case .servers: return "server.rack"
            }
        }
        var title: String {
            switch self {
            case .shell: return "Shell"
            case .agents: return "Agents"
            case .today: return "Today"
            case .usage: return "Usage"
            case .github: return "GitHub"
            case .servers: return "Servers"
            }
        }
    }

    var body: some View {
        Group {
            switch tab {
            case .shell:
                EmptyView()
            case .agents:
                agentSection
            case .today:
                HStack(alignment: .top, spacing: 10) {
                    tokenSection.frame(maxWidth: .infinity)
                    Group { if stats.summary.codexLimits.isEmpty { topSection } else { limitSection } }
                        .frame(maxWidth: .infinity)
                }
            case .usage:
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 10) {
                        ranking("Projects", stats.summary.projects, count: 5) { $0 }
                        ranking("Models", stats.summary.models, count: 4) { $0.replacingOccurrences(of: "claude-", with: "") }
                    }
                    .frame(maxWidth: .infinity)
                    daysSection.frame(maxWidth: .infinity)
                }
            case .github:
                VStack(spacing: 10) {
                    githubSection
                    if let calendar = stats.contributions { githubStats(calendar.stats()) }
                }
            case .servers:
                section("Dev servers") { DevServersWidget().frame(height: 200).padding(-8) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    // MARK: Sections

    /// Every session: the app it's in, the project, what it's doing right now, what
    /// it was asked, how long and how many steps. Click one to go to its app.
    @ViewBuilder
    private var agentSection: some View {
        if !agents.isEnabled {
            section("Agents") {
                Text("Turn on Settings → Activities → Coding agents to see each session here and beside the notch: the app it's in, what it's doing and when it needs you.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Turn On") { agents.setEnabled(true) }.buttonStyle(WidgetChipStyle(prominent: true, height: 26))
            }
        } else if agents.sessions.isEmpty {
            section("Agents") {
                Text("No agents running. Start Claude Code or Codex and they show up here.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(agents.sessions) { session in agentRow(session) }
                }
            }
        }
    }

    private func agentRow(_ session: AgentActivityMonitor.Session) -> some View {
        Button { agents.reveal(session) } label: {
            HStack(alignment: .top, spacing: 10) {
                Group {
                    if let icon = AgentActivityMonitor.icon(for: session) {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "sparkles").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.notch.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.project.isEmpty ? session.name : session.project).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text([session.name, session.appName].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(label(session.state))
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(color(session.state))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(color(session.state).opacity(0.14), in: Capsule())
                    }
                    Text(session.state == .needsYou ? (session.note ?? "Waiting for you") : session.headline)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(session.state == .needsYou ? Color.orange : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 8) {
                        if let prompt = session.prompt, !prompt.isEmpty {
                            Text("“\(prompt)”").lineLimit(1).truncationMode(.tail)
                        }
                        Spacer(minLength: 0)
                        if let started = session.started {
                            Text(started, style: .relative).monospacedDigit()
                        }
                        if session.steps > 0 { Text("\(session.steps) steps").monospacedDigit() }
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(session.appName.map { "Go to \($0)" } ?? "")
    }

    private var tokenSection: some View {
        section("Today") {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                stat(CodingStats.format(stats.summary.today["claude"]?.total ?? 0), "Claude Code")
                stat(CodingStats.format(stats.summary.today["codex"]?.total ?? 0), "Codex")
            }
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
        return section("Last two weeks") {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(zip(days, values)), id: \.0) { day, value in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(calendar.isDateInToday(day) ? theme.notch.accent : theme.notch.accent.opacity(0.45))
                            .frame(height: max(2, 196 * CGFloat(value) / CGFloat(peak)))
                        Text(String(day.formatted(.dateTime.weekday(.narrow))))
                            .font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(day.formatted(.dateTime.weekday().day())): \(CodingStats.format(value)) tokens")
                }
            }
            .frame(height: 212, alignment: .bottom)
            HStack {
                Text("\(CodingStats.format(values.reduce(0, +))) tokens").monospacedDigit()
                Spacer()
                Text("peak \(CodingStats.format(peak))").monospacedDigit()
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var topSection: some View {
        section("Most used") {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(top(stats.summary.projects, 2), id: \.0) { name, value in row(name, value) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(top(stats.summary.models, 2), id: \.0) { name, value in row(name.replacingOccurrences(of: "claude-", with: ""), value) }
                }
            }
        }
    }

    private var githubSection: some View {
        section("GitHub") {
            if stats.githubUser.isEmpty || editingUser {
                TextField("GitHub username", text: $stats.githubUser)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11))
                    .onSubmit { editingUser = false }
            }
            if let calendar = stats.contributions {
                ContributionStrip(days: Array(calendar.days.suffix(7 * 53)), accent: theme.notch.accent)
                HStack {
                    Text("\(calendar.total.formatted()) contributions in the last year").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button("@\(stats.githubUser)") { editingUser.toggle() }.buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.notch.accent)
                        .help("Change the GitHub account")
                }
            } else if !stats.githubUser.isEmpty {
                Text("Loading contributions…").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    /// A ranked list with a bar for each, scaled to the first.
    private func ranking(_ title: String, _ values: [String: Int], count: Int, name: @escaping (String) -> String) -> some View {
        let rows = top(values, count)
        let peak = max(rows.first?.1 ?? 1, 1)
        return section(title) {
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
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    statTile("\(numbers.currentStreak)", numbers.currentStreak == 1 ? "day streak" : "day streak")
                    statTile("\(numbers.longestStreak)", "longest streak")
                }
                HStack(spacing: 10) {
                    statTile("\(numbers.thisWeek)", "this week")
                    statTile("\(numbers.bestDayCount)", numbers.bestDay.flatMap(Self.dayLabel).map { "best day · \($0)" } ?? "best day")
                }
            }
            .frame(maxWidth: .infinity)
            section("Months") {
                let peak = max(numbers.monthTotals.max() ?? 1, 1)
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(zip(numbers.months.indices, numbers.months)), id: \.0) { index, month in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(index == numbers.months.count - 1 ? theme.notch.accent : theme.notch.accent.opacity(0.45))
                                .frame(height: max(2, 64 * CGFloat(numbers.monthTotals[index]) / CGFloat(peak)))
                            Text(String(month.prefix(1))).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .help("\(month): \(numbers.monthTotals[index]) contributions")
                    }
                }
                .frame(height: 78, alignment: .bottom)
                HStack {
                    Text("\(numbers.activeDays) active days").monospacedDigit()
                    Spacer()
                    if let weekday = numbers.busiestWeekday { Text("Busiest on \(weekday)s") }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(theme.notch.accent)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private static func dayLabel(_ key: String) -> String? {
        let parser = DateFormatter(); parser.dateFormat = "yyyy-MM-dd"; parser.locale = Locale(identifier: "en_US_POSIX")
        return parser.date(from: key).map { $0.formatted(.dateTime.month(.abbreviated).day()) }
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.3).foregroundStyle(.secondary)
            content()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(theme.notch.accent)
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
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
}

/// The last weeks of GitHub contributions, in the theme's accent.
struct ContributionStrip: View {
    let days: [(String, Int)]
    let accent: Color

    var body: some View {
        let weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        HStack(spacing: 2) {
            ForEach(weeks.indices, id: \.self) { column in
                VStack(spacing: 2) {
                    ForEach(weeks[column].indices, id: \.self) { row in
                        let level = weeks[column][row].1
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(level == 0 ? Color.primary.opacity(0.08) : accent.opacity(0.25 + 0.75 * Double(level) / 4))
                            .aspectRatio(1, contentMode: .fit)
                            .help("\(weeks[column][row].0)")
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
