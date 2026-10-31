import SwiftUI
import UniformTypeIdentifiers

/// Drag-and-drop file staging area: the Nook's Tray page and each file basket.
/// A grid of thumbnails with one toolbar that follows the selection, and a
/// status line for the focused file, the Undo bar and quiet notices.
@MainActor
struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @Binding var isDropTargeted: Bool
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(spacing: 6) {
            if !store.items.isEmpty { toolbar }
            if let error = store.errorText { errorRow(error) }
            if store.items.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
                // Clear All leaves the Undo bar (or a notice) under the empty state.
                if store.undoText != nil || store.notice != nil { statusLine }
            } else {
                grid
                statusLine
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            // The dashed outline invites a drop only while there's nothing
            // here; a drag over a full Tray lights the whole area instead.
            shape
                .fill(theme.notch.accent.opacity(isDropTargeted ? 0.08 : 0))
                .overlay {
                    if isDropTargeted || store.items.isEmpty {
                        shape.strokeBorder(style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1.25, dash: isDropTargeted ? [] : [5, 4]))
                            .foregroundStyle(isDropTargeted ? theme.notch.accent : Color.primary.opacity(0.14))
                    }
                }
        }
        .animation(Design.hoverAnimation, value: isDropTargeted)
        .onAppear { store.pruneMissingItems() }
        .onDrop(of: [UTType.fileURL, .url, .image, .plainText], isTargeted: $isDropTargeted) { providers in
            let accepted = store.handleDrop(providers: providers)
            if accepted { Haptics.drop() }
            return accepted
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        let selected = store.selectedItems
        return HStack(spacing: 5) {
            if selected.isEmpty {
                Text(store.summary)
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.secondary).lineLimit(1)
                Button("Select All") { store.selectAll() }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.notch.accent)
            } else {
                Button { store.select(nil) } label: {
                    HStack(spacing: 4) {
                        Text("\(selected.count) selected").monospacedDigit()
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain).font(.system(size: 10, weight: .semibold))
                .help("Deselect (Escape)")
            }
            Spacer(minLength: 4)
            if selected.isEmpty {
                iconButton("Paste copied files, text, links or images (⌘V)", "doc.on.clipboard") { store.paste() }
                    .keyboardShortcut("v")
                Button {
                    Haptics.drop()
                    store.removeAll()
                } label: { Label("Clear All", systemImage: "xmark.circle") }
                    .buttonStyle(WidgetChipStyle(height: 24))
                    .help("Remove everything from this list. Files stay where they are, and Undo brings them back.")
            } else {
                iconButton("Quick Look (Space)", "eye") { store.quickLook() }
                FileActionMenu(store: store)
                ShareLink(items: selected.map(\.url)) { toolbarIcon("square.and.arrow.up") }
                    .buttonStyle(PremiumPressButtonStyle())
                    .help("Share or AirDrop")
                iconButton("Show in Finder", "folder") { store.revealInFinder(selected) }
                Button {
                    Haptics.drop()
                    store.removeSelected()
                } label: { Label("Remove", systemImage: "minus.circle") }
                    .buttonStyle(WidgetChipStyle(height: 24))
                    .help("Remove from this list (Delete). The files stay where they are.")
            }
        }
        .frame(height: 24)
        .padding(.horizontal, 2)
    }

    private func iconButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { toolbarIcon(symbol) }
            .buttonStyle(PremiumPressButtonStyle())
            .help(title)
            .accessibilityLabel(title)
    }

    private func toolbarIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 24)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
    }

    private func errorRow(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            Text(error).font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if store.needsRecovery {
                Button("Preserve & Recover") { store.recoverPersistence() }.buttonStyle(WidgetChipStyle(height: 22))
            } else {
                Button { store.dismissError() } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Dismiss")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .transition(.opacity)
    }

    // MARK: Grid

    private var grid: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: 6)], spacing: 6) {
                    ForEach(store.items) { item in
                        ShelfItemView(
                            item: item,
                            store: store,
                            preview: store.previews[item.id],
                            info: store.info[item.id],
                            isSelected: store.selectedIDs.contains(item.id),
                            isOffline: store.offlineIDs.contains(item.id),
                            isBusy: store.busyItemIDs.contains(item.id)
                        )
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 2).padding(.top, 2).padding(.bottom, 10)
                .frame(minHeight: proxy.size.height, alignment: .top)
                // Clicking between tiles clears the selection.
                .background(Color.clear.contentShape(Rectangle()).onTapGesture { store.select(nil) })
            }
            // A row cut by the bottom edge fades out instead of ending in a hard line.
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: max(0, 1 - 14 / max(proxy.size.height, 1))),
                                         .init(color: .black.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom))
        }
    }

    // MARK: Status line

    @ViewBuilder
    private var statusLine: some View {
        Group {
            if let undo = store.undoText {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(theme.notch.accent)
                    Text(undo).lineLimit(1).truncationMode(.middle)
                    Text("Files stay where they are").foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    Button("Undo") { store.undoRemoval() }
                        .buttonStyle(WidgetChipStyle(prominent: true, height: 20))
                        .help("Undo (⌘Z)")
                }
                .padding(.leading, 8).padding(.trailing, 2)
                .background(theme.notch.control, in: Capsule())
            } else if let notice = store.notice {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                    Text(notice).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
            } else if let item = store.selectedItem {
                HStack(spacing: 6) {
                    Text(item.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                    Text(store.offlineIDs.contains(item.id)
                         ? "On a disconnected drive · reconnect it to use this file"
                         : store.info[item.id]?.details ?? "")
                        .foregroundStyle(.secondary).lineLimit(1).layoutPriority(-1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
            } else {
                HStack(spacing: 6) {
                    Text("Drag files out into any app · double-click to open")
                        .foregroundStyle(.tertiary).lineLimit(1)
                    Spacer(minLength: 0)
                    if !store.offlineIDs.isEmpty {
                        Button("Remove \(store.offlineIDs.count) on disconnected drives") { store.removeOffline() }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .font(.system(size: 10))
        .frame(height: 22)
        .animation(Design.spring(), value: store.undoText)
        .animation(Design.spring(), value: store.notice)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(isDropTargeted ? theme.notch.accent : Color.secondary)
                .scaleEffect(isDropTargeted && !theme.reduceMotion ? 1.14 : 1)
                .offset(y: isDropTargeted && !theme.reduceMotion ? 2 : 0)
            Text(isDropTargeted ? "Release to add" : "Drop files here")
                .font(.system(size: 12, weight: .semibold))
            Text("They wait here until you drag them into another app.\nRemoving one never deletes the file.")
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .opacity(isDropTargeted ? 0 : 1)
            Button { store.paste() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                .buttonStyle(WidgetChipStyle(height: 24))
                .keyboardShortcut("v")
                .help("Paste copied files, text, links or images (⌘V)")
                .opacity(isDropTargeted ? 0 : 1)
                .padding(.top, 2)
        }
        .animation(Design.spring(), value: isDropTargeted)
    }
}

/// One file: its thumbnail (screenshots and photos fill the frame, documents
/// sit on it like a page, everything else shows its icon) and its name.
@MainActor
private struct ShelfItemView: View {
    let item: ShelfItem
    let store: ShelfStore
    let preview: TrayPreview?
    let info: ShelfFileInfo?
    let isSelected: Bool
    let isOffline: Bool
    let isBusy: Bool
    @ObservedObject private var theme = ThemeStore.shared
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 5) {
            picture
                .frame(height: 66)
                .frame(maxWidth: .infinity)
            Text(item.displayName)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(isOffline ? Color.secondary : Color.primary)
                .padding(.horizontal, 2)
        }
        .padding(5)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            isSelected ? theme.notch.selected : Color.primary.opacity(isHovering ? 0.06 : 0),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isSelected ? theme.notch.accent.opacity(0.8) : .clear, lineWidth: 1.5)
        }
        .overlay {
            ShelfDragHandle(store: store, item: item)
                .accessibilityLabel(item.name)
        }
        .overlay(alignment: .topTrailing) {
            if isHovering && !isBusy {
                Button {
                    Haptics.drop()
                    store.remove(item)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 17, height: 17)
                        .background(Color.black.opacity(0.6), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Remove from Tray (the file stays where it is)")
                .offset(x: 3, y: -3)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .scaleEffect(isHovering && !theme.reduceMotion ? 1.03 : 1)
        .animation(Design.hoverAnimation, value: isHovering)
        .animation(Design.hoverAnimation, value: isSelected)
        .onHover { isHovering = $0 }
        .contextMenu { menu }
    }

    @ViewBuilder
    private var picture: some View {
        ZStack {
            if let preview, preview.isContent, info?.isImage == true {
                // Screenshots and photos fill the frame.
                Color.clear
                    .overlay { Image(nsImage: preview.image).resizable().interpolation(.high).scaledToFill() }
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            } else if let preview, preview.isContent {
                // Documents, PDFs and video sit on the tile like a page.
                Image(nsImage: preview.image)
                    .resizable().interpolation(.high).scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1.5)
                    .overlay(alignment: .bottomTrailing) { badge }
                    .padding(.vertical, 2)
            } else if let preview {
                Image(nsImage: preview.image).resizable().interpolation(.high).scaledToFit()
                    .frame(width: 58, height: 58)
            } else {
                Image(systemName: isOffline ? "externaldrive.badge.xmark" : "doc")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.tertiary)
            }
            if isBusy {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black.opacity(0.45))
                ProgressView().controlSize(.small)
            }
        }
        .saturation(isOffline ? 0 : 1)
        .opacity(isOffline ? 0.45 : 1)
        .overlay(alignment: .bottomTrailing) {
            // A thumbnail kept from before the drive went away gets a small badge.
            if isOffline && preview != nil {
                Image(systemName: "externaldrive.badge.xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(3)
                    .background(.ultraThinMaterial, in: Circle())
                    .help("On a disconnected drive")
            }
        }
        .overlay(alignment: .topLeading) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.black.opacity(0.8), theme.notch.accent)
                    .background(Circle().fill(Color.white.opacity(0.9)).padding(2))
                    .offset(x: -2, y: -2)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .animation(Design.hoverAnimation, value: preview != nil)
    }

    @ViewBuilder
    private var badge: some View {
        if let text = TrayFiles.badge(item.name, isDirectory: info?.isDirectory == true) {
            Text(text)
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 4).padding(.vertical, 1.5)
                .background(Color.black.opacity(0.6), in: Capsule())
                .offset(x: 4, y: 2)
        }
    }

    @ViewBuilder
    private var menu: some View {
        let targets = store.targets(for: item)
        let many = targets.count > 1
        Button(many ? "Open \(targets.count) Files" : "Open") { targets.forEach(store.open) }.disabled(isOffline)
        Button("Quick Look") { if !isSelected { store.select(item) }; store.quickLook() }.disabled(isOffline)
        Button("Show in Finder") { store.revealInFinder(targets) }.disabled(isOffline)
        Divider()
        Button(many ? "Copy \(targets.count) Files" : "Copy") { store.copyToPasteboard(targets) }
        Button(many ? "Compress \(targets.count) Files" : "Compress") { store.compress(targets) }.disabled(isBusy || isOffline)
        if !many {
            let type = UTType(filenameExtension: item.url.pathExtension)
            if type?.conforms(to: .image) == true {
                Divider()
                Button("Convert to PNG") { store.process(item, operation: .png) }.disabled(isBusy)
                Button("Convert to JPEG") { store.process(item, operation: .jpeg) }.disabled(isBusy)
                if #available(macOS 14, *) {
                    Button("Remove Background") { store.process(item, operation: .removeBackground) }.disabled(isBusy)
                }
            }
            if type?.conforms(to: .image) == true || type?.conforms(to: .pdf) == true {
                Button("Copy Text") { store.copyText(item) }.disabled(isBusy)
                Button("Extract Text") { store.process(item, operation: .extractText) }.disabled(isBusy)
            }
        }
        Divider()
        Button("Share via AirDrop") { store.airDrop(targets) }.disabled(isOffline)
        ShareLink(items: targets.map(\.url)) { Text("Share") }
        if isOffline {
            Divider()
            Button("Locate") { store.locate(item) }
            Button("Remove Files on Disconnected Drives") { store.removeOffline() }
        }
        Divider()
        Button(many ? "Remove \(targets.count) from Tray" : "Remove from Tray", role: .destructive) {
            many ? store.removeSelected() : store.remove(item)
        }
    }
}

