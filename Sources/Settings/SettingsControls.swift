import SwiftUI

/// The Settings window's own controls, so every page looks like one app: one search field,
/// one button family, one chip and segmented look and one text field, all in the theme's
/// Settings colours (`ThemeStore.settings`). Toggles, menus, sliders and colour wells stay
/// native; buttons, fields, chips and segmented choices use these.
enum SettingsMetrics {
    /// Buttons, chips, segments and text fields.
    static let controlHeight: CGFloat = 28
    static let controlRadius: CGFloat = 8
    /// The search field, the same in the sidebar and in a card.
    static let searchHeight: CGFloat = 34
}

extension ThemeStore {
    /// Black or white, whichever reads better on the Settings accent (the primary button's text).
    var settingsOnAccent: Color {
        let accent = CustomThemeColors.clean(family.palette(settingsScheme).accent) ?? "FFFFFF"
        return CustomThemeColors.contrast(accent, "000000") >= CustomThemeColors.contrast(accent, "FFFFFF")
            ? Color.black.opacity(0.85) : .white
    }
}

// MARK: - Search

/// Settings' search field: a magnifying glass, the field and a clear button in a soft
/// capsule that brightens while focused. The sidebar's search passes its own field (for
/// its keys and focus); lists inside cards use `SettingsListSearchField`.
struct SettingsSearchField<Field: View>: View {
    @Binding var text: String
    let focused: Bool
    let onClear: (() -> Void)?
    let field: Field

    init(text: Binding<String>, focused: Bool, onClear: (() -> Void)? = nil, @ViewBuilder field: () -> Field) {
        self._text = text
        self.focused = focused
        self.onClear = onClear
        self.field = field()
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            field
                .textFieldStyle(.plain)
                .tint(Color.primary)
            if !text.isEmpty {
                Button { text = ""; onClear?() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12).frame(height: SettingsMetrics.searchHeight)
        .background(Color.primary.opacity(focused ? 0.09 : 0.06), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.primary.opacity(focused ? 0.18 : 0), lineWidth: 1) }
    }
}

/// The search field for a list inside a card ("Search widgets", "Search terminal themes").
struct SettingsListSearchField: View {
    let prompt: String
    @Binding var text: String
    @FocusState private var focused: Bool

    init(_ prompt: String, text: Binding<String>) {
        self.prompt = prompt
        self._text = text
    }

    var body: some View {
        SettingsSearchField(text: $text, focused: focused) {
            TextField(prompt, text: $text)
                .focused($focused)
                .accessibilityLabel(prompt)
        }
    }
}

// MARK: - Buttons

/// Every Settings button: `.primary` (the accent, one per card at most) for the main action,
/// `.secondary` (a faint fill) for the rest, `.quiet` (accent text, no fill) for small
/// in-line actions such as Reset and Refresh, and `.destructive` (red) for removing or
/// resetting things. One height and corner; dimmed while disabled.
struct SettingsButtonStyle: ButtonStyle {
    enum Role { case primary, secondary, quiet, destructive }
    var role: Role = .secondary

    func makeBody(configuration: Configuration) -> some View {
        SettingsButtonBody(configuration: configuration, role: role)
    }
}

extension ButtonStyle where Self == SettingsButtonStyle {
    static func settings(_ role: SettingsButtonStyle.Role = .secondary) -> SettingsButtonStyle {
        SettingsButtonStyle(role: role)
    }
}

private struct SettingsButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let role: SettingsButtonStyle.Role
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SettingsMetrics.controlRadius, style: .continuous)
    }
    private var level: Int { !isEnabled ? 0 : configuration.isPressed ? 2 : hovered ? 1 : 0 }
    private static let red = Color(nsColor: .systemRed)

    private var ink: Color {
        switch role {
        case .primary: return theme.settingsOnAccent
        case .secondary: return theme.settingsForeground
        case .quiet: return theme.settings.accent
        case .destructive: return Self.red
        }
    }

    @ViewBuilder private var fill: some View {
        switch role {
        case .primary: shape.fill(theme.settings.accent).brightness([0, 0.05, -0.07][level])
        case .secondary: shape.fill(Color.primary.opacity([0.07, 0.10, 0.14][level]))
        case .quiet: shape.fill(Color.primary.opacity([0, 0.06, 0.10][level]))
        case .destructive: shape.fill(Self.red.opacity([0.10, 0.16, 0.22][level]))
        }
    }

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: role == .primary ? .semibold : .medium))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(ink)
            .padding(.horizontal, role == .quiet ? 8 : 12)
            .frame(minWidth: SettingsMetrics.controlHeight, minHeight: SettingsMetrics.controlHeight)
            .background { fill }
            .overlay { shape.strokeBorder(Color.primary.opacity(role == .secondary ? 0.08 : 0), lineWidth: 1) }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovered = $0 }
    }
}

