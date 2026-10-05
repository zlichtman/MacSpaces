import AppKit
import SwiftUI

/// Small shared pieces for the clipboard's popup, page and widget: writing a
/// snippet, filing a clip in a collection, the "Copy as" menu and dragging clips out.
@MainActor
enum ClipboardActions {
    /// Asks for a snippet's text (and optional collection) and saves it as a pinned clip.
    static func newSnippet(_ monitor: ClipboardMonitor) {
        let alert = NSAlert()
        alert.messageText = "New Snippet"
        alert.informativeText = "Text you paste often. Snippets are kept like pins."
        let text = NSTextView(frame: NSRect(x: 0, y: 30, width: 320, height: 110))
        text.isRichText = false
        text.font = .systemFont(ofSize: 13)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 30, width: 320, height: 110))
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let collection = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        collection.placeholderString = "Collection (optional), such as Email"
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 140))
        container.addSubview(scroll); container.addSubview(collection)
        alert.accessoryView = container
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = text
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = collection.stringValue.trimmingCharacters(in: .whitespaces)
        monitor.addSnippet(text.string, collection: name.isEmpty ? nil : name)
    }

    static func newCollection(for clip: ClipboardEntry, _ monitor: ClipboardMonitor) {
        let alert = NSAlert()
        alert.messageText = "New Collection"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { monitor.setCollection(clip, to: name) }
    }

    /// Drag a clip into another app: the image, the file or the text.
    static func dragItem(_ clip: ClipboardEntry) -> NSItemProvider {
        if let data = clip.imageData, let image = NSImage(data: data) { return NSItemProvider(object: image) }
        if let url = clip.fileURLs.first { return NSItemProvider(object: url as NSURL) }
        return NSItemProvider(object: clip.text as NSString)
    }
}

/// The right-click menu for a clip, the same everywhere.
struct ClipMenu: View {
    let clip: ClipboardEntry
    @ObservedObject var monitor: ClipboardMonitor
    var paste: ((ClipboardEntry, Bool) -> Void)?

    var body: some View {
        Button("Copy") { monitor.copyToPasteboard(clip) }
        if let paste { Button("Paste") { paste(clip, false) }; Button("Paste as Plain Text") { paste(clip, true) } }
        if !clip.recognizedText.isEmpty {
            Button("Copy Text in Image") { monitor.copyToPasteboard(ClipboardEntry(text: clip.recognizedText)) }
        }
        Menu("Copy As") {
            ForEach(ClipboardEntry.CaseStyle.allCases) { style in Button(style.title) { monitor.copy(clip, as: style) } }
        }
        Divider()
        Button(clip.isFavorite ? "Unpin" : "Pin") { _ = monitor.toggleFavorite(clip) }
        Menu("Collection") {
            ForEach(monitor.collections, id: \.self) { name in
                Button(name) { monitor.setCollection(clip, to: name) }
            }
            if !monitor.collections.isEmpty { Divider() }
            Button("New Collection…") { ClipboardActions.newCollection(for: clip, monitor) }
            if !clip.tags.isEmpty { Button("Remove from Collection") { monitor.setCollection(clip, to: nil) } }
        }
        Divider()
        Button("Delete", role: .destructive) { monitor.remove(clip) }
    }
}

/// One clip in a list, shared by the Clipboard widget and the Clipboard page:
/// click to copy (with a visible check), drag it out, right-click for the rest.
/// The page shows where it came from and its star and remove buttons.
struct ClipListRow: View {
    let entry: ClipboardEntry
    @ObservedObject var monitor: ClipboardMonitor
    var detailed = false
    var lines = 1
    @ObservedObject private var theme = ThemeStore.shared
    @State private var copied = false

    var body: some View {
        HStack(spacing: detailed ? 10 : 6) {
            Button {
                monitor.copyToPasteboard(entry)
                withAnimation(.easeOut(duration: 0.15)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { copied = false } }
            } label: {
                HStack(spacing: detailed ? 10 : 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.preview).font(.system(size: detailed ? 12 : 10)).lineLimit(detailed ? 2 : lines)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if detailed {
                            Text([entry.sourceName, entry.date.formatted(date: .omitted, time: .shortened)]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    if detailed {
                        if copied { Label("Copied", systemImage: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.green) }
                    } else {
                        Image(systemName: copied ? "checkmark" : (entry.isFavorite ? "star.fill" : "doc.on.doc"))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(copied ? Color.green : .secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy again")
            if detailed {
                Button { _ = monitor.toggleFavorite(entry) } label: {
                    Image(systemName: entry.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(entry.isFavorite ? AnyShapeStyle(theme.notch.accent) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.isFavorite ? "Unfavorite clip" : "Favorite clip")
                Button { monitor.remove(entry) } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Remove clip")
            }
        }
        .padding(.horizontal, detailed ? 11 : 7)
        .padding(.vertical, detailed ? 8 : 5)
        .background(Color.primary.opacity(detailed ? 0.04 : 0.06), in: RoundedRectangle(cornerRadius: detailed ? 9 : 7, style: .continuous))
        .onDrag { ClipboardActions.dragItem(entry) }
        .contextMenu { ClipMenu(clip: entry, monitor: monitor) }
    }
}
