import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings → Notch → Home: profiles, a to-scale preview of Home, the selected
/// widget controls and the visual widget gallery.
struct NookSettingsPane: View {
    @ObservedObject private var settings = NookSettings.shared
    @State private var selected: NookWidgetKind?

    var body: some View {
        SettingsPage(title: "Home", subtitle: "") {
            ProfileBar(settings: settings).id("settings.Profiles")

            VStack(alignment: .leading, spacing: 10) {
                HomeLayoutPreview(settings: settings, selected: $selected).id("settings.Layout")
                HStack {
                    Text(settings.widgets.isEmpty ? "Drag a widget here to start." : "Drag to arrange.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }

            WidgetGallery(settings: settings) { selected = $0 }.id("settings.Widgets")
        }
        .background {
            HomeLayoutKeyboardSelection(selected: $selected) { kind in
                settings.setEnabled(false, for: kind)
            }
            .frame(width: 0, height: 0)
        }
        .onChange(of: settings.activeProfileID) { _ in selected = nil }
    }
}

/// Selecting a preview hands keyboard focus to this view. Text fields take it
/// back normally, so Delete in either search field continues to edit text.
private struct HomeLayoutKeyboardSelection: NSViewRepresentable {
    @Binding var selected: NookWidgetKind?
    let remove: (NookWidgetKind) -> Void

    func makeNSView(context: Context) -> HomeLayoutKeyView {
        let view = HomeLayoutKeyView()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: HomeLayoutKeyView, context: Context) {
        view.removeSelected = { kind in
            remove(kind)
            selected = nil
        }
        view.deselect = { selected = nil }
        view.select(selected)
    }
}

final class HomeLayoutKeyView: NSView {
    private(set) var selection: NookWidgetKind?
    var removeSelected: (NookWidgetKind) -> Void = { _ in }
    var deselect: () -> Void = {}

    override var acceptsFirstResponder: Bool { true }

    func select(_ kind: NookWidgetKind?) {
        guard selection != kind else { return }
        selection = kind
        if kind != nil { window?.makeFirstResponder(self) }
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.function, .capsLock, .numericPad])
        guard let kind = selection, flags.isEmpty else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 51, 117:
            selection = nil
            removeSelected(kind)
        case 53:
            selection = nil
            deselect()
        default:
            super.keyDown(with: event)
        }
    }
}

// MARK: - Profiles

private struct ProfileBar: View {
    @ObservedObject var settings: NookSettings
    @State private var renamingID: UUID?
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(settings.profiles) { profile in
                        if renamingID == profile.id {
                            TextField("Profile name", text: $draftName)
                                .settingsTextField()
                                .frame(width: 150)
                                .focused($nameFocused)
                                .onSubmit(commitRename)
                                .onExitCommand { renamingID = nil }
                        } else {
                            chip(profile)
                        }
                    }
                    Menu {
                        Button("New Empty Profile") {
                            settings.addProfile(named: uniqueName("Profile"))
                        }
                        Button("Duplicate \(settings.activeProfile.name)") {
                            settings.addProfile(named: uniqueName(settings.activeProfile.name + " Copy"), copyingCurrent: true)
                        }
                    } label: {
                        Image(systemName: "plus").frame(width: 28, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .background { SettingsChipBackground(selected: false) }
                    .help("New profile")
                }
                .padding(.vertical, 2)
            }

        }
    }

    private func chip(_ profile: NookProfile) -> some View {
        let active = profile.id == settings.activeProfileID
        let count = profile.widgets.count
        return Button { settings.activeProfileID = profile.id } label: {
            HStack(spacing: 6) {
                Image(systemName: settings.symbol(for: profile)).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(active ? ThemeStore.shared.settings.accent : .secondary)
                Text(profile.name).font(.system(size: 12, weight: active ? .semibold : .medium)).lineLimit(1)
                Text("\(count)").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.primary.opacity(0.10), in: Capsule())
            }
            .padding(.horizontal, 12).frame(height: SettingsMetrics.controlHeight)
        }
        .buttonStyle(SettingsChipStyle(selected: active))
        .contextMenu {
            Button("Rename") { beginRename(profile) }
            Menu("Icon") {
                ForEach(NookProfile.symbols, id: \.self) { symbol in
                    Button { settings.setSymbol(symbol, for: profile) } label: {
                        Label(symbol == settings.symbol(for: profile) ? "Current" : " ", systemImage: symbol)
                    }
                }
            }
            Button("Duplicate") {
                settings.activeProfileID = profile.id
                settings.addProfile(named: uniqueName(profile.name + " Copy"), copyingCurrent: true)
            }
            Divider()
            Button("Delete", role: .destructive) { settings.removeProfile(profile) }
                .disabled(settings.profiles.count == 1)
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { beginRename(profile) })
        .help(active ? "Active profile. Double-click to rename." : "Switch to \(profile.name)")
    }

    private func beginRename(_ profile: NookProfile) {
        draftName = profile.name
        renamingID = profile.id
        DispatchQueue.main.async { nameFocused = true }
    }

    private func commitRename() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = renamingID, !name.isEmpty, let profile = settings.profiles.first(where: { $0.id == id }) {
            settings.renameProfile(profile, to: name)
        }
        renamingID = nil
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(settings.profiles.map(\.name))
        guard names.contains(base) else { return base }
        var index = 2
        while names.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }
}

