import SwiftUI

struct ClipboardWidget: View {
    @ObservedObject var monitor: ClipboardMonitor
    @State private var showingHistory = false
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var message: String?

    var body: some View {
        Button {
            showingHistory.toggle()
        } label: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingHistory, arrowEdge: .top) {
            historyList
        }
    }

    @ViewBuilder
    private var content: some View {
        if let latest = monitor.entries.first {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 9))
                    Text("CLIPBOARD · \(monitor.entries.count)")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.secondary)

                Text(latest.preview)
                    .font(.system(size: 10))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Text("Copy something to build history")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Clipboard").font(.headline)
                Spacer()
                Menu {
                    Button("Clear Recent Clips") { monitor.clear(keepingFavorites: true) }
                    Button("Clear All, Including Favorites", role: .destructive) { monitor.clear() }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Clipboard actions")
            }
            TextField("Search clipboard", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("clipboard.search")
            Toggle("Favorites only", isOn: $favoritesOnly)
                .toggleStyle(.checkbox)
            let matches = monitor.matching(query, favoritesOnly: favoritesOnly)
            if matches.isEmpty {
                Text(monitor.entries.isEmpty ? "Copy text to start your history." : "No matching clips.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 14)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(matches) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Button {
                                    monitor.copyToPasteboard(entry)
                                    showingHistory = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.preview).font(.system(size: 11)).lineLimit(3)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(entry.date, format: .dateTime.hour().minute())
                                            .font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Button {
                                    message = monitor.toggleFavorite(entry) ? nil : "Favorite limit reached (50)."
                                } label: {
                                    Image(systemName: entry.isFavorite ? "star.fill" : "star")
                                }.buttonStyle(.plain)
                                    .accessibilityLabel(entry.isFavorite ? "Unfavorite clip" : "Favorite clip")
                                Button { monitor.remove(entry) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain).accessibilityLabel("Remove clip")
                            }
                            .padding(8)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.frame(maxHeight: 280)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            Text("History and favorites stay in memory and clear when MacSpaces quits.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 340)
    }
}
