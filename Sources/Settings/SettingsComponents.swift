import SwiftUI

struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    let scrollAnchor: String?
    @ViewBuilder let content: Content
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var navigation = SettingsNavigationModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(title: String, subtitle: String, scrollAnchor: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.scrollAnchor = scrollAnchor
        self.content = content()
    }

    var body: some View {
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
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
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
    @ViewBuilder let content: Content
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var navigation = SettingsNavigationModel.shared

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
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.settings.accent.opacity(navigation.searchTarget == title ? 0.65 : 0), lineWidth: 1.5) }
        .id("settings." + title)
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
        SettingsCard(title, systemImage: systemImage, isOpen: $isOpen) { content }
            .onAppear(perform: openIfSearched)
            .onChange(of: navigation.searchTarget) { _ in openIfSearched() }
    }

    private func openIfSearched() {
        if navigation.searchTarget == title { isOpen = true }
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
