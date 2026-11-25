import SwiftUI

struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    let scrollAnchor: String?
    /// The page's content may grow to the window's height (Appearance's theme list): the page
    /// passes down how tall its window is (`settingsViewport`) and measures in `coordinateSpace`.
    let fillsHeight: Bool
    @ViewBuilder let content: Content
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var navigation = SettingsNavigationModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where a page that fills the window measures from: the top of its scrolled content.
    static var coordinateSpace: String { "settingsPage" }
    /// The page's margin all round, which also ends a page that fills the window.
    static var margin: CGFloat { 28 }

    init(title: String, subtitle: String, scrollAnchor: String? = nil, fillsHeight: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.scrollAnchor = scrollAnchor
        self.fillsHeight = fillsHeight
        self.content = content()
    }

    var body: some View {
        if fillsHeight {
            GeometryReader { window in
                page.environment(\.settingsViewport, window.size.height)
            }
        } else {
            page
        }
    }

    private var page: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 26, weight: .bold))
                        if !subtitle.isEmpty {
                            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 2)

                    content
                }
                .padding(Self.margin)
                .frame(maxWidth: .infinity, alignment: .leading)
                .coordinateSpace(name: Self.coordinateSpace)
            }
            .background(theme.settings.surface)
            .foregroundStyle(theme.settingsForeground)
            .task(id: scrollAnchor ?? navigation.searchTarget) {
                guard let target = scrollAnchor ?? navigation.searchTarget.map({ "settings." + $0 }) else { return }
                await Task.yield()
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    proxy.scrollTo(target, anchor: scrollAnchor == nil ? .top : .center)
                }
            }
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    /// Drawn instead of the symbol, as a template (Tape's own mark).
    var mark: NSImage?
    /// Given, the header opens and closes the card (`SettingsDrawerCard`).
    let isOpen: Binding<Bool>?
    /// The name search lands on when the title changes (the chat card is named for the agent).
    var anchor: String?
    @ViewBuilder let content: Content
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var navigation = SettingsNavigationModel.shared

    init(_ title: String, systemImage: String, anchor: String, @ViewBuilder content: () -> Content) {
        self.init(title, systemImage: systemImage, content: content)
        self.anchor = anchor
    }

    init(_ title: String, systemImage: String, isOpen: Binding<Bool>? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.isOpen = isOpen
        self.content = content()
    }

    init(_ title: String, mark: NSImage, @ViewBuilder content: () -> Content) {
        self.init(title, systemImage: "", content: content)
        self.mark = mark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let isOpen {
                Button { isOpen.wrappedValue.toggle() } label: {
                    HStack {
                        header
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isOpen.wrappedValue ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(isOpen.wrappedValue ? "Open" : "Closed")
                if isOpen.wrappedValue { content }
            } else {
                header
                content
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.settings.tile,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.settings.border, lineWidth: 1)
        }
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.settings.accent.opacity(navigation.searchTarget == (anchor ?? title) ? 0.65 : 0), lineWidth: 1.5) }
        .id("settings." + (anchor ?? title))
    }

    @ViewBuilder private var label: some View {
        if let mark {
            Label { Text(title) } icon: { Image(nsImage: mark).renderingMode(.template) }
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    private var header: some View {
        label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

/// A card that stays closed until its header is clicked, or a search lands on it, and remembers.
struct SettingsDrawerCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content
    @AppStorage private var isOpen: Bool
    @ObservedObject private var navigation = SettingsNavigationModel.shared

    init(_ title: String, systemImage: String, openKey: String, startsOpen: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
        _isOpen = AppStorage(wrappedValue: startsOpen, openKey)
    }

    var body: some View {
        SettingsCard(title, systemImage: systemImage, isOpen: openBinding) { content }
            .onAppear(perform: openIfSearched)
            .onChange(of: navigation.searchTarget) { _ in openIfSearched() }
    }

    private var openBinding: Binding<Bool> {
        #if DEBUG
        if SettingsDrawerPreview.allOpen { return .constant(true) }
        #endif
        return $isOpen
    }

    private func openIfSearched() {
        if navigation.searchTarget == title { isOpen = true }
    }
}

#if DEBUG
/// Check renders draw every drawer open (`settings-pages`) without touching the saved state.
@MainActor enum SettingsDrawerPreview {
    static var allOpen = false
}
#endif

// MARK: - Inside a card

/// A part of a card under its own small heading, which is also where a search for it scrolls to
/// (`SettingsSearch.entries`), so one card can hold one idea's several parts.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeading(title)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsSectionHeading: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .id("settings." + title)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A card's one-line caption. The rest of what it would say goes in `help`, shown on hover.
struct SettingsCaption: View {
    let text: String
    var help: String = ""
    var colour: Color?

    init(_ text: String, help: String = "", colour: Color? = nil) {
        self.text = text
        self.help = help
        self.colour = colour
    }

    var body: some View {
        Text(text).font(.caption).foregroundStyle(colour.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
            .lineLimit(1).truncationMode(.tail)
            .help(help.isEmpty ? text : help)
    }
}

/// A long list or a rare part inside a card, folded away until its row is clicked (or a search
/// lands on it): the same chevron as a drawer card's header. Closed each time Settings opens,
/// unless it's given a saved `isOpen`.
struct SettingsDisclosure<Content: View>: View {
    let title: String
    var detail: String = ""
    @ViewBuilder let content: Content
    private let saved: Binding<Bool>?
    @State private var shown = false
    @ObservedObject private var navigation = SettingsNavigationModel.shared

    init(_ title: String, detail: String = "", isOpen: Binding<Bool>? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.saved = isOpen
        self.content = content()
    }

    private var open: Bool {
        get { saved?.wrappedValue ?? shown }
        nonmutating set { if let saved { saved.wrappedValue = newValue } else { shown = newValue } }
    }

    private var isOpen: Bool {
        #if DEBUG
        if SettingsDrawerPreview.allOpen { return true }
        #endif
        return open
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { open.toggle() } label: {
                HStack(spacing: 6) {
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .id("settings." + title)
            .accessibilityLabel(detail.isEmpty ? title : "\(title), \(detail)")
            .accessibilityValue(isOpen ? "Open" : "Closed")
            if isOpen { content }
        }
        .onAppear(perform: openIfSearched)
        .onChange(of: navigation.searchTarget) { _ in openIfSearched() }
    }

    private func openIfSearched() {
        if navigation.searchTarget == title { open = true }
    }
}

/// A card's live preview: what the Notch will show, on the Nook's own colour, the same height
/// and corners on every page. Every setting in its card changes it.
struct SettingsPreview<Content: View>: View {
    static var height: CGFloat { 200 }
    @ViewBuilder let content: Content
    @ObservedObject private var theme = ThemeStore.shared

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .background(theme.notch.surface)
            .foregroundStyle(theme.nookForeground)
            .environment(\.colorScheme, theme.notch.colorScheme)
            .tint(theme.notch.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.settings.border, lineWidth: 1))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct SettingsSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueText: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 124, alignment: .leading)
            Slider(value: $value, in: range)
                .frame(maxWidth: .infinity)
            Text(valueText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
        .frame(minWidth: 300)
    }
}

private struct SettingsViewportKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// The height of the Settings page's window area, for a page that fills it (`SettingsPage.fillsHeight`);
    /// nil elsewhere, such as captures drawing a card alone.
    var settingsViewport: CGFloat? {
        get { self[SettingsViewportKey.self] }
        set { self[SettingsViewportKey.self] = newValue }
    }
}
