import AppKit
import SwiftUI

/// The Themes list: an AppKit table in its own scroll view, three themes to a
/// row, each row drawn in one pass and reused as it scrolls. It looks exactly like the
/// SwiftUI rows it replaced (`TerminalThemeLayout`): a 56 × 16 pt capsule in the theme's
/// background holding its accent and red, green, yellow, blue and magenta as six dots
/// (7 pt then 6 pt, 3 pt apart; a light background gets a faint edge), 8 pt, the family's
/// name in 12 pt type with its pack small beneath (unless a pack is chosen), then in fixed spots a scene's picture, its live mark or level bars, and a moon or sun; the theme in
/// use on a soft accent tint with a semibold name. Hovering shows the full name. Scrolling never touches SwiftUI: the 830-theme `LazyVGrid` of buttons it
/// replaced relaid out and rebuilt rows on the main thread as they scrolled in.
struct TerminalThemeGrid: NSViewRepresentable {
    let items: [TerminalThemeItem]
    /// Our palettes' pills (`GhosttyLibrary.ownPills`); Ghostty's carry their own.
    let ownPills: [ThemeFamily: TerminalPillColours]
    /// `GhosttyLibrary.editRevision`: a recoloured theme's pill redraws.
    let revision: Int
    /// The search and tone: a new one scrolls back to the top.
    let filter: String
    /// Whether each row names its pack: not inside one pack, where they'd all say the same.
    let showsPack: Bool
    /// `TerminalThemeItem.id` of the theme in use.
    let selectedID: String
    let tint: NSColor
    /// The names' colour (Settings' foreground).
    let ink: NSColor
    /// Settings' scheme, for the light pills' edge (`Color.primary` at 16%).
    let dark: Bool
    /// What a click does; nil uses the theme on the Nook. The Agent card picks the agent's colours.
    var onChoose: ((TerminalThemeItem) -> Void)? = nil
    /// Whether the arrow keys flip through it: Appearance's list, or the Agent card's when it
    /// picks for the agent (`ThemeArrowKeyRouter` sends them to whichever is showing).
    var arrowKeys = true

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
        let coordinator = context.coordinator
        if arrowKeys {
            if onChoose != nil {
                ThemeArrowKeyRouter.shared.setAgent({ coordinator.move($0) }, view: scroll)
            } else {
                ThemeArrowKeyRouter.shared.set({ coordinator.move($0) }, for: .terminal)
            }
        }
        return scroll
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if coordinator.onChoose == nil {
            ThemeArrowKeyRouter.shared.set(nil, for: .terminal)
        } else {
            ThemeArrowKeyRouter.shared.clearAgent(scroll)
        }
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
        private var revision = 0
        private(set) var showsPack = true
        private var preview: NSPopover?
        private(set) var selectedID = ""
        private(set) var style = TerminalThemeLayout.Style(tint: .controlAccentColor, ink: .labelColor)
        private(set) var onChoose: ((TerminalThemeItem) -> Void)?

