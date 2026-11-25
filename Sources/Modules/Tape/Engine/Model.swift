import Foundation
import CoreGraphics

struct WindowID: Hashable, Codable, Sendable {
    let rawValue: UUID
    init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

enum ColumnWidth: Equatable, Sendable {
    case fraction(Double)
    case points(Double)

    func resolve(in availableWidth: Double) -> Double {
        let value: Double
        switch self {
        case .fraction(let fraction): value = fraction * availableWidth
        case .points(let points): value = points
        }
        // Never narrower than discovery's smallest tile, so Tape's own widths don't make a window
        // look like a palette.
        let smallest = min(Double(WindowDiscovery.smallestTile.width), availableWidth)
        return min(max(value.isFinite ? value : availableWidth / 2, smallest), availableWidth)
    }
}

enum ColumnMode: String, Sendable { case stacked, tabbed }

struct Column: Equatable, Sendable {
    let id = UUID()
    var windows: [WindowID]
    var width: ColumnWidth
    var minimumWidth: Double = 0
    var automaticWidth = true
    var mode: ColumnMode = .stacked
    var activeWindow: WindowID?
    var heightWeights: [WindowID: Double] = [:]
    var minimumHeights: [WindowID: Double] = [:]
    init(window: WindowID, width: ColumnWidth = .fraction(0.5)) {
        windows = [window]
        self.width = width
        activeWindow = window
    }
}

struct Strip: Equatable, Sendable {
    var columns: [Column] = []
    var scrollOffset: Double = 0
    var focusedWindow: WindowID?
    init() {}
    var focusedIndex: Int? {
        columns.firstIndex { $0.windows.contains(where: { $0 == focusedWindow }) }
    }

    /// A background window joins the strip without changing focus or the viewport.
    mutating func insert(_ id: WindowID, foreground: Bool, width: ColumnWidth = .fraction(0.5)) {
        guard !columns.contains(where: { $0.windows.contains(id) }) else { return }
        let index = focusedIndex.map { $0 + 1 } ?? columns.count
        columns.insert(Column(window: id, width: width), at: index)
        if foreground { focusedWindow = id }
    }

    mutating func remove(_ id: WindowID) {
        let oldIndex = focusedIndex ?? 0
        for index in columns.indices {
            let oldSlot = columns[index].windows.firstIndex(of: id) ?? 0
            columns[index].windows.removeAll { $0 == id }
            columns[index].heightWeights.removeValue(forKey: id)
            columns[index].minimumHeights.removeValue(forKey: id)
            if columns[index].activeWindow == id {
                columns[index].activeWindow = columns[index].windows.isEmpty ? nil
                    : columns[index].windows[min(oldSlot, columns[index].windows.count - 1)]
            }
        }
        columns.removeAll { $0.windows.isEmpty }
        if focusedWindow == id {
            focusedWindow = columns.isEmpty ? nil : columns[min(oldIndex, columns.count - 1)].activeWindow
        }
    }

