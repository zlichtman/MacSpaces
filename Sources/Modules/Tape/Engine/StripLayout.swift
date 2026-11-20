import Foundation
import CoreGraphics

enum StripLayout {
    static func contentRect(screen: ScreenGeometry, options: LayoutOptions) -> CGRect {
        let rect = screen.visibleFrame.intersection(screen.frame)
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return .zero }
        let edge = min(max(options.edgeGap.isFinite ? options.edgeGap : 0, 0), max(0, min(rect.width, rect.height) / 2 - 1))
        return rect.insetBy(dx: edge, dy: edge)
    }

    static func columnRects(for strip: Strip, screen: ScreenGeometry, options: LayoutOptions) -> [CGRect] {
        let content = contentRect(screen: screen, options: options)
        guard content.width > 0, content.height > 0 else { return [] }
        let gap = max(0, options.gap.isFinite ? options.gap : 0)
        var x = content.minX - (strip.scrollOffset.isFinite ? strip.scrollOffset : 0)
        return strip.columns.map { column in
            let preferred = strip.columns.count == 1 && column.automaticWidth ? content.width : column.width.resolve(in: content.width)
            let width = min(content.width, max(column.minimumWidth, preferred))
            let rect = CGRect(x: x, y: content.minY, width: width, height: content.height)
            x += rect.width + gap
            return rect
        }
    }

    /// Pure logical layout. Columns retain their widths and never overlap.
    static func frames(for strip: Strip, screen: ScreenGeometry, options: LayoutOptions) -> [WindowID: CGRect] {
        let rects = columnRects(for: strip, screen: screen, options: options)
        var frames: [WindowID: CGRect] = [:]
        for (column, rect) in zip(strip.columns, rects) {
            if column.mode == .tabbed && column.windows.count > 1 {
                let bar = min(tabBarHeight, max(0, rect.height - 1))
                let body = CGRect(x: rect.minX, y: rect.minY + bar, width: rect.width, height: rect.height - bar)
                // Tabs share one frame; the active tab is raised after writes settle.
                for id in column.windows { frames[id] = body }
                continue
            }
            let count = max(column.windows.count, 1)
            let gap = min(max(0, options.gap.isFinite ? options.gap : 0), max(0, (rect.height - Double(count)) / Double(max(1, count - 1))))
            let available = max(Double(count), rect.height - gap * Double(count - 1))
            let weights = column.windows.map { id -> Double in
                let value = column.heightWeights[id] ?? 1
                return value.isFinite ? min(8, max(0.25, value)) : 1
            }
            let sum = weights.reduce(0, +)
            let minimums = column.windows.map { id -> Double in
                let value = column.minimumHeights[id] ?? 1
                return value.isFinite ? min(available, max(1, value)) : 1
            }
            let required = minimums.reduce(0, +)
            var y = rect.minY
            for (index, id) in column.windows.enumerated() {
                let height = required > available ? available * minimums[index] / required
                    : minimums[index] + (available - required) * weights[index] / sum
                frames[id] = CGRect(x: rect.minX, y: y, width: rect.width, height: height)
                y += height + gap
            }
        }
        return frames
    }

    static let tabBarHeight: Double = 30

    static func revealedOffset(for strip: Strip, screen: ScreenGeometry, options: LayoutOptions, forceCenter: Bool = false) -> Double {
        guard let index = strip.focusedIndex else { return strip.scrollOffset }
        var unscrolled = strip
        unscrolled.scrollOffset = 0
        let rects = columnRects(for: unscrolled, screen: screen, options: options)
        guard rects.indices.contains(index), let last = rects.last else { return 0 }
        let content = contentRect(screen: screen, options: options)
        let target = rects[index]
        let totalWidth = last.maxX - content.minX
        let maxOffset = max(0, totalWidth - content.width)
        if forceCenter || options.centering == .always || (options.centering == .overflow && maxOffset > 0) {
            return target.midX - content.midX
        }
        var offset = strip.scrollOffset
        if target.minX - offset < content.minX { offset = target.minX - content.minX }
        if target.maxX - offset > content.maxX { offset = target.maxX - content.maxX }
        return min(max(offset, 0), maxOffset)
    }

    /// Browse within the strip bounds without changing its focused column.
    static func scrolledOffset(for strip: Strip, by delta: Double, screen: ScreenGeometry, options: LayoutOptions) -> Double {
        guard delta.isFinite else { return strip.scrollOffset }
        var unscrolled = strip
        unscrolled.scrollOffset = 0
        let content = contentRect(screen: screen, options: options)
        let end = columnRects(for: unscrolled, screen: screen, options: options).last?.maxX ?? content.maxX
        let limit = max(0, end - content.maxX)
        // Preserve any existing centering margin until the gesture moves out of it.
        // Clamping it away on the first pixel would make a centered edge window jump.
        let lower = min(0, strip.scrollOffset)
        let upper = max(limit, strip.scrollOffset)
        return min(max(strip.scrollOffset + delta, lower), upper)
    }

    /// After windows disappear, keep a visible column in reach without changing focus.
    /// Existing centering margins are legitimate; an obsolete far-end offset is not.
    static func constrainedOffset(for strip: Strip, screen: ScreenGeometry, options: LayoutOptions) -> Double {
        var plain = strip; plain.scrollOffset = 0
        let content = contentRect(screen: screen, options: options)
        let rects = columnRects(for: plain, screen: screen, options: options)
        guard let first = rects.first, let last = rects.last else { return 0 }
        let lower = min(0, first.midX - content.midX)
        let upper = max(max(0, last.maxX - content.maxX), last.midX - content.midX)
        return min(max(strip.scrollOffset, lower), upper)
    }

    /// Keep a sliver on the owner display, unless that would enter a neighboring display.
    /// In that case park inside the owner display and raise the focused window above it.
    static func parked(_ rect: CGRect, on screen: ScreenGeometry, sliver: Double = 6) -> CGRect {
        let bounds = screen.frame
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let width = min(max(1, rect.width), bounds.width)
        let height = min(max(1, rect.height), screen.visibleFrame.height)
        let visible = min(max(1, sliver), width)
        let x = min(max(rect.minX, bounds.minX - width + visible), bounds.maxX - visible)
        let y = min(max(rect.minY, screen.visibleFrame.minY), screen.visibleFrame.maxY - height)
        var result = CGRect(x: x, y: y, width: width, height: height)
        if screen.neighbors.contains(where: { $0.intersects(result) }) {
            result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - width)
        }
        return result
    }

    static func restored(_ rect: CGRect, on screen: ScreenGeometry) -> CGRect {
        let bounds = screen.visibleFrame
        let width = min(max(1, rect.width), bounds.width)
        let height = min(max(1, rect.height), bounds.height)
        return CGRect(x: min(max(rect.minX, bounds.minX), bounds.maxX - width),
                      y: min(max(rect.minY, bounds.minY), bounds.maxY - height), width: width, height: height)
    }
}

protocol WindowServer: AnyObject {
    var onChange: (() -> Void)? { get set }
    var onStall: (() -> Void)? { get set }
    var onFocusChange: ((WindowID) -> Void)? { get set }
    var onDesktopChange: (() -> Void)? { get set }
    var onWindowRemoved: ((WindowID) -> Void)? { get set }
    var onWindowInteraction: ((WindowID, CGRect, WindowInteraction, Bool) -> Void)? { get set }
    var pointerPosition: CGPoint? { get }
    func start()
    func stop()
    /// `completion` also gets the Spaces each display shows, read on the scan's worker; nil when
    /// macOS doesn't offer the private list.
    func scan(policy: AppPolicy, completion: @escaping ([WindowSnapshot], WindowID?, [SpaceDisplay]?) -> Void)
    func apply(frames: [WindowID: CGRect])
    func cancelPendingWrites()
    func settle(completion: @escaping () -> Void)
    func focus(_ id: WindowID, activate: Bool)
    func raise(_ ids: [WindowID], preservingFocus: WindowID?)
    func restore(frames: [WindowID: CGRect], completion: @escaping () -> Void)
}

enum WindowInteraction: Sendable { case move, resize }