/// The minus button that takes one item out of a Settings list (an app, a folder, a pattern).
struct SettingsRemoveButton: View {
    var label = "Remove"
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(hovered ? AnyShapeStyle(Color(nsColor: .systemRed)) : AnyShapeStyle(.secondary))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Chips and segmented choices

/// The fill and edge of a chip or a segment: the theme's selection tint with an accent edge
/// when chosen, a faint fill otherwise, a little brighter on hover.
struct SettingsChipBackground: View {
    let selected: Bool
    var hovered = false
    var radius = SettingsMetrics.controlRadius
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape.fill(selected ? AnyShapeStyle(theme.settings.selected) : AnyShapeStyle(Color.primary.opacity(hovered ? 0.08 : 0.05)))
            .overlay { shape.strokeBorder(selected ? theme.settings.accent.opacity(0.8) : .clear, lineWidth: 1) }
    }
}

/// A chip: one of a set of choices (a Home profile, a Custom style). The label sets its own
/// padding and size; the style draws the chip around it.
struct SettingsChipStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SettingsChipBody(configuration: configuration, selected: selected)
    }
}

private struct SettingsChipBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        configuration.label
            .background { SettingsChipBackground(selected: selected, hovered: hovered && isEnabled) }
            .contentShape(RoundedRectangle(cornerRadius: SettingsMetrics.controlRadius, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .onHover { hovered = $0 }
    }
}

/// A row of two to four exclusive choices, drawn as chips in one track; the label sits on
/// the left like a native picker's.
struct SettingsSegmentedPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let optionTitle: (Value) -> String
    @ObservedObject private var theme = ThemeStore.shared

    init(_ title: String, selection: Binding<Value>, options: [Value], title optionTitle: @escaping (Value) -> String) {
        self.title = title
        self._selection = selection
        self.options = options
        self.optionTitle = optionTitle
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
            HStack(spacing: 2) {
                ForEach(options, id: \.self) { option in
                    let on = option == selection
                    Button { selection = option } label: {
                        Text(optionTitle(option))
                            .font(.system(size: 12, weight: on ? .semibold : .medium))
                            .foregroundStyle(theme.settingsForeground.opacity(on ? 1 : 0.75))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity)
                            .frame(height: SettingsMetrics.controlHeight - 4)
                    }
                    .buttonStyle(SettingsSegmentStyle(selected: on))
                    .accessibilityLabel(optionTitle(option))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(2)
            .background(Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: SettingsMetrics.controlRadius + 1, style: .continuous))
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
            Spacer(minLength: 0)
        }
    }
}

/// A segment inside `SettingsSegmentedPicker`: the chip look, clear when not chosen.
private struct SettingsSegmentStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SettingsSegmentBody(configuration: configuration, selected: selected)
    }
}

private struct SettingsSegmentBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SettingsMetrics.controlRadius - 1, style: .continuous)
        configuration.label
            .background {
                if selected {
                    SettingsChipBackground(selected: true, radius: SettingsMetrics.controlRadius - 1)
                } else {
                    shape.fill(Color.primary.opacity(hovered ? 0.06 : 0))
                }
            }
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .onHover { hovered = $0 }
    }
}

// MARK: - Text fields

extension View {
    /// A Settings text field: plain text on a faint rounded fill with a hairline edge, the
    /// height of a button so it lines up with the Add beside it.
    func settingsTextField() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: SettingsMetrics.controlHeight)
            .background(Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: SettingsMetrics.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SettingsMetrics.controlRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            }
    }
}