    mutating func perform(_ action: StripAction) {
        guard !columns.isEmpty else { return }
        let index = focusedIndex ?? 0
        switch action {
        case .focus(let destination):
            let target: Int
            switch destination {
            case .left: target = index - 1
            case .right: target = index + 1
            case .first: target = 0
            case .last: target = columns.count - 1
            case .slot(let slot):
                guard columns.indices.contains(slot) else { return }
                target = slot
            }
            focusedWindow = columns[min(max(target, 0), columns.count - 1)].activeWindow
        case .move(let direction):
            let target = index + direction
            guard columns.indices.contains(target) else { return }
            columns.swapAt(index, target)
        case .nextWidth:
            let presets = [1.0 / 3, 0.5, 2.0 / 3, 1.0]
            let shown = displayedFraction(of: index)
            columns[index].automaticWidth = false
            if let current = shown {
                columns[index].width = .fraction(presets.first { $0 > current + 0.001 } ?? presets[0])
            } else {
                columns[index].width = .fraction(presets[0])
            }
        case .adjustWidth(let delta):
            guard delta.isFinite else { return }
            let shown = displayedFraction(of: index)
            columns[index].automaticWidth = false
            if let fraction = shown {
                columns[index].width = .fraction(min(max(fraction + delta, 0.2), 1))
            } else if case .points(let points) = columns[index].width {
                columns[index].width = .points(max(Double(WindowDiscovery.smallestTile.width), points + delta * 1000))
            }
        case .setWidth(let fraction):
            guard fraction.isFinite else { return }
            columns[index].automaticWidth = false
            columns[index].width = .fraction(min(max(fraction, 0.2), 1))
        case .join(let direction):
            let target = index + direction
            guard columns.indices.contains(target), let id = focusedWindow else { return }
            columns[target].windows.append(id)
            columns[target].activeWindow = id
            remove(id, fromColumn: index)
        case .detach:
            guard columns[index].windows.count > 1, let id = focusedWindow else { return }
            var column = Column(window: id, width: columns[index].width)
            column.automaticWidth = columns[index].automaticWidth
            remove(id, fromColumn: index)
            columns.insert(column, at: index + 1)
        case .toggleColumnMode:
            columns[index].mode = columns[index].mode == .stacked ? .tabbed : .stacked
        case .focusInColumn(let direction):
            guard let id = focusedWindow, let slot = columns[index].windows.firstIndex(of: id) else { return }
            let count = columns[index].windows.count
            let target = (slot + direction % count + count) % count
            focusedWindow = columns[index].windows[target]
            columns[index].activeWindow = focusedWindow
        case .moveInColumn(let direction):
            guard let id = focusedWindow, let slot = columns[index].windows.firstIndex(of: id) else { return }
            let target = slot + direction
            guard columns[index].windows.indices.contains(target) else { return }
            columns[index].windows.swapAt(slot, target)
        case .equalHeights: columns[index].heightWeights.removeAll()
        case .adjustHeight(let delta):
            guard delta.isFinite, let id = focusedWindow, columns[index].windows.count > 1 else { return }
            columns[index].heightWeights[id] = min(8, max(0.25, (columns[index].heightWeights[id] ?? 1) + delta))
        }
    }

    /// The width the column is shown at, as a fraction: a lone automatic column fills the screen.
    func displayedFraction(of index: Int) -> Double? {
        guard columns.indices.contains(index) else { return nil }
        if columns.count == 1 && columns[index].automaticWidth { return 1 }
        if case .fraction(let fraction) = columns[index].width { return fraction }
        return nil
    }

    private mutating func remove(_ id: WindowID, fromColumn index: Int) {
        columns[index].windows.removeAll { $0 == id }
        columns[index].heightWeights.removeValue(forKey: id)
        columns[index].minimumHeights.removeValue(forKey: id)
        if columns[index].activeWindow == id { columns[index].activeWindow = columns[index].windows.first }
        if columns[index].windows.isEmpty { columns.remove(at: index) }
    }

    mutating func select(_ id: WindowID) {
        guard let index = columns.firstIndex(where: { $0.windows.contains(id) }) else { return }
        focusedWindow = id
        columns[index].activeWindow = id
    }

    mutating func setWidths(_ width: ColumnWidth) {
        for index in columns.indices { columns[index].width = width; columns[index].automaticWidth = false }
    }

    mutating func reorder(_ id: WindowID, to target: Int) {
        guard let source = columns.firstIndex(where: { $0.windows.contains(id) }), columns.indices.contains(target), source != target else { return }
        let column = columns.remove(at: source)
        columns.insert(column, at: target)
    }

    mutating func reorderTab(_ id: WindowID, before other: WindowID) {
        guard let index = columns.firstIndex(where: { $0.windows.contains(id) && $0.windows.contains(other) }), id != other,
              let source = columns[index].windows.firstIndex(of: id) else { return }
        columns[index].windows.remove(at: source)
        let target = columns[index].windows.firstIndex(of: other)!
        columns[index].windows.insert(id, at: target)
    }

