import AppKit
import SwiftUI

/// The Terminal drawer's list: an AppKit table in its own scroll view, three themes to a
/// row, each row drawn in one pass and reused as it scrolls. It looks exactly like the
/// SwiftUI rows it replaced (`TerminalThemeLayout`): a 60 × 16 pt capsule in the theme's
/// background holding its accent and red, green, yellow, blue and magenta as six dots
/// (7 pt then 6 pt, 3 pt apart; a light background gets a faint edge), 8 pt, then the
/// name in 12 pt type; the theme in use on a soft accent tint with a small tick and a
/// semibold name. Scrolling never touches SwiftUI: the 830-theme `LazyVGrid` of buttons it
/// replaced relaid out and rebuilt rows on the main thread as they scrolled in.
struct TerminalThemeGrid: NSViewRepresentable {
    let items: [TerminalThemeItem]
    /// Our palettes' pills (`GhosttyLibrary.ownPills`); Ghostty's carry their own.
    let ownPills: [ThemeFamily: TerminalPillColours]
    /// The search and tone: a new one scrolls back to the top.
    let filter: String
    /// `TerminalThemeItem.id` of the theme in use.
    let selectedID: String
    let tint: NSColor
    /// The names' colour (Settings' foreground).
    let ink: NSColor
    /// Settings' scheme, for the light pills' edge (`Color.primary` at 16%).
    let dark: Bool

