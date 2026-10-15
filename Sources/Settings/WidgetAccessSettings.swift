import SwiftUI
import AppKit
import AVFoundation
import EventKit
import CoreLocation
import ApplicationServices
import CoreBluetooth
import Contacts
import Carbon

/// Permission status for the widgets. Visiting this page never asks for
/// anything: each row reads its status quietly, and only a row's own button
/// asks macOS (or opens System Settings). Statuses re-read every couple of
/// seconds while the page is open, so changes made in System Settings show up
/// on their own.
struct WidgetAccessSettings: View {
    @StateObject private var model = PermissionStatusModel()
    @ObservedObject private var settings = NookSettings.shared

    private var enabledKinds: Set<NookWidgetKind> { Set(settings.profiles.flatMap(\.widgets)) }

    var body: some View {
        let inUse = PermissionKind.allCases.filter { !enabledKinds.isDisjoint(with: $0.usedBy) }
        let unused = PermissionKind.allCases.filter { enabledKinds.isDisjoint(with: $0.usedBy) }
        Group {
            SettingsCard("Used by your widgets", systemImage: "hand.raised") {
                HStack(alignment: .top) {
                    Text("macOS asks the first time a widget needs access, or set it up here now.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    RefreshButton("Refresh") { model.refresh() }
                        .buttonStyle(.borderless)
                }
                if inUse.isEmpty {
                    Text("Your widgets don't need any special access.").font(.system(size: 13)).padding(.vertical, 6)
                }
                ForEach(inUse) { row($0) }
            }
            if !unused.isEmpty {
                SettingsCard("Not used right now", systemImage: "moon.zzz") {
                    Text("These are only needed if you add the widgets listed.").font(.caption).foregroundStyle(.secondary)
                    ForEach(unused) { row($0).opacity(0.75) }
                }
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private func row(_ kind: PermissionKind) -> some View {
        PermissionRow(kind: kind, status: model.statuses[kind] ?? .notRequested) { model.setUp(kind) }
            .id("settings." + kind.title)
    }
}

enum PermissionKind: String, CaseIterable, Identifiable {
    case automation, accessibility, calendars, reminders, camera, location, bluetooth, fullDiskAccess, contacts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automation: return "Automation"
        case .accessibility: return "Accessibility"
        case .calendars: return "Calendars"
        case .reminders: return "Reminders"
        case .camera: return "Camera"
        case .location: return "Location"
        case .bluetooth: return "Bluetooth"
        case .fullDiskAccess: return "Full Disk Access"
        case .contacts: return "Contacts"
        }
    }

    var symbol: String {
        switch self {
        case .automation: return "gearshape.2"
        case .accessibility: return "list.number"
        case .calendars: return "calendar"
        case .reminders: return "checklist"
        case .camera: return "camera"
        case .location: return "location"
        case .bluetooth: return "headphones"
        case .fullDiskAccess: return "bubble.left.and.bubble.right"
        case .contacts: return "person.crop.circle"
        }
    }

    var usedBy: [NookWidgetKind] {
        switch self {
        case .automation: return [.media, .quickActions, .notifications]
        case .accessibility: return [.clipboard]
        case .calendars: return [.calendar]
        case .reminders: return [.todos]
        case .camera: return [.mirror]
        case .location: return [.weather]
        case .bluetooth: return [.battery]
        case .fullDiskAccess, .contacts: return [.notifications]
        }
    }

    var settingsURL: URL? {
        let pane: String
        switch self {
        case .automation: pane = "Privacy_Automation"
        case .accessibility: pane = "Privacy_Accessibility"
        case .calendars: pane = "Privacy_Calendars"
        case .reminders: pane = "Privacy_Reminders"
        case .camera: pane = "Privacy_Camera"
        case .location: pane = "Privacy_LocationServices"
        case .bluetooth: pane = "Privacy_Bluetooth"
        case .fullDiskAccess: pane = "Privacy_AllFiles"
        case .contacts: pane = "Privacy_Contacts"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
    }
}

enum PermissionState: Hashable {
    case granted
    /// macOS hasn't asked yet; the row's button asks now.
    case notRequested
    /// Turned off, or (Full Disk Access) only settable in System Settings.
    case notGranted

    var title: String {
        switch self {
        case .granted: return "Allowed"
        case .notRequested: return "Allow…"
        case .notGranted: return "Open Settings"
        }
    }

    var symbol: String {
        switch self {
        case .granted: return "checkmark.circle.fill"
        case .notRequested: return "hand.raised"
        case .notGranted: return "arrow.up.forward.app"
        }
    }

    var color: Color {
        switch self {
        case .granted: return .green
        case .notRequested: return Color(red: 0.10, green: 0.91, blue: 0.65)
        case .notGranted: return .orange
        }
    }
}

/// Reads and requests the permissions the widgets use.
@MainActor
final class PermissionStatusModel: ObservableObject {
    @Published private(set) var statuses: [PermissionKind: PermissionState] = [:]

    /// Apps the widgets script: Media (Music, Spotify), Quick actions
    /// (System Events, Finder) and Messages (Messages, System Events).
    nonisolated static let automationTargets = ["com.apple.Music", "com.spotify.client", "com.apple.systemevents",
                                                "com.apple.finder", "com.apple.MobileSMS"]
    private static let locationManager = CLLocationManager()
    private static let eventStore = EKEventStore()
    private static var bluetoothManager: CBCentralManager?
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var slowReadInFlight = false

    init() { readQuickStatuses() }

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
    }

    func refresh() {
        readQuickStatuses()
        // Apple Events consent and file access talk to other processes, so
        // they're read off the main thread.
        guard !slowReadInFlight else { return }
        slowReadInFlight = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let automation = Self.automationStatus(ask: false)
            let fullDisk = Self.fullDiskAccessStatus()
            Task { @MainActor in
                guard let self else { return }
                self.slowReadInFlight = false
                self.update(.automation, automation)
                self.update(.fullDiskAccess, fullDisk)
            }
        }
    }

    /// Asks macOS for the permission, or opens its System Settings pane when
    /// macOS won't ask again (turned off, or Full Disk Access).
    func setUp(_ kind: PermissionKind) {
        let status = statuses[kind] ?? .notRequested
        guard status == .notRequested, kind != .fullDiskAccess else {
            if let url = kind.settingsURL { NSWorkspace.shared.open(url) }
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let done: @Sendable () -> Void = { [weak self] in Task { @MainActor in self?.refresh() } }
        switch kind {
        case .automation:
            DispatchQueue.global(qos: .userInitiated).async {
                // macOS can only ask on behalf of an app that's running.
                if Self.automationStatus(ask: true) == .notRequested, let url = kind.settingsURL {
                    DispatchQueue.main.async { NSWorkspace.shared.open(url) }
                }
                done()
            }
        case .accessibility:
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        case .calendars:
            if #available(macOS 14.0, *) {
                Self.eventStore.requestFullAccessToEvents { _, _ in done() }
            } else {
                Self.eventStore.requestAccess(to: .event) { _, _ in done() }
            }
        case .reminders:
            if #available(macOS 14.0, *) {
                Self.eventStore.requestFullAccessToReminders { _, _ in done() }
            } else {
                Self.eventStore.requestAccess(to: .reminder) { _, _ in done() }
            }
        case .camera:
            AVCaptureDevice.requestAccess(for: .video) { _ in done() }
        case .location:
            Self.locationManager.requestWhenInUseAuthorization()
        case .bluetooth:
            // Creating a central manager is what makes macOS ask.
            if Self.bluetoothManager == nil { Self.bluetoothManager = CBCentralManager(delegate: nil, queue: nil) }
        case .contacts:
            CNContactStore().requestAccess(for: .contacts) { _, _ in done() }
        case .fullDiskAccess:
            break
        }
    }

