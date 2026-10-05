import SwiftUI

/// The Nook's Tray page. With file baskets, a row of chips switches between the
/// Tray and each basket; files dropped on the page go to the one showing.
struct TrayPageView: View {
    @ObservedObject var tray: ShelfStore
    @Binding var isDropTargeted: Bool
    @ObservedObject private var baskets = BasketWindowController.shared
    @State private var selection: UUID?

    var body: some View {
        let selected = baskets.baskets.first { $0.id == selection }
        VStack(spacing: 8) {
            if !baskets.baskets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button { selection = nil } label: { Label("Tray", systemImage: "tray.fill") }
                            .buttonStyle(WidgetChipStyle(prominent: selected == nil, height: 26))
                        ForEach(baskets.baskets) { basket in
                            BasketChip(basket: basket, store: baskets.store(for: basket.id), selected: selected?.id == basket.id) {
                                selection = basket.id
                            }
                            .contextMenu {
                                Button("Show on Desktop") { baskets.show(basket.id) }
                                Divider()
                                Button("Remove Basket", role: .destructive) { baskets.remove(basket.id) }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let selected {
                ShelfView(store: baskets.store(for: selected.id), isDropTargeted: $isDropTargeted)
                    .id(selected.id)
            } else {
                ShelfView(store: tray, isDropTargeted: $isDropTargeted)
            }
        }
        .onAppear { baskets.loadCatalog() }
    }
}

private struct BasketChip: View {
    let basket: FileBasket
    @ObservedObject var store: ShelfStore
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 5) {
                Image(systemName: "tray.full")
                Text(basket.name).lineLimit(1)
                if !store.items.isEmpty {
                    Text("\(store.items.count)").monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(WidgetChipStyle(prominent: selected, height: 26))
        .help("\(basket.name): right-click to show it on the desktop or remove it")
    }
}