/// A native drag can carry every selected file, unlike SwiftUI's single provider.
private struct ShelfDragHandle: NSViewRepresentable {
    let store: ShelfStore
    let item: ShelfItem
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {
        view.store = store; view.item = item
        view.toolTip = item.name
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(item.url.lastPathComponent)
        view.setAccessibilityHelp("Select file. Space previews, Return opens; Delete removes it from the Tray, not from disk.")
    }
    final class DragView: NSView, NSDraggingSource {
        weak var store: ShelfStore?
        var item: ShelfItem?
        private var mouseStart: NSEvent?
        private var dragging = false
        override var acceptsFirstResponder: Bool { true }
        override func accessibilityPerformPress() -> Bool { guard let store, let item else { return false }; store.select(item); return true }
        override func mouseDown(with event: NSEvent) {
            guard let item, let store else { return }
            window?.makeFirstResponder(self)
            mouseStart = event
            if event.clickCount == 2 {
                if !store.offlineIDs.contains(item.id) { store.open(item) }
                return
            }
            if !store.selectedIDs.contains(item.id) || event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift) {
                store.select(item, extending: event.modifierFlags.contains(.command), range: event.modifierFlags.contains(.shift))
            }
        }
        override func mouseDragged(with event: NSEvent) {
            guard !dragging, let start = mouseStart, let store, hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y) > 4 else { return }
            let files = store.selectedItems.filter { !store.offlineIDs.contains($0.id) }
            guard !files.isEmpty else { return }
            dragging = true
            // The drag shows the thumbnails already on screen (no file reads here).
            let fallback = NSImage(systemSymbolName: "doc.fill", accessibilityDescription: nil) ?? NSImage()
            let origin = convert(event.locationInWindow, from: nil)
            let items = files.prefix(24).enumerated().map { index, file in
                let drag = NSDraggingItem(pasteboardWriter: file.url as NSURL)
                let image = store.previews[file.id]?.image ?? fallback
                let side: CGFloat = 56
                drag.setDraggingFrame(NSRect(x: origin.x - side / 2 + Double(index * 6), y: origin.y - side / 2 - Double(index * 6),
                                             width: side, height: side), contents: image)
                return drag
            }
            beginDraggingSession(with: Array(items), event: event, source: self)
        }
        override func mouseUp(with event: NSEvent) { mouseStart = nil }
        override func keyDown(with event: NSEvent) {
            guard let store else { return }
            switch event.keyCode {
            case 49: store.quickLook()
            case 36, 76: store.openSelected()
            case 53:
                if store.selectedIDs.isEmpty { super.keyDown(with: event) } else { store.select(nil) }
            case 123, 126: store.selectNext(-1)
            case 124, 125: store.selectNext(1)
            case 51, 117: store.removeSelected()
            default:
                if event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() {
                    switch key {
                    case "a": store.selectAll()
                    case "v": store.paste()
                    case "z": store.undoRemoval()
                    case "c": store.copyToPasteboard(store.selectedItems)
                    case "o": store.openSelected()
                    default: super.keyDown(with: event)
                    }
                } else { super.keyDown(with: event) }
            }
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { dragging = false; mouseStart = nil }
    }
}
