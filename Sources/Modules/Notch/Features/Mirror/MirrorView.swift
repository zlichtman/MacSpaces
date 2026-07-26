import SwiftUI
@preconcurrency import AVFoundation

/// Live camera preview so you can check yourself before joining a call.
struct MirrorView: View {
    @StateObject private var camera = CameraController()
    @AppStorage("mirrorPreviewIsFlipped") private var isMirrored = true
    @State private var isHoveringPreview = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.primary.opacity(0.05))

            switch camera.status {
            case .running:
                ZStack {
                    CameraPreviewLayerView(
                        session: camera.session,
                        isMirrored: isMirrored
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { isMirrored.toggle() }

                    HStack(spacing: 8) {
                        cameraPicker
                        Spacer(minLength: 0)
                        Button {
                            isMirrored.toggle()
                        } label: {
                            previewControl("arrow.left.and.right")
                        }
                        .buttonStyle(.plain)
                        .help(
                            isMirrored
                                ? "Show camera orientation"
                                : "Show mirrored orientation"
                        )
                    }
                    .foregroundStyle(.primary)
                    .padding(9)
                    .opacity(isHoveringPreview ? 1 : 0.68)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onHover { isHoveringPreview = $0 }
            case .permissionRequired:
                permissionPrompt
            case .denied:
                placeholder("video.slash", "Camera access denied.\nEnable it in System Settings → Privacy.")
            case .idle:
                placeholder("web.camera", "Mirror")
            case .starting:
                placeholder("web.camera", "Starting camera…")
            }
        }
        .task {
            // AVFoundation can briefly contend with SwiftUI's render pass.
            // Always finish the surface transition first, then start preview
            // work without ever feeding camera state back into layout.
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            camera.startIfAuthorized()
        }
        .onDisappear { camera.stop() }
    }

    private var cameraPicker: some View {
        Menu {
            ForEach(camera.availableCameras) { option in
                Button {
                    camera.selectCamera(option)
                } label: {
                    Label(
                        option.name,
                        systemImage: option.id == camera.selectedCameraID
                            ? "checkmark"
                            : option.systemImage
                    )
                }
            }

            Divider()
            Button {
                camera.refreshAvailableCameras()
            } label: {
                Label("Refresh Cameras", systemImage: "arrow.clockwise")
            }
        } label: {
            previewControl("video.fill")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Camera: \(camera.selectedCameraName)")
    }

    private func previewControl(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .frame(width: 25, height: 25)
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.6)
            }
    }

    private var permissionPrompt: some View {
        VStack(spacing: 7) {
            Image(systemName: "web.camera")
                .font(.system(size: 22, weight: .light))
            Text("Camera access is needed for Mirror.")
                .font(.system(size: 10))
            Button("Allow Camera") {
                camera.requestPermission()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .foregroundStyle(.secondary)
    }

    private func placeholder(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
            Text(text)
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }
}

@MainActor
final class CameraController: ObservableObject {
    enum Status {
        case idle, starting, running, permissionRequired, denied
    }

    struct CameraOption: Identifiable, Equatable {
        let id: String
        let name: String
        let systemImage: String
    }

    @Published var status: Status = .idle
    @Published private(set) var availableCameras: [CameraOption] = []
    @Published private(set) var selectedCameraID: String?

    var selectedCameraName: String {
        availableCameras.first { $0.id == selectedCameraID }?.name ?? "Default camera"
    }

    private var sessionStorage: AVCaptureSession?
    var session: AVCaptureSession {
        if let sessionStorage { return sessionStorage }
        let session = AVCaptureSession()
        sessionStorage = session
        return session
    }
    private let sessionQueue = DispatchQueue(label: "dev.opensource.macspaces.camera")
    private let selectedCameraKey = "mirror.selectedCameraID"
    private var deviceObservers: [NSObjectProtocol] = []
    private var desiredRunning = false
    private var generation = 0

    init() {
        selectedCameraID = UserDefaults.standard.string(forKey: selectedCameraKey)
        refreshAvailableCameras(reconfigureIfNeeded: false)

        let center = NotificationCenter.default
        deviceObservers = [
            center.addObserver(
                forName: .AVCaptureDeviceWasConnected,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshAvailableCameras()
                }
            },
            center.addObserver(
                forName: .AVCaptureDeviceWasDisconnected,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshAvailableCameras()
                }
            },
        ]
    }

    func refreshAvailableCameras(reconfigureIfNeeded: Bool = true) {
        let devices = Self.discoverVideoDevices()
        availableCameras = devices.map {
            CameraOption(
                id: $0.uniqueID,
                name: $0.localizedName,
                systemImage: Self.systemImage(for: $0)
            )
        }

        let previousSelection = selectedCameraID
        if !devices.contains(where: { $0.uniqueID == selectedCameraID }) {
            selectedCameraID = AVCaptureDevice.default(for: .video)?.uniqueID
                ?? devices.first?.uniqueID
        }
        if let selectedCameraID {
            UserDefaults.standard.set(selectedCameraID, forKey: selectedCameraKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedCameraKey)
        }

        if reconfigureIfNeeded,
           desiredRunning,
           previousSelection != selectedCameraID {
            restartWithSelection()
        }
    }

    func selectCamera(_ option: CameraOption) {
        guard option.id != selectedCameraID else { return }
        selectedCameraID = option.id
        UserDefaults.standard.set(option.id, forKey: selectedCameraKey)
        if desiredRunning {
            restartWithSelection()
        }
    }

    func startIfAuthorized() {
        guard !desiredRunning else { return }

        refreshAvailableCameras(reconfigureIfNeeded: false)

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            desiredRunning = true
            generation += 1
            let requestGeneration = generation
            status = .starting
            configureAndRun(for: requestGeneration)
        case .notDetermined:
            status = .permissionRequired
        case .denied, .restricted:
            status = .denied
        @unknown default:
            status = .denied
        }
    }

    func requestPermission() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else {
            startIfAuthorized()
            return
        }
        generation += 1
        let requestGeneration = generation
        status = .starting
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                guard let self, self.generation == requestGeneration else { return }
                if granted {
                    self.startIfAuthorized()
                } else {
                    self.status = .denied
                }
            }
        }
    }

    private func configureAndRun(for requestGeneration: Int) {
        guard desiredRunning, generation == requestGeneration else { return }
        let session = session
        let sessionQueue = sessionQueue
        let requestedDeviceID = selectedCameraID

        sessionQueue.async { [weak self] in
            let devices = Self.discoverVideoDevices()
            let device = devices.first { $0.uniqueID == requestedDeviceID }
                ?? AVCaptureDevice.default(for: .video)
                ?? devices.first
            var configured = false
            var configuredDeviceID: String?

            session.beginConfiguration()
            session.sessionPreset = .medium
            let previousInputs = session.inputs
            previousInputs.forEach(session.removeInput)
            if let device,
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
                configured = true
                configuredDeviceID = device.uniqueID
            } else {
                // A hot-unplug can race this configuration pass. Preserve the
                // last working input until the connection observer retries.
                previousInputs.forEach {
                    if session.canAddInput($0) { session.addInput($0) }
                }
            }
            session.commitConfiguration()

            if configured, !session.isRunning {
                session.startRunning()
            }

            Task { @MainActor [weak self, configured, configuredDeviceID] in
                guard let self else {
                    sessionQueue.async {
                        if session.isRunning { session.stopRunning() }
                    }
                    return
                }
                guard configured,
                      self.desiredRunning,
                      self.generation == requestGeneration else {
                    sessionQueue.async {
                        if session.isRunning { session.stopRunning() }
                    }
                    if !configured, self.generation == requestGeneration {
                        self.desiredRunning = false
                        self.status = .denied
                    }
                    return
                }
                if let configuredDeviceID,
                   self.selectedCameraID != configuredDeviceID {
                    self.selectedCameraID = configuredDeviceID
                    UserDefaults.standard.set(
                        configuredDeviceID,
                        forKey: self.selectedCameraKey
                    )
                }
                self.status = .running
            }
        }
    }

    private func restartWithSelection() {
        generation += 1
        let requestGeneration = generation
        // Keep the current preview visible while swapping an already-running
        // capture input. The session reconfiguration is quick and does not need
        // to replace the mirror with a second loading state.
        if status != .running {
            status = .starting
        }
        configureAndRun(for: requestGeneration)
    }

    nonisolated private static func discoverVideoDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .external,
                .continuityCamera,
                .deskViewCamera,
            ],
            mediaType: .video,
            position: .unspecified
        )
        .devices
        .reduce(into: [AVCaptureDevice]()) { result, device in
            guard !result.contains(where: { $0.uniqueID == device.uniqueID }) else {
                return
            }
            result.append(device)
        }
    }

    nonisolated private static func systemImage(for device: AVCaptureDevice) -> String {
        if device.deviceType == .continuityCamera {
            return "iphone"
        }
        if device.deviceType == .deskViewCamera {
            return "rectangle.inset.filled.and.person.filled"
        }
        if device.deviceType == .builtInWideAngleCamera {
            return "laptopcomputer"
        }
        return "video"
    }

    func stop() {
        desiredRunning = false
        generation += 1
        status = .idle
        guard let session = sessionStorage else { return }
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    deinit {
        deviceObservers.forEach(NotificationCenter.default.removeObserver)
    }
}

/// AppKit-backed view hosting an `AVCaptureVideoPreviewLayer`.
struct CameraPreviewLayerView: NSViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        configureMirroring(for: previewLayer)
        view.layer?.addSublayer(previewLayer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let previewLayer = nsView.layer?.sublayers?.first as? AVCaptureVideoPreviewLayer else {
            return
        }
        previewLayer.frame = nsView.bounds
        configureMirroring(for: previewLayer)
    }

    /// Keep the capture connection unmirrored and apply the user's orientation
    /// directly to the preview layer. Some external cameras ignore
    /// `isVideoMirrored`, while an affine layer transform is deterministic for
    /// built-in and USB cameras alike and does not alter the captured stream.
    private func configureMirroring(for previewLayer: AVCaptureVideoPreviewLayer) {
        if let connection = previewLayer.connection,
           connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        previewLayer.setAffineTransform(
            isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        )
    }
}
