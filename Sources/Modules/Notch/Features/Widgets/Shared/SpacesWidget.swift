import SwiftUI

/// One dot per desktop, the current one in the accent; eight to a row. With `jump`, each other
/// dot is a button: its whole cell, gaps included, takes the click.
struct SpaceDots: View {
    let count: Int
    /// From 1; nil while a full-screen space shows.
    let current: Int?
    let tint: Color
    var jump: ((Int) -> Void)?
    var hover: (Int?) -> Void = { _ in }
    @State private var hovered: Int?

    private static let side: CGFloat = 8
    private static let gap: CGFloat = 6
    private static var cell: CGFloat { side + gap }

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(Self.cell), spacing: 0), count: max(1, min(count, 8)))
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(1..<(count + 1), id: \.self) { number in
                if let jump, number != current {
                    Button { jump(number) } label: { dot(number) }
                        .buttonStyle(.plain)
                        .onHover { inside in
                            if inside { hovered = number } else if hovered == number { hovered = nil }
                            hover(hovered)
                        }
                        .accessibilityLabel("Go to Desktop \(number)")
                } else {
                    dot(number).accessibilityHidden(true)
                }
            }
        }
        .fixedSize()
        // The cells' outer gaps take clicks without adding to the layout.
        .padding(-Self.gap / 2)
        // The dot pointed at may have just become the current one, which reports no leaving.
        .onChange(of: current) { _ in
            hovered = nil
            hover(nil)
        }
    }

    private func dot(_ number: Int) -> some View {
        Circle()
            .fill(number == current ? tint : Color.primary.opacity(hovered == number ? 0.6 : 0.22))
            .frame(width: Self.side, height: Self.side)
            .frame(width: Self.cell, height: Self.cell)
            .contentShape(Rectangle())
    }
}

/// Says why a click couldn't change desktop, with the way to fix it.
struct SpaceJumpHelp: View {
    let problem: SpaceJumpProblem
    var done: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            Text(problem.message).font(.system(size: 12, weight: .medium)).lineLimit(1).fixedSize()
            Button(problem.button) {
                done()
                if let url = problem.settingsURL { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(WidgetChipStyle(prominent: true, height: 22))
        }
        .padding(12)
    }
}

/// Names every desktop on a display in one place: Tab moves down the list, Return or clicking
/// away saves, Escape cancels. It opens on the current desktop's row.
struct SpaceNamesEditor: View {
    let desktops: [SpaceDesktop]
    let current: String?
    @Binding var drafts: [String: String]
    var done: () -> Void = {}
    var cancel: () -> Void = {}
    @ObservedObject private var theme = ThemeStore.shared

    private static let rowHeight: CGFloat = 26
    private static let rowGap: CGFloat = 6
    private static let padding: CGFloat = 12
    private static let tallest: CGFloat = 280

    var body: some View {
        let height = CGFloat(desktops.count) * (Self.rowHeight + Self.rowGap) - Self.rowGap + Self.padding * 2
        ScrollView(showsIndicators: false) {
            VStack(spacing: Self.rowGap) {
                ForEach(desktops, id: \.uuid) { desktop in
                    HStack(spacing: 8) {
                        Text("\(desktop.number)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(desktop.uuid == current ? theme.notch.accent : Color.secondary)
                            .frame(width: 16, alignment: .trailing)
                        NookTextField("Desktop \(desktop.number)", text: binding(desktop.uuid), height: Self.rowHeight,
                                      focusOnAppear: desktop.uuid == (current ?? desktops.first?.uuid))
                    }
                }
            }
            .padding(Self.padding)
        }
        .frame(width: 210, height: min(height, Self.tallest))
        .onSubmit(done)
        .onExitCommand(perform: cancel)
    }

    private func binding(_ uuid: String) -> Binding<String> {
        Binding(get: { drafts[uuid] ?? "" },
                set: { drafts[uuid] = String($0.prefix(SpaceLayout.nameLimit)) })
    }
}

/// Spaces on Home: the desktops on this display and the current one's name. Clicking a dot goes
/// to that desktop, and pointing at one shows its name; clicking the name opens a list to name
/// them all.
struct SpacesWidget: View {
    @ObservedObject var monitor: SpacesMonitor
    var displayIdentifier: String?
    var compact = false
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var theme = ThemeStore.shared
    @State private var naming: [SpaceDesktop] = []
    @State private var drafts: [String: String] = [:]
    @State private var isNaming = false
    @State private var cancelled = false
    @State private var hovered: Int?
    @State private var problem: SpaceJumpProblem?

    var body: some View {
        let display = monitor.display(on: displayIdentifier)
        let current = display?.current
        VStack(spacing: compact ? 6 : 10) {
            SpaceDots(count: display?.desktops.count ?? 0, current: current?.number, tint: theme.notch.accent,
                      jump: { number in
                          guard let desktop = display?.desktops.first(where: { $0.number == number }) else { return }
                          monitor.jump(to: desktop, on: displayIdentifier) { problem = $0 }
                      },
                      hover: { hovered = $0 })
            .nookPopover(isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } }), arrowEdge: .top) {
                if let problem { SpaceJumpHelp(problem: problem) { self.problem = nil } }
            }
            nameButton(display: display, pointedAt: display?.desktops.first { $0.number == hovered })
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .nookPopover(isPresented: $isNaming, arrowEdge: .top) {
            SpaceNamesEditor(desktops: naming, current: display?.current?.uuid, drafts: $drafts,
                             done: { isNaming = false },
                             cancel: { cancelled = true; isNaming = false })
        }
        .onChange(of: isNaming) { open in
            onEditingChanged(open || problem != nil)
            guard !open else { return }
            if !cancelled { naming.forEach { monitor.setName(drafts[$0.uuid] ?? "", for: $0.uuid) } }
            naming = []
        }
        .onChange(of: problem) { onEditingChanged($0 != nil || isNaming) }
        .onAppear { monitor.refresh() }
        .onDisappear { onEditingChanged(false) }
    }

    @ViewBuilder
    private func nameButton(display: SpaceDisplay?, pointedAt: SpaceDesktop?) -> some View {
        let isFullScreen = display != nil && display?.current == nil
        let shown = pointedAt ?? display?.current
        let shownName = shown.flatMap { monitor.names[$0.uuid] }
        Button {
            guard let display else { return }
            naming = display.desktops
            drafts = monitor.names
            cancelled = false
            isNaming = true
        } label: {
            Text(shownName ?? shown.map { "Desktop \($0.number)" } ?? (isFullScreen ? "Full screen" : " "))
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .foregroundStyle(shownName == nil ? Color.secondary : Color.primary)
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(display == nil)
        .help(display == nil ? "" : "Name your desktops")
    }
}
