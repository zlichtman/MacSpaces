import SwiftUI

/// Local dev servers: port, project and command, with Open and Stop.
/// On the Terminal page (`page`) it has the page's shared header and rows, and `empty`
/// replaces the small caption once a scan finds nothing.
struct DevServersWidget: View {
    var page = false
    var empty: AnyView?
    @StateObject private var scanner = DevServers()
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        Group {
            if page {
                // The Terminal page's Servers tab: the shared header, then a row per server.
                VStack(alignment: .leading, spacing: TerminalTabMetrics.gap) {
                    TerminalTabHeader("Servers", details: details)
                    if scanner.servers.isEmpty {
                        if scanner.scanned, let empty {
                            empty
                        } else {
                            WidgetEmptyState(systemImage: "server.rack",
                                             caption: scanner.scanned ? "No dev servers running" : "Looking for dev servers…", captionSize: 10)
                        }
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: TerminalTabMetrics.rowGap) {
                                ForEach(scanner.servers) { server in pageRow(server) }
                            }
                        }
                    }
                }
            } else if scanner.servers.isEmpty {
                WidgetEmptyState(systemImage: "server.rack",
                                 caption: scanner.scanned ? "No dev servers running" : "Looking for dev servers…", captionSize: 10)
            } else {
                list
            }
        }
        .padding(page ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: page ? .top : .center)
        .overlay(alignment: .bottom) {
            if let error = scanner.errorText { Text(error).font(.caption).foregroundStyle(.orange).padding(6).background(.regularMaterial) }
        }
        .onAppear { scanner.start() }
        .onDisappear { scanner.stop() }
    }

    private var details: [String] {
        guard scanner.scanned else { return ["Looking for dev servers"] }
        let count = scanner.servers.count
        guard count > 0 else { return ["Nothing listening"] }
        return ["\(count) listening on localhost", "\(count) listening"]
    }

    private var list: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 4) {
                ForEach(scanner.servers) { server in row(server) }
            }
        }
    }

    /// The page's row: the project and its command, the port, Open and Stop.
    private func pageRow(_ server: DevServers.Server) -> some View {
        TerminalRow(server.project, subtitle: server.command) {
            Text(verbatim: ":\(server.port)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.notch.accent)
            Button { scanner.open(server) } label: { Image(systemName: "arrow.up.right.square") }
                .buttonStyle(TerminalButtonStyle()).help("Open localhost:\(server.port)")
                .accessibilityLabel("Open")
            Button { scanner.stop(server) } label: { Image(systemName: "stop.fill") }
                .buttonStyle(TerminalButtonStyle()).help("Stop \(server.command) (like Ctrl-C)")
                .accessibilityLabel("Stop")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(server.project) on port \(server.port)")
    }

    private func row(_ server: DevServers.Server) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: ":\(server.port)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.notch.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(server.project).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text(server.command).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { scanner.open(server) } label: { Image(systemName: "arrow.up.right.square") }
                .buttonStyle(WidgetChipStyle(height: 22)).help("Open localhost:\(server.port)")
            Button { scanner.stop(server) } label: { Image(systemName: "stop.fill") }
                .buttonStyle(WidgetChipStyle(height: 22)).help("Stop \(server.command) (like Ctrl-C)")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(server.project) on port \(server.port)")
    }
}

/// Type a sum, a unit or a currency conversion; the answer appears as you type.
/// Click the answer to copy it.
struct CalculatorWidget: View {
    var onEditingChanged: (Bool) -> Void = { _ in }
    /// QA captures start with something typed.
    var initialInput = ""
    @ObservedObject private var theme = ThemeStore.shared
    @State private var input = ""
    @State private var answer = ""
    @State private var detail = ""
    @State private var copied = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("12*7, 5 km in mi, 20 usd to eur", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .rounded))
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .focused($focused)
            Spacer(minLength: 0)
            Button {
                guard !answer.isEmpty else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(answer.replacingOccurrences(of: ",", with: ""), forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(answer.isEmpty ? "=" : answer)
                        .font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(answer.isEmpty ? Color.secondary : theme.notch.accent)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(copied ? "Copied" : detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy the answer")
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: focused) { value in onEditingChanged(value) }
        .onDisappear { onEditingChanged(false) }
        .onAppear { if input.isEmpty { input = initialInput } }
        .task(id: input) { await solve() }
    }

    private func solve() async {
        detail = ""
        switch Calculator.evaluate(input) {
        case nil:
            answer = ""
        case .number(let value):
            answer = Calculator.format(value)
        case .measurement(let value, let unit):
            answer = "\(Calculator.format(value)) \(unit)"
        case .currency(let amount, let from, let to):
            // Wait for typing to settle before asking for the day's rate.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                let expression = input
                let rate = try await CurrencyRates.shared.rate(from: from, to: to)
                guard !Task.isCancelled, input == expression else { return }
                answer = "\(Calculator.format(amount * rate)) \(to)"
                detail = "1 \(from) = \(Calculator.format(rate)) \(to) · European Central Bank"
            } catch {
                guard !Task.isCancelled else { return }
                answer = ""
                detail = "Exchange rates unavailable"
            }
        }
    }
}
