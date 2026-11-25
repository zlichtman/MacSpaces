import AppKit
import SwiftUI

/// Studio's script editor: a plain text view that reports its selection (Read reads the selected
/// words) and shows the words being read highlighted in the accent while a take is made. The
/// highlight is drawn by the layout manager, so it never changes the text. SwiftUI's own editor
/// reports no selection before macOS 15.
struct StudioTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange?
    var highlight: NSRange?
    var accent: Color
    var ink: Color
    var fontSize: CGFloat = 13
    var onEditingChanged: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.textContainerInset = NSSize(width: 2, height: 4)
        view.font = .systemFont(ofSize: fontSize)
        view.textColor = .labelColor
        view.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text {
            context.coordinator.updating = true
            view.string = text
            context.coordinator.updating = false
            DispatchQueue.main.async { selection = nil }
        }
        view.font = .systemFont(ofSize: fontSize)
        view.textColor = NSColor(ink)
        view.insertionPointColor = NSColor(accent)
        view.selectedTextAttributes = [.backgroundColor: NSColor(accent).withAlphaComponent(0.32)]
        guard let layout = view.layoutManager else { return }
        let whole = NSRange(location: 0, length: (view.string as NSString).length)
        layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
        if let highlight, NSMaxRange(highlight) <= whole.length {
            layout.addTemporaryAttribute(.backgroundColor, value: NSColor(accent).withAlphaComponent(0.28), forCharacterRange: highlight)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: StudioTextEditor
        /// Set while the text is replaced from outside, whose selection change isn't the user's.
        var updating = false
        init(_ parent: StudioTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating, let view = notification.object as? NSTextView else { return }
            let range = view.selectedRange()
            parent.selection = range.length > 0 ? range : nil
        }

        func textDidBeginEditing(_ notification: Notification) { parent.onEditingChanged(true) }
        func textDidEndEditing(_ notification: Notification) { parent.onEditingChanged(false) }
    }
}
