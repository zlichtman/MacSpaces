import SwiftUI

struct ClipboardWidget: View {
    @ObservedObject var monitor: ClipboardMonitor
    var compact = false
    @State private var showingHistory = false
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var message: String?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .popover(isPresented: $showingHistory, arrowEdge: .top) {
                historyList
            }
    }

    @ViewBuilder
    private var content: some View {
        if monitor.entries.isEmpty {
            WidgetEmptyState(systemImage: "doc.on.clipboard", caption: "Copied text and links appear here", captionSize: 10)
                .padding(.horizontal, 10)
        } else if compact, let latest = monitor.entries.first {
            HStack(spacing: 6) {
                clipRow(latest, lines: 2)
                historyButton
            }
            .padding(.horizontal, 8)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(monitor.entries.prefix(3)) { entry in
                    clipRow(entry, lines: 1)
                }
                Spacer(minLength: 0)
                HStack {
                    Text(monitor.queueEnabled
                         ? (monitor.queueNeedsAccess ? "Queue needs Accessibility" : "\(monitor.queue.count) to paste")
                         : "\(monitor.entries.count) clip\(monitor.entries.count == 1 ? "" : "s")")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    Spacer()
                    Button { monitor.setQueueEnabled(!monitor.queueEnabled) } label: { Image(systemName: "list.number") }
                        .buttonStyle(WidgetChipStyle(prominent: monitor.queueEnabled, height: 20))
                        .help("Paste queue: copy several clips, then each ⌘V pastes the next")
                        .accessibilityLabel(monitor.queueEnabled ? "Turn off paste queue" : "Turn on paste queue")
                    Button("All") { showingHistory = true }
                        .buttonStyle(WidgetChipStyle(height: 20))
                        .help("Search clipboard history")
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private var historyButton: some View {
        Button { showingHistory = true } label: { Image(systemName: "list.bullet") }
            .buttonStyle(WidgetChipStyle(height: 22))
            .help("Search clipboard history")
    }

    private func clipRow(_ entry: ClipboardEntry, lines: Int) -> some View {
        ClipListRow(entry: entry, monitor: monitor, lines: lines)
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
            Toggle("Keep history after quitting", isOn: Binding(get: { monitor.persistenceEnabled }, set: { monitor.setPersistence($0) }))
                .toggleStyle(.checkbox)
            Text("Stored locally when enabled. Turning this off removes saved history from disk.").font(.caption2).foregroundStyle(.secondary)
            if let error = monitor.storageError { Text(error).font(.caption2).foregroundStyle(.red) }
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