        func apply(_ grid: TerminalThemeGrid) {
            onChoose = grid.onChoose
            guard let table else { return }
            let appearance = NSAppearance(named: grid.dark ? .darkAqua : .aqua)
            if table.enclosingScrollView?.appearance?.name != appearance?.name {
                table.enclosingScrollView?.appearance = appearance
            }
            let ids = grid.items.map(\.id)
            let reload = ids != self.ids || grid.ownPills != ownPills || grid.revision != revision
            revision = grid.revision
            let newStyle = TerminalThemeLayout.Style(tint: grid.tint, ink: grid.ink)
            let restyle = grid.selectedID != selectedID || newStyle != style || grid.showsPack != showsPack
            selectedID = grid.selectedID
            showsPack = grid.showsPack
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
                    case .ghostty(let theme): return GhosttyLibrary.shared.current(item)?.pill ?? theme.pill
                    }
                }
                table.reloadData()
                // Rows drawn before the reload are redrawn from the new list, not left as they were.
                table.enumerateAvailableRowViews { row, _ in row.needsDisplay = true }
            } else if restyle {
                table.enumerateAvailableRowViews { row, _ in row.needsDisplay = true }
            }
        }

        /// An arrow key: the next theme in the current search, applied, with its row in view.
        func move(_ direction: GridMove.Direction) -> Bool {
            guard let next = GridMove.target(from: ids.firstIndex(of: selectedID), count: items.count,
                                             columns: TerminalThemeLayout.columns, direction) else { return false }
            choose(next)
            if onChoose != nil {
                // The agent's pick shows at once, so a quick run of keys steps on from it.
                selectedID = ids[next]
                table?.enumerateAvailableRowViews { row, _ in row.needsDisplay = true }
            }
            table?.scrollRowToVisible(next / TerminalThemeLayout.columns)
            return true
        }

        func choose(_ index: Int) {
            guard items.indices.contains(index) else { return }
            preview?.close()
            if let onChoose { onChoose(items[index]) } else { GhosttyLibrary.shared.use(items[index]) }
        }

        /// A scene's small picture, pressed: the same picture large, beside it.
        func showPicture(item index: Int, at rect: NSRect, of view: NSView) {
            guard items.indices.contains(index), let asset = items[index].photo,
                  let image = MotifThumbnails.shared.image(asset) else { return }
            preview?.close()
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = !ThemeStore.shared.reduceMotion
            popover.appearance = view.effectiveAppearance
            let width: CGFloat = 320, height = (width * CGFloat(image.height) / CGFloat(max(1, image.width))).rounded()
            let picture = Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                .frame(width: width, height: height).clipped()
                .accessibilityLabel("\(items[index].title) picture")
            popover.contentViewController = NSHostingController(rootView: picture)
            popover.contentSize = NSSize(width: width, height: height)
            popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
            preview = popover
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
    private static let pill = CGSize(width: 56, height: 16)
    private static let dotSizes: [CGFloat] = [7, 6, 6, 6, 6, 6]
    private static let dotSpacing: CGFloat = 3
    private static let regular = NSFont.systemFont(ofSize: 12, weight: .regular)
    private static let semibold = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private static let packFont = NSFont.systemFont(ofSize: 9.5, weight: .medium)
    private static let barsWidth: CGFloat = 12
    private static let toneWidth: CGFloat = 11
    private static let picture = CGSize(width: 28, height: 18)
    private static var toneImages: [String: NSImage] = [:]

    /// A colour as drawn now (catalogue colours resolve in the current appearance), with
    /// its opacity multiplied as SwiftUI's `opacity(_:)` does.
    private static func resolved(_ colour: NSColor, opacity: CGFloat = 1) -> CGColor {
        let rgb = colour.usingColorSpace(.sRGB) ?? colour
        return rgb.withAlphaComponent(rgb.alphaComponent * opacity).cgColor
    }

    /// A row's small mark in the given colour at the tag's strength: the moon or sun, or the
    /// sparkles of a live scene. Made once per colour.
    private static func mark(_ symbol: String, ink: NSColor, opacity: CGFloat = 0.6) -> NSImage? {
        let key = "\(symbol)|\(opacity)|\(ink.description)"
        if let image = toneImages[key] { return image }
        let colour = NSColor(cgColor: resolved(ink, opacity: opacity)) ?? ink
        let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [colour]))
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        toneImages[key] = image
        return image
    }

    private static func drawMark(_ image: NSImage, width: CGFloat, right: CGFloat, midY: CGFloat) {
        let size = image.size
        image.draw(in: CGRect(x: right - width + (width - size.width) / 2, y: midY - size.height / 2,
                              width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// Where a scene's small picture sits in its cell: just before its live mark.
    static func pictureRect(in rect: CGRect) -> CGRect {
        let right = rect.maxX - padding - toneWidth - 4 - barsWidth - 6
        return CGRect(x: right - picture.width, y: rect.midY - picture.height / 2, width: picture.width, height: picture.height)
    }

    /// One theme: the tint when it's in use, the pill, the name, then its tone, level and pack.
    /// The last three keep their spots whatever the name, so the columns read straight down.
    static func draw(item: TerminalThemeItem, pill colours: TerminalPillColours, selected: Bool, showsPack: Bool, style: Style,
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

        // At the end, in fixed spots so the columns read straight down: a scene's picture, then
        // the live mark or level bars, then the moon or sun. The name takes the rest, with its
        // pack as a small line under it.
        var right = rect.maxX - padding
        if let tone = mark(item.isDark ? "moon.fill" : "sun.max.fill", ink: style.ink) {
            drawMark(tone, width: toneWidth, right: right, midY: rect.midY)
        }
        right -= toneWidth + 4
        if item.isLive {
            if let live = mark("sparkles", ink: style.tint, opacity: 1) {
                drawMark(live, width: barsWidth, right: right, midY: rect.midY)
            }
        } else if let level = item.level {
            let heights: [CGFloat] = [4, 6, 8]
            for (index, height) in heights.enumerated() {
                let bar = CGRect(x: right - barsWidth + CGFloat(index) * 4.5, y: rect.midY + 4 - height, width: 3, height: height)
                context.setFillColor(resolved(style.ink, opacity: index < level ? 0.7 : 0.18))
                context.addPath(CGPath(roundedRect: bar, cornerWidth: 1, cornerHeight: 1, transform: nil))
                context.fillPath()
            }
        }
        right -= barsWidth + 6
        if let asset = item.photo {
            let frame = pictureRect(in: rect)
            if let photo = MotifThumbnails.shared.image(asset) {
                context.saveGState()
                context.addPath(CGPath(roundedRect: frame, cornerWidth: 4, cornerHeight: 4, transform: nil))
                context.clip()
                // Filling the frame; this context is flipped and an image draws from the bottom.
                let scale = max(frame.width / CGFloat(photo.width), frame.height / CGFloat(photo.height))
                let drawn = CGSize(width: CGFloat(photo.width) * scale, height: CGFloat(photo.height) * scale)
                context.translateBy(x: frame.midX, y: frame.midY)
                context.scaleBy(x: 1, y: -1)
                context.draw(photo, in: CGRect(x: -drawn.width / 2, y: -drawn.height / 2, width: drawn.width, height: drawn.height))
                context.restoreGState()
            }
            right = frame.minX - 4
        }
        let font = selected ? semibold : regular
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let textX = capsule.maxX + 6, width = max(0, right - textX)
        let edited = GhosttyLibrary.shared.isEdited(item)
        let tagged = showsPack || edited
        let nameRect = CGRect(x: textX, y: tagged ? rect.midY - 13 : rect.midY - 8, width: width, height: 15)
        (item.familyTitle as NSString).draw(with: nameRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                            attributes: [.font: font, .foregroundColor: style.ink, .paragraphStyle: paragraph])
        guard tagged else { return }
        let packRect = CGRect(x: textX, y: rect.midY + 1.5, width: width, height: 12)
        ((edited ? "Edited" : item.packTitle) as NSString).draw(with: packRect, options: [.usesLineFragmentOrigin], attributes: [
            .font: packFont, .foregroundColor: edited ? style.tint : NSColor(cgColor: resolved(style.ink, opacity: 0.5)) ?? style.ink,
            .paragraphStyle: paragraph])
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
        let point = convert(event.locationInWindow, from: nil)
        guard let pressed, item(at: point) == pressed, let coordinator else { return }
        // A scene's small picture opens large; anywhere else chooses the theme.
        let tableRow = row(at: point), rowRect = rect(ofRow: tableRow)
        let cell = TerminalThemeLayout.cells(width: rowRect.width, row: tableRow)[pressed % TerminalThemeLayout.columns]
        let local = CGPoint(x: point.x - rowRect.minX, y: point.y - rowRect.minY)
        if coordinator.items[pressed].photo != nil, TerminalThemeLayout.pictureRect(in: cell).contains(local) {
            coordinator.showPicture(item: pressed, at: TerminalThemeLayout.pictureRect(in: cell).offsetBy(dx: rowRect.minX, dy: rowRect.minY), of: self)
            return
        }
        coordinator.choose(pressed)
    }
}

/// One table row: three themes, drawn together. Each is an accessibility button.
final class TerminalThemeRowView: NSTableRowView, NSViewToolTipOwner {
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
            TerminalThemeLayout.draw(item: item, pill: coordinator.pills[index],
                                     selected: item.id == coordinator.selectedID, showsPack: coordinator.showsPack, style: coordinator.style,
                                     in: rect, context: context)
        }
    }

    /// The full name on hover: the row itself shows the family.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        removeAllToolTips()
        for (index, rect) in entries() {
            addToolTip(rect, owner: self, userData: UnsafeMutableRawPointer(bitPattern: index + 1))
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let coordinator, let data else { return "" }
        let index = Int(bitPattern: data) - 1
        return coordinator.items.indices.contains(index) ? coordinator.items[index].title : ""
    }

    override func isAccessibilityElement() -> Bool { false }

    override func accessibilityChildren() -> [Any]? {
        guard let coordinator else { return [] }
        return entries().map { index, rect in
            let item = coordinator.items[index]
            let element = TerminalThemeCellElement()
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel("\(item.title), \(item.packTitle)" + (item.isLive ? ", live" : ""))
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