    /// The scroll view's identifier, so `theme-lag` can find it to scroll it.
    static let scrollIdentifier = NSUserInterfaceItemIdentifier("TerminalThemeGrid")

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let table = TerminalThemeTableView()
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.usesAlternatingRowBackgroundColors = false
        table.gridStyleMask = []
        table.selectionHighlightStyle = .none
        table.allowsEmptySelection = true
        table.allowsColumnReordering = false
        table.allowsColumnResizing = false
        table.focusRingType = .none
        table.intercellSpacing = .zero
        table.usesAutomaticRowHeights = false
        table.rowSizeStyle = .custom
        table.rowHeight = TerminalThemeLayout.pitch
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("themes"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.coordinator = context.coordinator
        table.setAccessibilityLabel("Terminal themes")

        let scroll = NSScrollView()
        scroll.identifier = Self.scrollIdentifier
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none
        scroll.documentView = table
        context.coordinator.table = table
        context.coordinator.apply(self)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.apply(self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var table: TerminalThemeTableView?
        private(set) var items: [TerminalThemeItem] = []
        private(set) var pills: [TerminalPillColours] = []
        private var ids: [String] = []
        private var ownPills: [ThemeFamily: TerminalPillColours] = [:]
        private var filter: String?
        private(set) var selectedID = ""
        private(set) var style = TerminalThemeLayout.Style(tint: .controlAccentColor, ink: .labelColor)

        func apply(_ grid: TerminalThemeGrid) {
            guard let table else { return }
            let appearance = NSAppearance(named: grid.dark ? .darkAqua : .aqua)
            if table.enclosingScrollView?.appearance?.name != appearance?.name {
                table.enclosingScrollView?.appearance = appearance
            }
            let ids = grid.items.map(\.id)
            let reload = ids != self.ids || grid.ownPills != ownPills
            let newStyle = TerminalThemeLayout.Style(tint: grid.tint, ink: grid.ink)
            let restyle = grid.selectedID != selectedID || newStyle != style
            selectedID = grid.selectedID
            style = newStyle
            // A new search or tone starts at the top, as a fresh list does. It scrolls before
            // the list shrinks, so it's never left scrolled past the new end, showing nothing.
            let refiltered = grid.filter != filter && filter != nil
            filter = grid.filter
            if refiltered, let scroll = table.enclosingScrollView {
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            if reload {
                items = grid.items
                self.ids = ids
                ownPills = grid.ownPills
                pills = items.map { item in
                    switch item {
                    case .own(let family): return grid.ownPills[family] ?? GhosttyLibrary.shared.pill(family)
                    case .ghostty(let theme): return theme.pill
                    }
                }
                table.reloadData()
                // Rows drawn before the reload are redrawn from the new list, not left as they were.
                table.enumerateAvailableRowViews { row, _ in row.needsDisplay = true }
            } else if restyle {
                table.enumerateAvailableRowViews { row, _ in row.needsDisplay = true }
            }
        }

        func choose(_ index: Int) {
            guard items.indices.contains(index) else { return }
            switch items[index] {
            case .own(let family): ThemeStore.shared.selectFamily(family)
            case .ghostty(let ghostty): ThemeStore.shared.selectGhostty(ghostty)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            (items.count + TerminalThemeLayout.columns - 1) / TerminalThemeLayout.columns
        }

        /// Everything is drawn by the row view; there are no cell views.
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? { nil }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let view = tableView.makeView(withIdentifier: TerminalThemeRowView.reuse, owner: nil) as? TerminalThemeRowView
                ?? TerminalThemeRowView()
            view.identifier = TerminalThemeRowView.reuse
            view.coordinator = self
            view.row = row
            view.needsDisplay = true
            return view
        }

        /// The first and last rows also carry the grid's padding above and below.
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            TerminalThemeLayout.height(row: row, of: numberOfRows(in: tableView))
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
        func selectionShouldChange(in tableView: NSTableView) -> Bool { false }
    }
}

/// The list's geometry: what the SwiftUI grid laid out (three flexible columns 8 pt apart,
/// 26 pt rows 2 pt apart, 2 pt of padding round the grid, each cell padded 6 pt).
@MainActor enum TerminalThemeLayout {
    static let columns = 3
    static let rowHeight: CGFloat = 26
    static let rowSpacing: CGFloat = 2
    static let columnSpacing: CGFloat = 8
    static let edge: CGFloat = 1
    static let inset: CGFloat = 2
    /// One table row: a cell row and the spacing, half above and half below.
    static let pitch = rowHeight + rowSpacing

    /// A table row's height: the pitch, plus the grid's padding for the first and last
    /// (each row carries half the spacing between rows above and below its cells).
    static func height(row: Int, of count: Int) -> CGFloat {
        pitch + (row == 0 ? edge : 0) + (row == count - 1 ? edge : 0)
    }

    /// The cells of one table row, in its flipped coordinates.
    static func cells(width: CGFloat, row: Int) -> [CGRect] {
        let cell = (width - 2 * inset - CGFloat(columns - 1) * columnSpacing) / CGFloat(columns)
        let top = rowSpacing / 2 + (row == 0 ? edge : 0)
        return (0..<columns).map { column in
            CGRect(x: inset + CGFloat(column) * (cell + columnSpacing), y: top, width: cell, height: rowHeight)
        }
    }

    struct Style: Equatable {
        let tint: NSColor
        let ink: NSColor
    }

    private static let highlightRadius: CGFloat = 6
    private static let padding: CGFloat = 6
    private static let pill = CGSize(width: 60, height: 16)
    private static let dotSizes: [CGFloat] = [7, 6, 6, 6, 6, 6]
    private static let dotSpacing: CGFloat = 3
    private static let regular = NSFont.systemFont(ofSize: 12, weight: .regular)
    private static let semibold = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private static var tick: (tint: NSColor, image: NSImage)?

    /// A colour as drawn now (catalogue colours resolve in the current appearance), with
    /// its opacity multiplied as SwiftUI's `opacity(_:)` does.
    private static func resolved(_ colour: NSColor, opacity: CGFloat = 1) -> CGColor {
        let rgb = colour.usingColorSpace(.sRGB) ?? colour
        return rgb.withAlphaComponent(rgb.alphaComponent * opacity).cgColor
    }

    private static func checkmark(_ tint: NSColor) -> NSImage? {
        if let tick, tick.tint == tint { return tick.image }
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
        guard let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        tick = (tint, image)
        return image
    }

    /// One theme: the tint and tick when it's in use, the pill, then the name.
    static func draw(title: String, pill colours: TerminalPillColours, selected: Bool, style: Style,
                     in rect: CGRect, context: CGContext) {
        if selected {
            context.setFillColor(resolved(style.tint, opacity: 0.14))
            context.addPath(CGPath(roundedRect: rect, cornerWidth: highlightRadius, cornerHeight: highlightRadius, transform: nil))
            context.fillPath()
        }
        let capsule = CGRect(x: rect.minX + padding, y: rect.midY - pill.height / 2, width: pill.width, height: pill.height)
        func fillCapsule(_ r: CGRect, _ colour: CGColor) {
            context.setFillColor(colour)
            context.addPath(CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil))
            context.fillPath()
        }
        if colours.isLight {
            fillCapsule(capsule, resolved(.labelColor, opacity: 0.16))
            fillCapsule(capsule.insetBy(dx: 0.5, dy: 0.5), colours.background)
        } else {
            fillCapsule(capsule, colours.background)
        }
        let dotsWidth = dotSizes.reduce(0, +) + dotSpacing * CGFloat(dotSizes.count - 1)
        var x = capsule.minX + (capsule.width - dotsWidth) / 2
        for (size, colour) in zip(dotSizes, colours.dots) {
            context.setFillColor(colour)
            context.fillEllipse(in: CGRect(x: x, y: capsule.midY - size / 2, width: size, height: size))
            x += size + dotSpacing
        }

        var textMaxX = rect.maxX - padding
        if selected, let tick = checkmark(style.tint) {
            let size = tick.size
            let origin = CGPoint(x: textMaxX - size.width, y: rect.midY - size.height / 2)
            tick.draw(in: CGRect(origin: origin, size: size), from: .zero, operation: .sourceOver, fraction: 1,
                      respectFlipped: true, hints: nil)
            textMaxX = origin.x - 8
        }
        let font = selected ? semibold : regular
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let textX = capsule.maxX + 8
        let textRect = CGRect(x: textX, y: rect.midY - lineHeight / 2, width: max(0, textMaxX - textX), height: lineHeight)
        (title as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                 attributes: [.font: font, .foregroundColor: style.ink, .paragraphStyle: paragraph])
    }
}

/// The table: clicks choose the theme under the pointer (on release, as a button does),
/// and it takes no keyboard focus or selection of its own.
final class TerminalThemeTableView: NSTableView {
    weak var coordinator: TerminalThemeGrid.Coordinator?
    private var pressed: Int?

