import SwiftUI
import AppKit

/// Unread count from Apple Mail via AppleScript (macOS shows a one-time
/// automation prompt). Click to open Mail. Only polls while Mail is running.
struct MailWidget: View {
    @StateObject private var model = MailModel()

    var body: some View {
        Button {
            model.openMail()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: model.unreadCount > 0 ? "envelope.badge" : "envelope")
                    .font(.system(size: 16))
                    .foregroundStyle(model.unreadCount > 0 ? .blue : .secondary)

                if let status = model.statusText {
                    Text(status)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("\(model.unreadCount)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("unread")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

@MainActor
private final class MailModel: ObservableObject {
    @Published private(set) var unreadCount = 0
    /// Non-nil when the count is unavailable (Mail closed, access denied).
    @Published private(set) var statusText: String? = "Open Mail to see unread"

    private var timer: Timer?
    private var refreshInFlight = false

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }

    private var isMailRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty
    }

    private func refresh() {
        guard isMailRunning else {
            statusText = "Open Mail to see unread"
            refreshInFlight = false
            return
        }
        // A slow Mail, or the first automation prompt, keeps the script running
        // for seconds. Overlapping requests would just queue up behind it.
        guard !refreshInFlight else { return }
        refreshInFlight = true

        AppleScriptRunner.run(
            "tell application \"Mail\" to unread count of inbox"
        ) { [weak self] result in
            guard let self else { return }
            refreshInFlight = false
            if let descriptor = result.descriptor, !result.failed {
                unreadCount = Int(descriptor.int32Value)
                statusText = nil
            } else {
                statusText = "Allow automation for Mail in System Settings"
            }
        }
    }

    func openMail() {
        if let url = URL(string: "message://") {
            NSWorkspace.shared.open(url)
        }
    }
}
