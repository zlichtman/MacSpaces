import SwiftUI

/// The Terminal page: the shell, and beside it everything about your coding
/// day: agents working right now, Claude Code and Codex tokens, Codex's plan
/// limits, the last two weeks, top projects and models, your GitHub
/// contributions and local dev servers.
struct TerminalPage: View {
    @ObservedObject var shell: QuickShell
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TerminalWidget(shell: shell, isPage: true, onEditingChanged: onEditingChanged)
                .frame(maxWidth: .infinity)
            CodingPanel()
                .frame(width: 270)
        }
    }
}

struct CodingPanel: View {
    @ObservedObject private var stats = CodingStats.shared
    @ObservedObject private var agents = AgentActivityMonitor.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var editingUser = false
    @AppStorage("coding.tab") private var tab: Tab = .today

    enum Tab: String, CaseIterable, Identifiable {
        case today, usage, github, servers
        var id: String { rawValue }
        var title: String {
            switch self {
            case .today: return "Today"
            case .usage: return "Usage"
            case .github: return "GitHub"
            case .servers: return "Servers"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            Group {
                switch tab {
                case .today:
                    VStack(alignment: .leading, spacing: 8) { agentSection; tokenSection }
                case .usage:
                    VStack(alignment: .leading, spacing: 6) {
                        if !stats.summary.codexLimits.isEmpty { limitSection }
                        daysSection
                        topSection
                    }
                case .github:
                    githubSection
                case .servers:
                    section("Dev servers") { DevServersWidget().frame(height: 210).padding(-8) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    // MARK: Sections

    @ViewBuilder
    private var agentSection: some View {
        section("Agents") {
            if !agents.isEnabled {
                Text("Turn on Settings → Activities → Coding agents to see sessions here and beside the notch.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else if agents.sessions.isEmpty {
                Text("No agents running").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ForEach(agents.sessions) { session in
                    HStack(spacing: 6) {
                        Circle().fill(color(session.state)).frame(width: 7, height: 7)
                        Text(session.name).font(.system(size: 11, weight: .semibold))
                        Text(session.project).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(label(session.state)).font(.system(size: 10, weight: .semibold)).foregroundStyle(color(session.state))
                    }
                }
            }
        }
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
                    RoundedRectangle(cornerRadius: 2)
                        .fill(calendar.isDateInToday(day) ? theme.notch.accent : theme.notch.accent.opacity(0.45))
                        .frame(height: max(2, 30 * CGFloat(value) / CGFloat(peak)))
                        .frame(maxWidth: .infinity)
                        .help("\(day.formatted(.dateTime.weekday().day())): \(CodingStats.format(value)) tokens")
                }
            }
            .frame(height: 30, alignment: .bottom)
            Text("\(CodingStats.format(values.reduce(0, +))) tokens").font(.system(size: 10)).foregroundStyle(.secondary)
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
                ContributionStrip(days: Array(calendar.days.suffix(7 * 30)), accent: theme.notch.accent)
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