    override var acceptsFirstResponder: Bool { false }

    /// The theme whose cell holds the point, if any (the gaps between cells choose nothing).
    func item(at point: NSPoint) -> Int? {
        let row = row(at: point)
        guard row >= 0, let coordinator else { return nil }
        let rowRect = rect(ofRow: row)
        let local = CGPoint(x: point.x - rowRect.minX, y: point.y - rowRect.minY)
        for (column, cell) in TerminalThemeLayout.cells(width: rowRect.width, row: row).enumerated() where cell.contains(local) {
            let index = row * TerminalThemeLayout.columns + column
            return index < coordinator.items.count ? index : nil
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        pressed = item(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        guard let pressed, item(at: convert(event.locationInWindow, from: nil)) == pressed else { return }
        coordinator?.choose(pressed)
    }
}

/// One table row: three themes, drawn together. Each is an accessibility button.
final class TerminalThemeRowView: NSTableRowView {
    static let reuse = NSUserInterfaceItemIdentifier("TerminalThemeRow")
    weak var coordinator: TerminalThemeGrid.Coordinator?
    var row = 0

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func drawBackground(in dirtyRect: NSRect) {}
    override func drawSelection(in dirtyRect: NSRect) {}
    override func drawSeparator(in dirtyRect: NSRect) {}

    override func setFrameSize(_ newSize: NSSize) {
        let resized = newSize != frame.size
        super.setFrameSize(newSize)
        if resized { needsDisplay = true }
    }

    private func entries() -> [(index: Int, rect: CGRect)] {
        guard let coordinator else { return [] }
        return TerminalThemeLayout.cells(width: bounds.width, row: row).enumerated().compactMap { column, rect in
            let index = row * TerminalThemeLayout.columns + column
            return index < coordinator.items.count ? (index, rect) : nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let coordinator, let context = NSGraphicsContext.current?.cgContext else { return }
        for (index, rect) in entries() where rect.intersects(dirtyRect) {
            let item = coordinator.items[index]
            TerminalThemeLayout.draw(title: item.title, pill: coordinator.pills[index],
                                     selected: item.id == coordinator.selectedID, style: coordinator.style,
                                     in: rect, context: context)
        }
    }

    override func isAccessibilityElement() -> Bool { false }

    override func accessibilityChildren() -> [Any]? {
        guard let coordinator else { return [] }
        return entries().map { index, rect in
            let item = coordinator.items[index]
            let element = TerminalThemeCellElement()
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(item.title)
            element.setAccessibilitySelected(item.id == coordinator.selectedID)
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(rect)
            element.press = { [weak coordinator] in coordinator?.choose(index) }
            return element
        }
    }
}

final class TerminalThemeCellElement: NSAccessibilityElement {
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool {
        press?()
        return press != nil
    }
}
