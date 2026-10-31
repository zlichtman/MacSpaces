import AppKit
import SwiftUI

/// The Terminal page's Homebrew tab: what's installed, what's outdated, and two
/// buttons, Update (`brew update`) and Upgrade (`brew upgrade`); a row's Upgrade does
/// one package. Nothing runs until you press one. A running command shows in a strip
/// with its last line, its output on request, and Stop; one that needs your password
/// can be sent to the Shell tab instead.
struct HomebrewPanel: View {
    @ObservedObject var store: HomebrewStore
    /// Types a command into the page's shell and shows the Shell tab.
    var runInShell: (String) -> Void = { _ in }
    @ObservedObject private var theme = ThemeStore.shared
    @State private var filter: Filter?
    @State private var query = ""
    @State private var showsOutput = false

    enum Filter: String, CaseIterable, Identifiable {
        case outdated, formulae, casks
        var id: String { rawValue }
        var title: String {
            switch self {
            case .outdated: return "Outdated"
            case .formulae: return "Formulae"
            case .casks: return "Casks"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TerminalTabMetrics.gap) {
            header
            switch store.status {
            case .missing:
                message("Homebrew isn't installed", "It installs command-line tools and apps with one command. Install it from brew.sh, then check again.", link: true)
            case .failed(let reason):
                message("Couldn't read your packages", reason, retry: true)
            case .idle, .loading where store.packages.isEmpty:
                message("Reading your packages", "This takes a second or two and never goes online.", spinner: true)
            default:
                if let job = store.job { jobStrip(job) }
                if showsOutput, let job = store.job { output(job) } else { list }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { store.load() }
    }

    // MARK: Header

    private var outdated: [HomebrewPackage] { store.packages.filter(\.outdated) }
    private var upgradable: Int { outdated.filter { !$0.pinned }.count }
    private var busy: Bool { store.job?.running == true }

    /// The shared header: counts and when the lists were updated, Update and Upgrade,
    /// and the filters beneath while the list shows.
    private var header: some View {
        TerminalTabHeader("Homebrew", details: details) {
            if store.status != .missing {
                Button { store.run(.update) } label: {
                    Label("Update", systemImage: "arrow.clockwise")
                }
                .buttonStyle(TerminalButtonStyle())
                .disabled(busy)
                .help("Runs brew update: fetches Homebrew's lists of new versions. Upgrades nothing.")
                Button { store.run(.upgradeAll) } label: {
                    Label(upgradable > 0 ? "Upgrade \(upgradable)" : "Upgrade", systemImage: "arrow.up")
                }
                .buttonStyle(TerminalButtonStyle(prominent: true))
                .disabled(busy || upgradable == 0)
                .help("Runs brew upgrade: upgrades every outdated package that isn't pinned.")
            }
        } filters: {
            if showsFilters { filters }
        }
    }

    private var showsFilters: Bool {
        switch store.status {
        case .missing, .failed: return false
        case .idle, .loading where store.packages.isEmpty: return false
        default: return !(showsOutput && store.job != nil)
        }
    }

    /// Longest first; the header shows the first that fits, never a word cut short.
    private var details: [String] {
        switch store.status {
        case .missing: return ["Not installed"]
        case .failed: return ["Couldn't read your packages"]
        default: break
        }
        guard !store.packages.isEmpty else { return ["Reading your packages"] }
        let counts = HomebrewCatalog.counts(store.packages)
        let total = "\(store.packages.count) \(store.packages.count == 1 ? "package" : "packages")"
        guard let date = store.listsUpdated else { return [counts, total] }
        let full = RelativeDateTimeFormatter(), short = RelativeDateTimeFormatter()
        short.unitsStyle = .abbreviated
        return ["\(counts) · lists updated \(full.localizedString(for: date, relativeTo: Date()))",
                "\(counts) · updated \(short.localizedString(for: date, relativeTo: Date()))",
                counts, total]
    }

    // MARK: Filters and list

    private var current: Filter { filter ?? (outdated.isEmpty ? .formulae : .outdated) }

    private var filters: some View {
        TerminalFilterRow(query: $query) {
            ForEach(Filter.allCases) { item in
                TerminalFilterChip(title: item.title, count: item == .outdated ? outdated.count : 0,
                                   selected: current == item) { filter = item }
            }
        }
    }

    private var shown: [HomebrewPackage] {
        let base: [HomebrewPackage]
        switch current {
        case .outdated: base = outdated
        case .formulae: base = store.packages.filter { $0.kind == .formula }
        case .casks: base = store.packages.filter { $0.kind == .cask }
        }
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(needle) || $0.name.localizedCaseInsensitiveContains(needle) }
    }

    @ViewBuilder
    private var list: some View {
        let rows = shown
        if rows.isEmpty {
            Text(current == .outdated && query.isEmpty ? "Everything is up to date. Update fetches Homebrew's newest lists." : "Nothing matches.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: TerminalTabMetrics.rowGap) {
                    ForEach(rows) { package in row(package) }
                }
            }
        }
    }

