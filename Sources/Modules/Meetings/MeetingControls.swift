import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class MeetingControls: ObservableObject {
    static let shared = MeetingControls()
    enum Provider: String, CaseIterable, Identifiable {
        case zoom, meetSafari, meetChrome
        var id: String { rawValue }
        var title: String { switch self { case .zoom: return "Zoom"; case .meetSafari: return "Google Meet · Safari"; case .meetChrome: return "Google Meet · Chrome" } }
    }
    @Published var provider: Provider = .zoom { didSet { microphoneMuted = nil; cameraOff = nil; problem = nil; busy = false; generation = UUID() } }
    @Published private(set) var microphoneMuted: Bool?
    @Published private(set) var cameraOff: Bool?
    @Published private(set) var busy = false
    @Published private(set) var problem: String?
    private var generation = UUID()
#if DEBUG
    func setPreview(muted: Bool?, cameraOff: Bool?, problem: String? = nil) {
        microphoneMuted = muted; self.cameraOff = cameraOff; self.problem = problem
    }
#endif
    func refresh() { perform("read") }
    func setMicrophone(muted: Bool) { perform(muted ? "mute" : "unmute") }
    func setCamera(off: Bool) { perform(off ? "cameraOff" : "cameraOn") }
    private func perform(_ action: String) {
        guard !busy else { return }
        generation = UUID(); let token = generation
        problem = nil; busy = true
        if provider == .zoom {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "us.zoom.xos").first, !app.isTerminated else {
                busy = false; microphoneMuted = nil; cameraOff = nil; problem = "Open a meeting in Zoom first."; return
            }
            guard AXIsProcessTrusted() else {
                let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
                busy = false; problem = "Allow Accessibility, then Connect again. MacSpaces controls Zoom only; it does not mute the whole Mac."
                return
            }
            let pid = app.processIdentifier
            Task { [weak self] in
                let result = await Task.detached { ZoomControls.read(pid: pid, action: action) }.value
                guard let self, self.generation == token else { return }
                self.busy = false
                self.microphoneMuted = result.muted; self.cameraOff = result.cameraOff; self.problem = result.problem
                if action != "read", result.problem == nil {
                    try? await Task.sleep(for: .milliseconds(600))
                    guard self.generation == token else { return }; self.refresh()
                }
            }
        } else {
            let appID = provider == .meetSafari ? "com.apple.Safari" : "com.google.Chrome"
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: appID).isEmpty else {
                busy = false; problem = "Open Google Meet in the selected browser first."; return
            }
            let script = Self.browserScript(safari: provider == .meetSafari)
            AppleScriptRunner.runHandler(script, name: "readmeeting", arguments: [.text(Self.meetScript(action: action))]) { [weak self] result in
                guard let self, self.generation == token else { return }
                self.busy = false
                guard !result.failed, let string = result.descriptor?.stringValue, let data = string.data(using: .utf8),
                      let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.microphoneMuted = nil; self.cameraOff = nil
                    self.problem = "Couldn't read Meet. Allow Automation and JavaScript from Apple Events for this browser, then Connect again."
                    return
                }
                self.microphoneMuted = value["muted"] as? Bool; self.cameraOff = value["cameraOff"] as? Bool
                self.problem = value["error"] as? String
                if action != "read", self.problem == nil {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(600))
                        guard let self, self.generation == token else { return }; self.refresh()
                    }
                }
            }
        }
    }
    nonisolated static func browserScript(safari: Bool) -> String {
        let getTab = safari ? "current tab of front window" : "active tab of front window"
        let execute = safari ? "do JavaScript js in page" : "execute page javascript js"
        let app = safari ? "com.apple.Safari" : "com.google.Chrome"
        return """
        on readmeeting(js)
            tell application id "\(app)"
                if (count of windows) is 0 then return "{\\"error\\":\\"Open a Google Meet call first.\\"}"
                set page to \(getTab)
                if URL of page does not start with "https://meet.google.com/" then return "{\\"error\\":\\"Select the Google Meet tab first.\\"}"
                return \(execute)
            end tell
        end readmeeting
        """
    }
    nonisolated static func meetScript(action: String) -> String {
        // Actions are a closed set, not user-provided JavaScript. Verify the origin again in-page.
        let allowed = ["read", "mute", "unmute", "cameraOff", "cameraOn"]
        let action = allowed.contains(action) ? action : "read"
        return """
        (() => {
          if (location.protocol !== 'https:' || location.hostname !== 'meet.google.com') return JSON.stringify({error:'Select the Google Meet call first.'});
          const buttons = [...document.querySelectorAll('button,[role="button"]')].filter(b => !b.disabled && b.getClientRects().length);
          const find = word => buttons.filter(b => new RegExp('^Turn (on|off) ' + word + '(\\\\b|\\\\s)', 'i').test(b.getAttribute('aria-label') || ''));
          const mic = find('microphone'), cam = find('camera');
          const state = arr => arr.length === 1 ? /^Turn on /i.test(arr[0].getAttribute('aria-label')) : null;
          const muted = state(mic), cameraOff = state(cam);
          if ('\(action)' !== 'read') {
            const isMic = ['mute','unmute'].includes('\(action)');
            const arr = isMic ? mic : cam, current = isMic ? muted : cameraOff;
            if (current === null) return JSON.stringify({error:'The meeting control is unavailable or ambiguous. Use Meet directly.'});
            const wanted = ['mute','cameraOff'].includes('\(action)');
            if (current !== wanted) arr[0].click();
          }
          return JSON.stringify({muted,cameraOff,error:muted === null && cameraOff === null ? 'No supported meeting controls found. Join the call first; English control labels are currently required.' : null});
        })()
        """
    }
}

