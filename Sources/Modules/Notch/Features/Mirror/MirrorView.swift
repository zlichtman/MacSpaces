import SwiftUI
@preconcurrency import AVFoundation

/// Live camera preview so you can check yourself before joining a call.
struct MirrorView: View {
    @StateObject private var camera = CameraController()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.primary.opacity(0.05))

            switch camera.status {
            case .running:
                CameraPreviewLayerView(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .scaleEffect(x: -1) // mirror horizontally, like a real mirror
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

    @Published var status: Status = .idle
    private var sessionStorage: AVCaptureSession?
    var session: AVCaptureSession {
        if let sessionStorage { return sessionStorage }
        let session = AVCaptureSession()
        sessionStorage = session
        return session
    }
    private let sessionQueue = DispatchQueue(label: "dev.opensource.macspaces.camera")
    private var desiredRunning = false
    private var generation = 0

    func startIfAuthorized() {
        guard !desiredRunning else { return }

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

        sessionQueue.async { [weak self] in
            var configured = true
            if session.inputs.isEmpty {
                session.beginConfiguration()
                session.sessionPreset = .medium
                if let device = AVCaptureDevice.default(for: .video),
                   let input = try? AVCaptureDeviceInput(device: device),
                   session.canAddInput(input) {
                    session.addInput(input)
                } else {
                    configured = false
                }
                session.commitConfiguration()
            }

            if configured, !session.isRunning {
                session.startRunning()
            }

            Task { @MainActor [weak self, configured] in
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
                self.status = .running
            }
        }
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
}

/// AppKit-backed view hosting an `AVCaptureVideoPreviewLayer`.
struct CameraPreviewLayerView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(previewLayer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer?.sublayers?.first?.frame = nsView.bounds
    }
}