    private func update(_ kind: PermissionKind, _ status: PermissionState) {
        if statuses[kind] != status { statuses[kind] = status }
    }

    private func readQuickStatuses() {
        update(.accessibility, AXIsProcessTrusted() ? .granted : .notRequested)
        update(.calendars, Self.eventStatus(.event))
        update(.reminders, Self.eventStatus(.reminder))
        update(.camera, Self.mediaStatus(AVCaptureDevice.authorizationStatus(for: .video)))
        update(.location, Self.locationStatus)
        update(.bluetooth, Self.bluetoothStatus)
        update(.contacts, Self.contactsStatus)
        if statuses[.automation] == nil { statuses[.automation] = .notRequested }
        if statuses[.fullDiskAccess] == nil { statuses[.fullDiskAccess] = .notGranted }
    }

    private static func mediaStatus(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notRequested
        default: return .notGranted
        }
    }

    private static func eventStatus(_ type: EKEntityType) -> PermissionState {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess, .authorized: return .granted
        case .notDetermined: return .notRequested
        default: return .notGranted
        }
    }

    private static var contactsStatus: PermissionState {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: return .granted
        case .notDetermined: return .notRequested
        default: return .notGranted
        }
    }

    private static var bluetoothStatus: PermissionState {
        switch CBCentralManager.authorization {
        case .allowedAlways: return .granted
        case .notDetermined: return .notRequested
        default: return .notGranted
        }
    }

    private static var locationStatus: PermissionState {
        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways: return .granted
        case .notDetermined: return .notRequested
        default: return .notGranted
        }
    }

    /// Apple Events consent for the running target apps: any app turned off
    /// wins, then any not asked yet. macOS only reports on running apps.
    nonisolated static func automationStatus(ask: Bool) -> PermissionState {
        var results: [OSStatus] = []
        for bundleID in automationTargets
        where !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            guard let target = NSAppleEventDescriptor(bundleIdentifier: bundleID).aeDesc else { continue }
            results.append(AEDeterminePermissionToAutomateTarget(target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask))
        }
        if results.contains(OSStatus(errAEEventNotPermitted)) { return .notGranted }
        if results.contains(OSStatus(errAEEventWouldRequireUserConsent)) { return .notRequested }
        return results.contains(noErr) ? .granted : .notRequested
    }

    /// Full Disk Access has no status API; the Messages database (or, before
    /// Messages has run, the user's privacy database) only opens with it.
    nonisolated static func fullDiskAccessStatus() -> PermissionState {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for path in ["Library/Messages/chat.db", "Library/Application Support/com.apple.TCC/TCC.db"] {
            let descriptor = open(home.appendingPathComponent(path).path, O_RDONLY)
            if descriptor >= 0 { close(descriptor); return .granted }
            if errno != ENOENT { return .notGranted }
        }
        return .notGranted
    }
}

private struct PermissionRow: View {
    let kind: PermissionKind
    let status: PermissionState
    let setUp: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title).font(.system(size: 13, weight: .medium))
                Text("Used by " + ListFormatter.localizedString(byJoining: kind.usedBy.map(\.title)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if status == .granted {
                Label(status.title, systemImage: status.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(status.color)
            } else {
                Button(action: setUp) {
                    Label(status.title, systemImage: status.symbol)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(status.color)
                .help(status == .notRequested ? "Ask macOS for \(kind.title) access now"
                                              : "Turn on \(kind.title) for MacSpaces in System Settings")
            }
        }
        .padding(.vertical, 3)
        .animation(.easeOut(duration: 0.2), value: status)
    }
}