    /// A package: its name, what it is (formula or cask, pinned, updates itself), its
    /// version and the newer one, and Upgrade when it's outdated.
    private func row(_ package: HomebrewPackage) -> some View {
        TerminalRow(package.title, subtitle: detail(package)) {
            versions(package)
            if package.outdated {
                Button(package.pinned ? "Pinned" : "Upgrade") { store.run(.upgrade(package)) }
                    .buttonStyle(TerminalButtonStyle())
                    .disabled(busy || package.pinned)
                    .help(package.pinned ? "Pinned with brew pin; unpin it to upgrade." : "Runs brew upgrade \(package.name)")
            }
        }
        .help(package.name)
    }

    private func detail(_ package: HomebrewPackage) -> String {
        var parts = [package.kind == .cask ? "cask" : "formula"]
        if package.pinned { parts.append("pinned") }
        if package.autoUpdates { parts.append("updates itself") }
        return parts.joined(separator: " · ")
    }

    private func versions(_ package: HomebrewPackage) -> some View {
        HStack(spacing: 4) {
            Text(package.installed).foregroundStyle(.secondary)
            if package.outdated {
                Text("→").foregroundStyle(.secondary)
                Text(package.latest).foregroundStyle(Color.green)
            }
        }
        .font(.system(size: 10.5, design: .monospaced))
        .lineLimit(1)
    }

    // MARK: Running

    private func jobStrip(_ job: HomebrewStore.Job) -> some View {
        HStack(spacing: 8) {
            if job.running {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
            } else {
                Image(systemName: job.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(job.succeeded ? Color.green : Color.orange)
                    .font(.system(size: 12))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(status(job)).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                if let line = HomebrewCatalog.lastLine(job.log) {
                    Text(line).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if !job.running, job.needsPassword, let brew = HomebrewStore.brew,
               let line = HomebrewCatalog.shellLine(job.command, brew: brew) {
                Button("Run in Shell") { runInShell(line) }
                    .buttonStyle(TerminalButtonStyle(prominent: true))
                    .help("Types \(line) into the Shell tab, where it can ask for your password.")
            }
            Button(showsOutput ? "Hide Output" : "Show Output") { showsOutput.toggle() }
                .buttonStyle(TerminalButtonStyle())
            if job.running {
                Button("Stop") { store.stop() }.buttonStyle(TerminalButtonStyle())
            } else {
                Button { store.dismissJob(); showsOutput = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(TerminalButtonStyle())
                    .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: TerminalTabMetrics.rowHeight)
        .background(TerminalTabMetrics.fill, in: RoundedRectangle(cornerRadius: TerminalTabMetrics.rowRadius, style: .continuous))
    }

    private func status(_ job: HomebrewStore.Job) -> String {
        if job.running { return job.command.title }
        if job.succeeded { return job.command == .update ? "Lists updated" : "Upgraded" }
        if job.needsPassword { return "It needs your password" }
        return job.exitCode == 15 ? "Stopped" : "Didn't finish (\(job.exitCode ?? -1))"
    }

    private func output(_ job: HomebrewStore.Job) -> some View {
        ScrollView {
            Text(job.log.isEmpty ? "No output yet." : job.log)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(theme.nookForeground.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(8)
        }
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: TerminalTabMetrics.cardRadius, style: .continuous))
    }

    // MARK: Empty states

    private func message(_ title: String, _ detail: String, link: Bool = false, retry: Bool = false, spinner: Bool = false) -> some View {
        Group {
            if spinner {
                VStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyTabMessage(systemImage: link ? "mug" : "exclamationmark.triangle", title: title, detail: detail) {
                    HStack(spacing: 6) {
                        if link, let url = URL(string: "https://brew.sh") {
                            Button { NSWorkspace.shared.open(url) } label: { Label("Open brew.sh", systemImage: "arrow.up.right") }
                                .buttonStyle(TerminalButtonStyle(prominent: true))
                                .help("Homebrew's install steps, in your browser")
                            Button { store.load(force: true) } label: { Label("Check Again", systemImage: "arrow.clockwise") }
                                .buttonStyle(TerminalButtonStyle())
                                .help("Looks for brew in /opt/homebrew/bin and /usr/local/bin")
                        }
                        if retry {
                            Button("Try Again") { store.load(force: true) }.buttonStyle(TerminalButtonStyle())
                        }
                    }
                }
            }
        }
    }
}
