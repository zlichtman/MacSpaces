#if DEBUG
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor enum SettingsUpdateRegressionChecks {
    static func run() async {
        let suite = "dev.opensource.MacSpaces.Gallery." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = NookSettings(defaults: defaults)
        settings.widgets = [.media, .clock, .timer]
        precondition(NookWidgetTransfer.decode(Data("not-a-widget".utf8)) == nil)
        precondition(NookWidgetTransfer.decode(Data(repeating: 65, count: 1000)) == nil)
        let provider = NookWidgetTransfer.provider(.weather)
        precondition(NookWidgetTransfer.receive([provider], into: settings, before: .clock))
        for _ in 0..<100 where !settings.widgets.contains(.weather) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(settings.widgets == [.media, .weather, .clock, .timer], "A library drop inserts at the target")
        _ = NookWidgetTransfer.receive([provider], into: settings)
        try? await Task.sleep(nanoseconds: 50_000_000)
        precondition(settings.widgets.filter { $0 == .weather }.count == 1, "Repeated drops must not duplicate a widget")

        let window = NotchWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 350))
        var dropped: NookWidgetKind?
        let host = NotchHostingView(rootView: Color.clear,
            interactiveSize: { CGSize(width: 600, height: 300) },
            fileDragActivationSize: { .zero }, fileDragEntered: {}, fileDragExited: {}, fileURLsDropped: { _ in false },
            widgetDataDropped: { data in dropped = NookWidgetTransfer.decode(data); return dropped != nil })
        window.installNookContent(host)
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 350)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally(); window.close() }
        board.setData(Data(NookWidgetKind.weather.rawValue.utf8), forType: .init(UTType.nookWidget.identifier))
        let drag = WidgetDragProbe(window: window, board: board, point: NSPoint(x: 400, y: 200))
        precondition(host.draggingEntered(drag) == .copy && host.prepareForDragOperation(drag))
        precondition(host.performDragOperation(drag) && dropped == .weather, "Native hosting must forward widget payloads")
        drag.point = NSPoint(x: 10, y: 10)
        precondition(host.draggingUpdated(drag).isEmpty && !host.performDragOperation(drag), "Transparent margins must not accept widgets")
        precondition(SettingsSearch.matches("lyrics").first?.destination == .appearance, "Lyrics search opens Appearance")
        checkEditorKeyboard(settings: settings)
        print("Settings update checks passed: typed widget drops, insertion and deduplication, native drop routing and transparent margins, editor Delete/Forward Delete and text focus, fixed sizes and lyrics settings routing")
    }

    private static func checkEditorKeyboard(settings: NookSettings) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let keys = HomeLayoutKeyView(frame: .zero)
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 60))
        window.contentView?.addSubview(keys)
        window.contentView?.addSubview(text)
        keys.removeSelected = { settings.setEnabled(false, for: $0) }
        func press(_ keyCode: UInt16, flags: NSEvent.ModifierFlags = []) {
            let characters = keyCode == 117 ? "\u{f728}" : keyCode == 53 ? "\u{1b}" : "\u{7f}"
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: keyCode)!
            window.sendEvent(event)
        }
        settings.widgets = [.media, .clock, .timer]
        keys.select(.media)
        precondition(window.firstResponder === keys, "Selecting a widget takes keyboard focus, including from search")
        press(51)
        precondition(settings.widgets == [.clock, .timer] && keys.selection == nil, "Delete removes the selected preview")
        keys.select(.timer)
        press(117, flags: [.function, .capsLock])
        precondition(settings.widgets == [.clock], "Forward Delete removes the selected preview")
        keys.select(.clock)
        text.string = "Typing"
        text.setSelectedRange(NSRange(location: text.string.count, length: 0))
        precondition(window.makeFirstResponder(text))
        press(51)
        precondition(text.string == "Typin" && settings.widgets == [.clock], "Delete in a text editor edits text and keeps the selected widget: text=\(text.string), widgets=\(settings.widgets)")
        keys.select(nil)
        keys.select(.clock)
        precondition(window.firstResponder === keys, "Selecting another preview returns keyboard focus from text")
        var deselected = false
        keys.deselect = { deselected = true }
        press(53)
        precondition(deselected && keys.selection == nil && settings.widgets == [.clock], "Escape clears selection without removing the widget")
    }
}

@MainActor private final class WidgetDragProbe: NSObject, NSDraggingInfo {
    let draggingDestinationWindow: NSWindow?
    let draggingPasteboard: NSPasteboard
    var point: NSPoint
    var draggingLocation: NSPoint { point }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    init(window: NSWindow, board: NSPasteboard, point: NSPoint) {
        draggingDestinationWindow = window; draggingPasteboard = board; self.point = point
    }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
#endif
