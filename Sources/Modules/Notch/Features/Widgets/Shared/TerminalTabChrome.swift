import SwiftUI

/// The pieces every Terminal tab is built from, so the tabs share one look: a header
/// (title, a quiet line, actions, an optional filter row), cards, list rows, buttons,
/// filter chips and a search field, all on one set of metrics.
enum TerminalTabMetrics {
    /// Between the header and the content, between cards, and between a card's parts.
    static let gap: CGFloat = 8
    /// Between list rows.
    static let rowGap: CGFloat = 4
    /// A rail tile's height, so the header and the first tile share a centre line.
    static let headerHeight: CGFloat = 30
    static let controlHeight: CGFloat = 22
    static let rowHeight: CGFloat = 36
    static let rowRadius: CGFloat = 9
    static let cardRadius: CGFloat = 12
    static let cardPadding = EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
    static let fill = Color.primary.opacity(0.05)
}

/// A tab's header: its title, one quiet line beside it and actions on the right, with an
/// optional row of filters beneath. `details` runs longest first; the first that fits
/// shows, so the line is shortened rather than cut mid-word.
struct TerminalTabHeader<Actions: View, Filters: View>: View {
    let title: String
    var details: [String] = []
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var filters: () -> Filters

    init(_ title: String, details: [String] = [],
         @ViewBuilder actions: @escaping () -> Actions,
         @ViewBuilder filters: @escaping () -> Filters) {
        self.title = title
        self.details = details.filter { !$0.isEmpty }
        self.actions = actions
        self.filters = filters
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TerminalTabMetrics.gap) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
                ViewThatFits(in: .horizontal) {
                    ForEach(details, id: \.self) { line in
                        Text(line).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    }
                    Color.clear.frame(width: 0, height: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) { actions() }.fixedSize().layoutPriority(1)
            }
            .frame(height: TerminalTabMetrics.headerHeight)
            filters()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension TerminalTabHeader where Filters == EmptyView {
    init(_ title: String, details: [String] = [], @ViewBuilder actions: @escaping () -> Actions) {
        self.init(title, details: details, actions: actions) { EmptyView() }
    }
}

extension TerminalTabHeader where Actions == EmptyView, Filters == EmptyView {
    init(_ title: String, details: [String] = []) {
        self.init(title, details: details, actions: { EmptyView() }) { EmptyView() }
    }
}

/// The filter row under a header: chips on the left, the search field on the right.
struct TerminalFilterRow<Chips: View>: View {
    @Binding var query: String
    var prompt = "Filter"
    @ViewBuilder var chips: () -> Chips

    var body: some View {
        HStack(spacing: 6) {
            chips()
            Spacer(minLength: 6)
            TerminalSearchField(text: $query, prompt: prompt)
        }
        .frame(height: TerminalTabMetrics.controlHeight)
    }
}

/// One filter: selected is a stronger fill; a count shows in orange.
struct TerminalFilterChip: View {
    let title: String
    var count = 0
    let selected: Bool
    let action: () -> Void
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if count > 0 { Text("\(count)").foregroundStyle(Color.orange).monospacedDigit() }
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(height: TerminalTabMetrics.controlHeight)
            .foregroundStyle(theme.nookForeground.opacity(selected ? 1 : 0.7))
            .background(Color.primary.opacity(selected ? 0.14 : 0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct TerminalSearchField: View {
    @Binding var text: String
    var prompt = "Filter"

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.system(size: 11))
        }
        .padding(.horizontal, 8)
        .frame(width: 150, height: TerminalTabMetrics.controlHeight)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

/// Every button on the Terminal page: the accent for the main action, a faint fill
/// otherwise, one height, dimmed while disabled.
struct TerminalButtonStyle: ButtonStyle {
    var prominent = false
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.isEnabled) private var isEnabled

    init(prominent: Bool = false) { self.prominent = prominent }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .foregroundStyle(prominent ? Color.black.opacity(0.82) : theme.nookForeground)
            .padding(.horizontal, 9)
            .frame(minWidth: TerminalTabMetrics.controlHeight, minHeight: TerminalTabMetrics.controlHeight)
            .background(prominent ? AnyShapeStyle(theme.notch.accent) : AnyShapeStyle(Color.primary.opacity(0.09)),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}

/// A titled card. `fill` stretches it to the height it's offered, content at the top,
/// so cards in a row line up and the tab ends at the page's bottom inset.
struct TerminalCard<Content: View>: View {
    let title: String
    var fill = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.3).foregroundStyle(.secondary)
            content()
        }
        .padding(TerminalTabMetrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: fill ? .infinity : nil, alignment: .topLeading)
        .background(TerminalTabMetrics.fill, in: RoundedRectangle(cornerRadius: TerminalTabMetrics.cardRadius, style: .continuous))
    }
}

/// A list row (a package, a session, a server): an optional meaningful leading image,
/// the name with a short label beside it, a secondary line under it, and trailing
/// values or buttons. Every list on the page uses this height, padding and corner.
struct TerminalRow<Leading: View, Trailing: View>: View {
    let title: String
    var label: String?
    var subtitle: String?
    var monospacedTitle = false
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, label: String? = nil, subtitle: String? = nil, monospacedTitle: Bool = false,
         @ViewBuilder leading: @escaping () -> Leading, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.label = label
        self.subtitle = subtitle
        self.monospacedTitle = monospacedTitle
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 9) {
            leading()
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.system(size: monospacedTitle ? 11 : 12, weight: .semibold,
                                      design: monospacedTitle ? .monospaced : .default))
                        .lineLimit(1).truncationMode(.middle)
                    if let label, !label.isEmpty {
                        Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
            trailing()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: TerminalTabMetrics.rowHeight, maxHeight: TerminalTabMetrics.rowHeight)
        .background(TerminalTabMetrics.fill, in: RoundedRectangle(cornerRadius: TerminalTabMetrics.rowRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: TerminalTabMetrics.rowRadius, style: .continuous))
    }
}

extension TerminalRow where Leading == EmptyView {
    init(_ title: String, label: String? = nil, subtitle: String? = nil, monospacedTitle: Bool = false,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(title, label: label, subtitle: subtitle, monospacedTitle: monospacedTitle,
                  leading: { EmptyView() }, trailing: trailing)
    }
}
