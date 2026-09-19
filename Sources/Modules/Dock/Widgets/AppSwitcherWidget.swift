import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Running apps with a click-to-activate icon row, like a mini ⌘-Tab.
struct AppSwitcherWidget: View {
    @StateObject private var model = RunningAppsModel()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.apps, id: \.processIdentifier) { app in
                    Button {
                        if DockStore.shared.windowPreviewsEnabled {
                            DockWindowPreviewController.shared.showWindows(
                                for: app
                            )
                        } else {
                            _ = app.activate(options: [])
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(nsImage: app.icon ?? NSWorkspace.shared.icon(for: .applicationBundle))
                                .resizable()
                                .frame(width: 30, height: 30)
                            Circle()
                                .fill(app.isActive ? Color.accentColor : .clear)
                                .frame(width: 3, height: 3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(
                        DockStore.shared.windowPreviewsEnabled
                            ? "Show \(app.localizedName ?? "app") windows"
                            : (app.localizedName ?? "")
                    )
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private final class RunningAppsModel: ObservableObject {
    @Published private(set) var apps: [NSRunningApplication] = []

    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            })
        }
    }

    private func refresh() {
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
    }
}
