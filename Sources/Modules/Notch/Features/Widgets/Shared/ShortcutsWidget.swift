import SwiftUI

struct ShortcutsWidget: View {
    @ObservedObject var service: ShortcutsService
    let compact: Bool
    @State private var showingAll = false

    var body: some View {
        Group {
            if service.isLoading && service.names.isEmpty {
                ProgressView()
                    .controlSize(.small)
            } else if service.names.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up")
                    Text(service.errorText ?? "No shortcuts yet")
                        .font(.system(size: 9))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(service.names.prefix(compact ? 3 : 4), id: \.self) { name in
                        shortcutButton(name)
                    }
                }
                .padding(.horizontal, 9)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onAppear { service.startIfNeeded() }
        .contextMenu {
            Button("Show All Shortcuts") { showingAll = true }
            Button("Refresh") { service.refresh() }
        }
        .popover(isPresented: $showingAll, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Shortcuts").font(.headline)
                    Spacer()
                    Button { service.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(service.names, id: \.self) { name in
                            shortcutButton(name)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .padding(14)
            .frame(width: 280)
        }
    }

    private func shortcutButton(_ name: String) -> some View {
        Button {
            service.run(name)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: service.runningName == name ? "progress.indicator" : "play.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(ThemeStore.shared.accent)
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(service.runningName != nil)
    }
}