private enum ZoomControls {
    struct State: Sendable { var muted: Bool?; var cameraOff: Bool?; var problem: String? }
    static func read(pid: pid_t, action: String) -> State {
        guard let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == "us.zoom.xos", !app.isTerminated else {
            return State(problem: "Zoom closed. Connect again.")
        }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.2)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXMenuBarAttribute as CFString, &bar) == .success, let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return State(problem: "Zoom's meeting menu is unavailable.") }
        var queue = [(unsafeBitCast(bar, to: AXUIElement.self), 0)], controls: [String: AXUIElement] = [:], visited = 0
        while !queue.isEmpty && visited < 400 {
            let (element, depth) = queue.removeFirst(); visited += 1
            var title: CFTypeRef?, role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            if role as? String == kAXMenuItemRole, let name = title as? String {
                let key = name.lowercased().filter { $0.isLetter }
                if ["muteaudio", "unmuteaudio", "startvideo", "stopvideo"].contains(key) { controls[key] = element }
            }
            if depth < 5 {
                var children: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success, let values = children as? [AXUIElement] {
                    queue += values.prefix(100).map { ($0, depth + 1) }
                }
            }
        }
        let muted: Bool? = controls["unmuteaudio"] != nil ? true : controls["muteaudio"] != nil ? false : nil
        let off: Bool? = controls["startvideo"] != nil ? true : controls["stopvideo"] != nil ? false : nil
        let keys = ["mute": "muteaudio", "unmute": "unmuteaudio", "cameraOff": "stopvideo", "cameraOn": "startvideo"]
        if let key = keys[action] {
            let already = action == "mute" ? muted == true : action == "unmute" ? muted == false : action == "cameraOff" ? off == true : off == false
            if !already {
                guard let element = controls[key] else { return State(muted: muted, cameraOff: off, problem: "That Zoom control is unavailable. Use Zoom directly.") }
                var enabled: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled) == .success, enabled as? Bool == true,
                      AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
                    return State(muted: muted, cameraOff: off, problem: "Zoom didn't accept the control. Check the meeting and try again.")
                }
            }
        }
        return State(muted: muted, cameraOff: off, problem: muted == nil && off == nil ? "Join a Zoom meeting first. English meeting menu labels are currently required." : nil)
    }
}

struct MeetingControlsView: View {
    @ObservedObject var model: MeetingControls
    @ObservedObject private var meetings = MeetingCountdown.shared
    @ObservedObject private var theme = ThemeStore.shared
    private var connected: Bool { model.microphoneMuted != nil || model.cameraOff != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Meeting controls").font(.system(size: 17, weight: .semibold))
                    Text("Your call, within reach.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Meeting app", selection: $model.provider) {
                    ForEach(MeetingControls.Provider.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 180)
                Button { model.refresh() } label: {
                    Label(model.busy ? "Connecting…" : connected ? "Refresh" : "Connect", systemImage: "arrow.clockwise")
                }.buttonStyle(WidgetChipStyle(height: 30)).disabled(model.busy)
            }
            HStack(spacing: 12) {
                control(title: "Microphone", symbol: model.microphoneMuted == true ? "mic.slash.fill" : "mic.fill",
                        state: model.microphoneMuted.map { $0 ? "Muted" : "On" } ?? "Not connected",
                        action: model.microphoneMuted == true ? "Unmute" : "Mute", available: model.microphoneMuted != nil) {
                    model.setMicrophone(muted: model.microphoneMuted != true)
                }
                control(title: "Camera", symbol: model.cameraOff == true ? "video.slash.fill" : "video.fill",
                        state: model.cameraOff.map { $0 ? "Off" : "On" } ?? "Not connected",
                        action: model.cameraOff == true ? "Start camera" : "Stop camera", available: model.cameraOff != nil) {
                    model.setCamera(off: model.cameraOff != true)
                }
            }
            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(connected ? "Connected to " + model.provider.title : "Open your call, then connect. Controls apply to the selected app.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let meeting = meetings.meeting, let url = meeting.meetingURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    HStack {
                        Image(systemName: "video.badge.waveform")
                        Text(meeting.title).lineLimit(1)
                        Spacer()
                        Text("Join call").fontWeight(.semibold)
                        Image(systemName: "arrow.up.right")
                    }
                }.buttonStyle(WidgetChipStyle(height: 34))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4).padding(.vertical, 8)
        .foregroundStyle(theme.nookForeground).tint(theme.notch.accent)
        .preferredColorScheme(theme.notch.colorScheme)
    }

    private func control(title: String, symbol: String, state: String, action: String,
                         available: Bool, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol).font(.system(size: 22, weight: .medium))
                    .foregroundStyle(available ? theme.notch.accent : theme.nookForeground.opacity(0.4))
                Spacer()
                Text(state).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(title).font(.system(size: 14, weight: .semibold))
            Button(action, action: perform).buttonStyle(WidgetChipStyle(height: 28))
                .disabled(model.busy || !available)
                .accessibilityLabel(action + ", " + title + " " + state)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.notch.control, in: RoundedRectangle(cornerRadius: 16))
    }
}