// MARK: - Preview

/// A miniature of Home drawn from the same layout rules as the Nook, so
/// stacks and widths match what opens from the notch.
private struct HomeLayoutPreview: View {
    @ObservedObject var settings: NookSettings
    @Binding var selected: NookWidgetKind?
    @ObservedObject private var theme = ThemeStore.shared
    @State private var dragged: NookWidgetKind?
    @State private var libraryTargeted = false

    private let spacing: CGFloat = 10
    private let tileHeight: CGFloat = 218

    var body: some View {
        let tiles = settings.widgets
        let columns = tiles.nookLayoutItems(sizes: settings.widgetSizes)
        let natural = max(NotchViewModel.standardPageWidth - 40,
            columns.reduce(CGFloat.zero) { $0 + $1.width } + CGFloat(max(0, columns.count - 1)) * spacing)
        let widths = tiles.fittedNookWidths(availableWidth: natural, spacing: spacing, sizes: settings.widgetSizes)

        GeometryReader { proxy in
            let available = proxy.size.width - 28
            let scale = natural > 0 ? min(1, available / natural) : 1
            VStack(spacing: 8 * scale) {
                if columns.isEmpty {
                    Text("No widgets")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(alignment: .top, spacing: spacing * scale) {
                        ForEach(columns) { column in
                            VStack(spacing: spacing * scale) {
                                ForEach(column.kinds) { kind in
                                    tile(kind, width: (widths[kind] ?? column.width) * scale,
                                         height: (column.isStack ? (tileHeight - spacing) / 2 : tileHeight) * scale,
                                         scale: scale, compact: column.isStack)
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(theme.notch.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, theme.notch.colorScheme)
            .foregroundStyle(theme.nookForeground)
            .onDrop(of: [.nookWidget], isTargeted: $libraryTargeted) { providers in
                NookWidgetTransfer.receive(providers, into: settings) { selected = $0 }
            }
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(theme.notch.accent.opacity(libraryTargeted ? 0.85 : 0), lineWidth: 2))
            .animation(Design.spring(), value: settings.widgets)
            .animation(Design.spring(), value: settings.widgetSizes)
        }
        .frame(height: 246)
    }

    private func tile(_ kind: NookWidgetKind, width: CGFloat, height: CGFloat, scale: CGFloat, compact: Bool) -> some View {
        let isSelected = selected == kind
        return Button { selected = isSelected ? nil : kind } label: {
            WidgetVisualPreview(kind: kind, compact: compact)
                .frame(width: width, height: height)
            .overlay {
                RoundedRectangle(cornerRadius: 12 * max(scale, 0.6), style: .continuous)
                    .strokeBorder(isSelected ? theme.notch.accent.opacity(0.65) : .clear, lineWidth: 1)
            }
            .opacity(dragged == kind ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button("Remove from Home", role: .destructive) {
                settings.setEnabled(false, for: kind)
                if selected == kind { selected = nil }
            }
        }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Button {
                    settings.setEnabled(false, for: kind)
                    selected = nil
                } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 15))
                        .foregroundStyle(theme.nookForeground.opacity(0.7))
                        .padding(5).background(theme.notch.tile, in: Circle())
                }
                .buttonStyle(.plain).padding(3).help("Remove from Home")
                .accessibilityLabel("Remove \(kind.title) from Home")
            }
        }
        .accessibilityAction(named: "Move left") { settings.moveWidget(kind, offset: -1) }
        .accessibilityAction(named: "Move right") { settings.moveWidget(kind, offset: 1) }
        .onDrag {
            dragged = kind
            settings.beginInteractiveReorder()
            WidgetDragSession.shared.begin {
                dragged = nil
                settings.endInteractiveReorder()
            }
            return NSItemProvider(object: kind.rawValue as NSString)
        }
        .onDrop(of: [UTType.text, .nookWidget], delegate: PreviewDropDelegate(target: kind, dragged: $dragged, settings: settings))
    }
}

private struct PreviewDropDelegate: DropDelegate {
    let target: NookWidgetKind
    @Binding var dragged: NookWidgetKind?
    let settings: NookSettings

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target else { return }
        withAnimation(Design.spring()) { settings.moveWidget(dragged, to: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: info.hasItemsConforming(to: [.nookWidget]) ? .copy : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        if info.hasItemsConforming(to: [.nookWidget]) {
            return NookWidgetTransfer.receive(info.itemProviders(for: [.nookWidget]), into: settings, before: target)
        }
        dragged = nil
        WidgetDragSession.shared.finish()
        return true
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Dock

/// Which app pages sit in the dock under the Nook, and in what order.
struct DockAppsCard: View {
    @ObservedObject var settings: NookSettings
    @ObservedObject private var theme = ThemeStore.shared
    /// The page being dragged by its handle, where it started and how far it has gone.
    @State private var dragging: NotchTab?
    @State private var dragStart = 0
    @State private var dragTranslation: CGFloat = 0
    private let rowHeight: CGFloat = 38
    private let rowSpacing: CGFloat = 4

    var body: some View {
        SettingsCard("Dock", systemImage: "dock.rectangle") {
            Text("Choose the app pages under the Nook. Home and Settings are always there.")
                .font(.caption).foregroundStyle(.secondary)
            let shown = settings.dockApps
            let hidden = NotchTab.appPages.filter { !settings.dockApps.contains($0) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            VStack(spacing: rowSpacing) {
                ForEach(shown) { page in
                    row(page, shown: true)
                        .offset(y: dragOffset(for: page))
                        .zIndex(dragging == page ? 1 : 0)
                        .background {
                            if dragging == page {
                                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.07))
                                    .offset(y: dragOffset(for: page)).padding(.horizontal, -6)
                            }
                        }
                }
            }
            if !hidden.isEmpty {
                Text("More pages").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
                VStack(spacing: rowSpacing) {
                    ForEach(hidden) { page in row(page, shown: false) }
                }
            }
            Divider().padding(.top, 4)
            // The buttons that sit beside Settings at the dock's end.
            Text("Next to Settings").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Toggle("Show Pin button", isOn: $settings.showDockPin)
            Toggle("Show Close button", isOn: $settings.showDockClose)
        }
    }

    private func row(_ page: NotchTab, shown: Bool) -> some View {
        HStack(spacing: 12) {
            Group {
                if page == .wisp { WispGlyph(size: 14) } else { Image(systemName: page.systemImage) }
            }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(shown ? theme.settings.accent : .secondary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title).font(.system(size: 13, weight: .medium))
                Text(page.summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { shown }, set: { value in
                withAnimation { settings.setDockApp(page, shown: value) }
            }))
            .toggleStyle(.switch).labelsHidden().controlSize(.small)
            .accessibilityLabel("Show \(page.title) in the dock")
            if shown {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(dragging == page ? AnyShapeStyle(theme.settings.accent) : AnyShapeStyle(.secondary))
                    .frame(width: 24, height: rowHeight)
                    .contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.openHand.push() } else { NSCursor.pop() } }
                    .gesture(reorderGesture(page))
                    .help("Drag to reorder")
                    .accessibilityLabel("Reorder \(page.title)")
                    .accessibilityAction(named: "Move earlier") { settings.moveDockApp(page, offset: -1) }
                    .accessibilityAction(named: "Move later") { settings.moveDockApp(page, offset: 1) }
            } else {
                // Keeps the switches lined up with the rows above.
                Color.clear.frame(width: 24, height: 1)
            }
        }
        .frame(height: rowHeight)
    }

    /// Dragging the handle moves the row with the pointer; the others make room
    /// as it passes the halfway point of each neighbour.
    private func reorderGesture(_ page: NotchTab) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragging != page {
                    dragging = page
                    dragStart = settings.dockApps.firstIndex(of: page) ?? 0
                    NSCursor.closedHand.push()
                }
                dragTranslation = value.translation.height
                let target = dragStart + Int((dragTranslation / (rowHeight + rowSpacing)).rounded())
                if target != settings.dockApps.firstIndex(of: page) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { settings.moveDockApp(page, to: target) }
                }
            }
            .onEnded { _ in
                NSCursor.pop()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    dragging = nil
                    dragTranslation = 0
                }
            }
    }

    /// The dragged row follows the pointer from wherever its slot now is.
    private func dragOffset(for page: NotchTab) -> CGFloat {
        guard dragging == page, let index = settings.dockApps.firstIndex(of: page) else { return 0 }
        return dragTranslation - CGFloat(index - dragStart) * (rowHeight + rowSpacing)
    }
}
