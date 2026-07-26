import SwiftUI

struct ClipboardWidget: View {
    @ObservedObject var monitor: ClipboardMonitor
    @State private var showingHistory = false

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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Clipboard History")
                    .font(.headline)
                Spacer()
                Button("Clear") { monitor.clear() }
                    .disabled(monitor.entries.isEmpty)
            }

            if monitor.entries.isEmpty {
                Text("Nothing copied yet")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(monitor.entries) { entry in
                            Button {
                                monitor.copyToPasteboard(entry)
                                showingHistory = false
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.preview)
                                        .font(.system(size: 11))
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(entry.date, format: .dateTime.hour().minute())
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(6)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
