import SwiftUI
import UniformTypeIdentifiers

/// Drag-and-drop file staging area shown in the expanded nook.
struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @Binding var isDropTargeted: Bool

    var body: some View {
        Group {
            if store.items.isEmpty {
                emptyState
            } else {
                itemGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(isDropTargeted ? ThemeStore.shared.accent : Color.primary.opacity(0.15))
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            store.handleDrop(providers: providers)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop files here to keep them handy")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var itemGrid: some View {
        VStack(spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(store.items) { item in
                        ShelfItemView(
                            item: item,
                            store: store,
                            isSelected: store.selectedItemID == item.id
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }

            if let item = store.selectedItem {
                HStack(spacing: 8) {
                    Label(item.name, systemImage: "cursorarrow.click.2")
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Open") { store.open(item) }
                    Button("Reveal") { store.revealInFinder(item) }
                    Button(role: .destructive) { store.remove(item) } label: {
                        Image(systemName: "trash")
                    }
                    .help("Remove selected item")
                }
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(ThemeStore.shared.notch.control, in: Capsule())
            }

            HStack {
                Text("Point at a file to select it")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
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
}

private struct ShelfItemView: View {
    let item: ShelfItem
    let store: ShelfStore
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 44, height: 44)
            Text(item.name)
                .font(.system(size: 9))
                .lineLimit(2)
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
        .scaleEffect(isHovering ? 1.035 : 1)
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
            Button("Share via AirDrop") { store.airDrop(item) }
            Divider()
            Button("Remove from Shelf", role: .destructive) { store.remove(item) }
        }
    }
}
