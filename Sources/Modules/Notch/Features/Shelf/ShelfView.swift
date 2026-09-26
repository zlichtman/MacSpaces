import SwiftUI
import UniformTypeIdentifiers

/// Drag-and-drop file staging area shown in the expanded nook.
@MainActor
struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @Binding var isDropTargeted: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Group {
            if store.items.isEmpty {
                emptyState
            } else {
                itemGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            shape
                .fill(ThemeStore.shared.accent.opacity(isDropTargeted ? 0.08 : 0))
                .overlay {
                    shape
                        .strokeBorder(style: StrokeStyle(
                            lineWidth: isDropTargeted ? 2 : 1.5,
                            dash: isDropTargeted ? [7, 4] : [5, 4]
                        ))
                        .foregroundStyle(isDropTargeted ? ThemeStore.shared.accent : Color.primary.opacity(0.15))
                }
        }
        .animation(Design.hoverAnimation, value: isDropTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            let accepted = store.handleDrop(providers: providers)
            if accepted { Haptics.drop() }
            return accepted
        }
        .onAppear { store.pruneMissingItems() }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(isDropTargeted ? ThemeStore.shared.accent : Color.secondary)
                .scaleEffect(isDropTargeted && !ThemeStore.shared.reduceMotion ? 1.14 : 1)
                .offset(y: isDropTargeted && !ThemeStore.shared.reduceMotion ? 2 : 0)
            Text(isDropTargeted ? "Release to add to Tray" : "Drop files here to keep them handy")
                .font(.system(size: 11, weight: isDropTargeted ? .semibold : .regular))
                .foregroundStyle(isDropTargeted ? Color.primary : Color.secondary)
            Text("Drag them back out into any app")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .opacity(isDropTargeted ? 0 : 1)
        }
        .animation(Design.spring(), value: isDropTargeted)
    }

    private var itemGrid: some View {
        VStack(spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(store.items) { item in
                        ShelfItemView(
                            item: item,
                            store: store,
                            thumbnail: store.thumbnails[item.id],
                            isSelected: store.selectedItemID == item.id,
                            isBusy: store.busyItemIDs.contains(item.id)
                        )
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }

            if let item = store.selectedItem {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        let details = item.details
                        if !details.isEmpty {
                            Text(details)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    actionButton("Open", systemImage: "arrow.up.forward.app") { store.open(item) }
                    actionButton("Reveal in Finder", systemImage: "folder") { store.revealInFinder(item) }
                    actionButton("Copy", systemImage: "doc.on.doc") { store.copyToPasteboard(item) }
                    actionButton("Remove from Tray", systemImage: "xmark") {
                        Haptics.drop()
                        store.remove(item)
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 4)
                .padding(.vertical, 4)
                .background(ThemeStore.shared.notch.control, in: Capsule())
            }

            HStack {
                Text(store.items.count == 1 ? "1 item · Drag out to use anywhere" : "\(store.items.count) items · Drag out to use anywhere")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Haptics.drop()
                    store.removeAll()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(PremiumPressButtonStyle())
        .foregroundStyle(.secondary)
        .help(title)
        .accessibilityLabel(title)
    }
}

@MainActor
private struct ShelfItemView: View {
    let item: ShelfItem
    let store: ShelfStore
    let thumbnail: NSImage?
    let isSelected: Bool
    let isBusy: Bool
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            preview
                .frame(width: 44, height: 44)
            Text(item.name)
                .font(.system(size: 9))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 72)
        }
        .padding(6)
        .background(
            isSelected ? ThemeStore.shared.notch.selected : ThemeStore.shared.notch.control,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? ThemeStore.shared.notch.accent.opacity(0.75) : .clear,
                    lineWidth: 1
                )
        }
        .overlay(alignment: .topTrailing) {
            if isHovering && !isBusy {
                Button {
                    Haptics.drop()
                    store.remove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.primary, Color.black.opacity(0.55))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Remove from Tray")
                .offset(x: 4, y: -4)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        // Hovered tiles lift toward the pointer: a slight scale plus a soft
        // shadow reads as depth on the dark surface.
        .shadow(color: .black.opacity(isHovering ? 0.32 : 0), radius: 8, y: 4)
        .scaleEffect(isHovering && !ThemeStore.shared.reduceMotion ? 1.04 : 1)
        .offset(y: isHovering && !ThemeStore.shared.reduceMotion ? -1 : 0)
        .animation(Design.hoverAnimation, value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering { store.select(item) }
        }
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
        // Double-tap must win over single-tap; a plain `.onTapGesture` attached
        // first would swallow the second click and open would never fire.
        .gesture(
            TapGesture(count: 2).exclusively(before: TapGesture())
                .onEnded { value in
                    switch value {
                    case .first: store.open(item)
                    case .second: store.select(item)
                    }
                }
        )
        .contextMenu {
            Button("Open") { store.open(item) }
            Button("Reveal in Finder") { store.revealInFinder(item) }
            Divider()
            Button("Copy") { store.copyToPasteboard(item) }
            Button("Compress") { store.compress(item) }
                .disabled(isBusy)
            Divider()
            Button("Share via AirDrop") { store.airDrop(item) }
            ShareLink(item: item.url) {
                Text("Share…")
            }
            Divider()
            Button("Remove from Tray", role: .destructive) { store.remove(item) }
        }
    }

    /// Real content previews read as the file itself; a small corner radius
    /// and hairline keep light thumbnails from dissolving into the tile.
    @ViewBuilder
    private var preview: some View {
        ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .transition(.opacity)
            } else {
                Image(nsImage: item.icon)
                    .resizable()
            }

            if isBusy {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.45))
                ProgressView()
                    .controlSize(.small)
            }
        }
        .animation(Design.hoverAnimation, value: thumbnail != nil)
    }
}