    mutating func moveTab(_ id: WindowID, to target: Int) {
        guard let index = columns.firstIndex(where: { $0.windows.contains(id) }),
              columns[index].windows.indices.contains(target), let source = columns[index].windows.firstIndex(of: id) else { return }
        columns[index].windows.remove(at: source)
        columns[index].windows.insert(id, at: target)
    }
}

enum FocusDestination: Equatable, Sendable {
    case left, right, first, last, slot(Int)
}

enum StripAction: Equatable, Sendable {
    case focus(FocusDestination), move(Int), nextWidth, adjustWidth(Double), setWidth(Double)
    case join(Int), detach, toggleColumnMode, focusInColumn(Int), moveInColumn(Int), equalHeights, adjustHeight(Double)
}

enum CenteringMode: String, CaseIterable, Sendable {
    case never, overflow, always
}

struct LayoutOptions: Equatable, Sendable {
    var gap: Double
    var edgeGap: Double
    var centering: CenteringMode
    init(gap: Double = 8, edgeGap: Double = 8, centering: CenteringMode = .never) {
        self.gap = gap
        self.edgeGap = edgeGap
        self.centering = centering
    }
}

struct ScreenGeometry: Equatable, Sendable {
    /// All rectangles use Accessibility coordinates: origin at the primary display's top left.
    var frame: CGRect
    var visibleFrame: CGRect
    var neighbors: [CGRect]
    init(frame: CGRect, visibleFrame: CGRect, neighbors: [CGRect] = []) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.neighbors = neighbors
    }
}

struct WindowSnapshot: Sendable {
    let id: WindowID
    let frame: CGRect
    let processID: Int32
    let isTileable: Bool
    /// Tileable but for `WindowTraits.isTooSmall`: a window Tape already tiles stays in its strip
    /// when Tape's own layout makes it that small.
    let isTileableAtAnySize: Bool
    let bundleIdentifier: String?
    let title: String?
    init(id: WindowID, frame: CGRect, processID: Int32, isTileable: Bool, isTileableAtAnySize: Bool? = nil,
         bundleIdentifier: String? = nil, title: String? = nil) {
        self.id = id; self.frame = frame; self.processID = processID; self.isTileable = isTileable
        self.isTileableAtAnySize = isTileableAtAnySize ?? isTileable
        self.bundleIdentifier = bundleIdentifier
        self.title = title
    }
    /// The same window, tileable whatever its size.
    func tiledAtAnySize() -> WindowSnapshot {
        guard !isTileable, isTileableAtAnySize else { return self }
        return WindowSnapshot(id: id, frame: frame, processID: processID, isTileable: true,
                              bundleIdentifier: bundleIdentifier, title: title)
    }
}

struct WindowTraits: Sendable {
    var isStandard: Bool
    var canMove: Bool
    var canResize: Bool
    var isMinimized: Bool
    var isFullscreen: Bool
    var isOwnWindow: Bool
    var hasSheet: Bool
    /// Can't be resized in practice: a known fixed-size app, or its zoom button is disabled.
    var isFixedSizeApp: Bool
    /// Blocks its app until answered.
    var isModal: Bool
    /// Under `WindowDiscovery.smallestTile`.
    var isTooSmall: Bool
    var isTileable: Bool {
        isStandard && canMove && canResize && !isMinimized && !isFullscreen && !isOwnWindow && !hasSheet && !isFixedSizeApp
            && !isModal && !isTooSmall
    }
    var isTileableAtAnySize: Bool {
        var traits = self
        traits.isTooSmall = false
        return traits.isTileable
    }
    init(isStandard: Bool = true, canMove: Bool = true, canResize: Bool = true,
                isMinimized: Bool = false, isFullscreen: Bool = false,
                isOwnWindow: Bool = false, hasSheet: Bool = false, isFixedSizeApp: Bool = false,
                isModal: Bool = false, isTooSmall: Bool = false) {
        self.isStandard = isStandard; self.canMove = canMove; self.canResize = canResize
        self.isMinimized = isMinimized; self.isFullscreen = isFullscreen
        self.isOwnWindow = isOwnWindow; self.hasSheet = hasSheet
        self.isFixedSizeApp = isFixedSizeApp; self.isModal = isModal; self.isTooSmall = isTooSmall
    }
}
