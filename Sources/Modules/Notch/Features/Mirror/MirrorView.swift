import SwiftUI
@preconcurrency import AVFoundation
import CoreMedia
import os

/// Live camera preview so you can check yourself before joining a call.
struct MirrorView: View {
    @ObservedObject private var camera = CameraController.shared
    @Environment(\.mirrorPresentationOwnerID) private var ownerID
    @State private var presentationID = UUID()
    @State private var isPresented = false
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
                        camera: camera, presentationID: presentationID, ownerID: ownerID ?? presentationID,
                        isPresented: isPresented, isMirrored: isMirrored
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
            case .interrupted:
                placeholder("video.slash", "Camera paused by another app.")
            case .unavailable:
                placeholder("video.slash", "No camera available.")
            case .failed(let message):
                VStack(spacing: 7) {
                    placeholder("video.slash", message)
                    Button("Try Again") { camera.retry() }.buttonStyle(.bordered).controlSize(.small)
                }
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
        .onAppear {
            isPresented = true
            camera.startIfAuthorized(id: presentationID, owner: ownerID ?? presentationID)
        }
        .onDisappear {
            isPresented = false
            camera.stop(id: presentationID)
        }
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

private struct MirrorPresentationOwnerKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}
extension EnvironmentValues {
    var mirrorPresentationOwnerID: UUID? {
        get { self[MirrorPresentationOwnerKey.self] }
        set { self[MirrorPresentationOwnerKey.self] = newValue }
    }
}

struct MirrorCameraOption: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let systemImage: String
}

enum MirrorCameraEvent: @unchecked Sendable {
    case prepared(Int, AVCaptureSession, [MirrorCameraOption], String?)
    case firstFrame(Int)
    case interrupted(Int)
    case resuming(Int)
    case unavailable(Int)
    case failed(Int, String)
}

protocol MirrorSessionDriving: AnyObject, Sendable {
    func configure(selectedID: String?, generation: Int, startRunning: Bool, forceDiscovery: Bool)
    func stop(generation: Int)
    func shutdown()
}

/// One controller/session for all Mirror presentations, including multiple displays.
/// The worker owns all discovery and session configuration; only view state is main-actor isolated.
@MainActor
final class CameraController: ObservableObject {
    static let shared = CameraController()
    enum Status: Equatable { case idle, starting, running, permissionRequired, denied, unavailable, interrupted, failed(String) }
    typealias CameraOption = MirrorCameraOption
    typealias WorkerFactory = (@escaping @Sendable (MirrorCameraEvent) -> Void) -> any MirrorSessionDriving

    @Published private(set) var status: Status = .idle
    @Published private(set) var availableCameras: [CameraOption] = []
    @Published private(set) var selectedCameraID: String?
    @Published private(set) var session: AVCaptureSession?
    var selectedCameraName: String { availableCameras.first { $0.id == selectedCameraID }?.name ?? "Default camera" }

    private let defaults: UserDefaults
    private let authorization: () -> AVAuthorizationStatus
    private let workerFactory: WorkerFactory
    private var workerStorage: (any MirrorSessionDriving)?
    private var consumers: [UUID: UUID] = [:]
    private var suppressed: Set<UUID> = []
    private var generation = 0
    private var deviceObservers: [NSObjectProtocol] = []
    private let previews = NSHashTable<CameraPreviewHostView>.weakObjects()
    private let selectedCameraKey = "mirror.selectedCameraID"

    init(defaults: UserDefaults = .standard,
         authorization: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .video) },
         workerFactory: WorkerFactory? = nil) {
        self.defaults = defaults
        self.authorization = authorization
        self.workerFactory = workerFactory ?? { CameraSessionWorker(event: $0) }
        selectedCameraID = defaults.string(forKey: selectedCameraKey)
        let center = NotificationCenter.default
        for name in [NSNotification.Name.AVCaptureDeviceWasConnected, .AVCaptureDeviceWasDisconnected] {
            deviceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshAvailableCameras() }
            })
        }
    }

    private var worker: any MirrorSessionDriving {
        if let workerStorage { return workerStorage }
        let value = workerFactory { [weak self] event in
            DispatchQueue.main.async { [weak self] in self?.receive(event) }
        }
        workerStorage = value
        return value
    }

    /// Configuration only: no permission prompt and no startRunning until a Mirror is visible.
    func prewarm() {
        guard consumers.isEmpty, authorization() == .authorized else { return }
        generation += 1
        worker.configure(selectedID: selectedCameraID, generation: generation, startRunning: false, forceDiscovery: false)
    }

    func startIfAuthorized(id: UUID, owner: UUID) {
        let alreadyVisible = !consumers.isEmpty
        consumers[id] = owner
        suppressed.remove(id)
        guard !alreadyVisible || status == .idle else { return }
        switch authorization() {
        case .authorized: configureVisible(forceDiscovery: false)
        case .notDetermined: status = .permissionRequired
        default: status = .denied
        }
    }

    func requestPermission() {
        guard !consumers.isEmpty else { return }
        guard authorization() == .notDetermined else { retry(); return }
        generation += 1
        let request = generation
        status = .starting
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self, self.generation == request, !self.consumers.isEmpty else { return }
                if granted { self.configureVisible(forceDiscovery: false) } else { self.status = .denied }
            }
        }
    }

    func retry() {
        guard !consumers.isEmpty else { return }
        guard authorization() == .authorized else { status = .denied; return }
        configureVisible(forceDiscovery: true)
    }

    func refreshAvailableCameras() {
        guard authorization() == .authorized else { return }
        if consumers.isEmpty {
            generation += 1
            worker.configure(selectedID: selectedCameraID, generation: generation, startRunning: false, forceDiscovery: true)
        } else { configureVisible(forceDiscovery: true) }
    }

    func selectCamera(_ option: CameraOption) {
        guard option.id != selectedCameraID else { return }
        selectedCameraID = option.id
        defaults.set(option.id, forKey: selectedCameraKey)
        if !consumers.isEmpty { configureVisible(forceDiscovery: false) }
    }

    private func configureVisible(forceDiscovery: Bool) {
        hidePreviews()
        generation += 1
        status = .starting
        worker.configure(selectedID: selectedCameraID, generation: generation, startRunning: true, forceDiscovery: forceDiscovery)
    }

    func isPresentationActive(_ id: UUID) -> Bool { consumers[id] != nil && !suppressed.contains(id) }
    func register(_ preview: CameraPreviewHostView) { previews.add(preview) }
    func unregister(_ preview: CameraPreviewHostView) { previews.remove(preview) }

    /// Called before the panel/page's removal transition, not after onDisappear.
    func hidePresentation(owner: UUID) {
        for (id, value) in consumers where value == owner { suppressed.insert(id) }
        for preview in previews.allObjects where preview.ownerID == owner { preview.detach() }
    }

    func endPresentation(owner: UUID) {
        hidePresentation(owner: owner)
        let ids = consumers.filter { $0.value == owner }.map(\.key)
        for id in ids { consumers[id] = nil; suppressed.remove(id) }
        stopIfUnused()
    }

    func stop(id: UUID) {
        for preview in previews.allObjects where preview.presentationID == id { preview.detach() }
        consumers[id] = nil
        suppressed.remove(id)
        stopIfUnused()
    }

    private func hidePreviews() { previews.allObjects.forEach { $0.detach() } }
    private func stopIfUnused() {
        guard consumers.isEmpty else { return }
        hidePreviews()
        generation += 1
        status = .idle
        workerStorage?.stop(generation: generation)
    }

    private func receive(_ event: MirrorCameraEvent) {
        switch event {
        case let .prepared(request, session, options, selection):
            guard request == generation else { return }
            if self.session !== session { self.session = session }
            if availableCameras != options { availableCameras = options }
            if selectedCameraID != selection {
                selectedCameraID = selection
                defaults.set(selection, forKey: selectedCameraKey)
            }
        case .firstFrame(let request):
            guard request == generation, !consumers.isEmpty, session != nil else { return }
            status = .running
        case .interrupted(let request):
            guard request == generation, !consumers.isEmpty else { return }
            hidePreviews(); status = .interrupted
        case .resuming(let request):
            guard request == generation, !consumers.isEmpty else { return }
            status = .starting
        case .unavailable(let request):
            guard request == generation, !consumers.isEmpty else { return }
            hidePreviews(); status = .unavailable
        case .failed(let request, let message):
            guard request == generation, !consumers.isEmpty else { return }
            hidePreviews(); status = .failed(message)
        }
    }

    deinit {
        deviceObservers.forEach(NotificationCenter.default.removeObserver)
        workerStorage?.shutdown()
    }
}

/// Session, inputs, discovery cache and sample callbacks are confined to one queue.
final class CameraSessionWorker: NSObject, MirrorSessionDriving, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private struct Request { var generation = 0; var running = false }
    private let desired = OSAllocatedUnfairLock(initialState: Request())
    private let queue = DispatchQueue(label: "dev.opensource.MacSpaces.camera", qos: .userInitiated)
    private let event: @Sendable (MirrorCameraEvent) -> Void
    private let discover: @Sendable () -> [AVCaptureDevice]
    private var session: AVCaptureSession?
    private var output: AVCaptureVideoDataOutput?
    private var devices: [AVCaptureDevice] = []
    private var discoveredAt = Date.distantPast
    private var defaultDeviceID: String?
    private var selectedID: String?
    private var awaitingFrame = false
    private var frameGeneration = 0
    private var frameWaitID = 0
    private var interrupted = false
    private var resetAttempts = 0
    private var observers: [NSObjectProtocol] = []

    init(discover: @escaping @Sendable () -> [AVCaptureDevice] = { CameraSessionWorker.discoverVideoDevices() },
         event: @escaping @Sendable (MirrorCameraEvent) -> Void) {
        self.discover = discover
        self.event = event
    }

    func configure(selectedID: String?, generation: Int, startRunning: Bool, forceDiscovery: Bool) {
        desired.withLock { $0 = Request(generation: generation, running: startRunning) }
        queue.async { [self] in
            guard desired.withLock({ $0.generation == generation }) else { return }
            resetAttempts = 0
            awaitingFrame = false
            guard prepare(selectedID: selectedID, forceDiscovery: forceDiscovery, request: generation) else {
                if session?.isRunning == true { session?.stopRunning() }
                return
            }
            guard startRunning, desired.withLock({ $0.generation == generation && $0.running }), let session,
                  !session.inputs.isEmpty, output != nil else { return }
            interrupted = false
            awaitFrames(generation)
            if !session.isRunning { session.startRunning() }
        }
    }

    private func prepare(selectedID requestedID: String?, forceDiscovery: Bool, request: Int) -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        if forceDiscovery || Date().timeIntervalSince(discoveredAt) > 30 {
            devices = discover()
            defaultDeviceID = devices.isEmpty ? nil : AVCaptureDevice.default(for: .video)?.uniqueID
            discoveredAt = Date()
        }
        let options = devices.map { MirrorCameraOption(id: $0.uniqueID, name: $0.localizedName, systemImage: Self.systemImage(for: $0)) }
        let device = devices.first { $0.uniqueID == requestedID }
            ?? devices.first { $0.uniqueID == defaultDeviceID } ?? devices.first
        let session = captureSession()
        guard let device else { event(.prepared(request, session, options, nil)); event(.unavailable(request)); return false }
        if selectedID != device.uniqueID || session.inputs.isEmpty {
            do {
                let input = try AVCaptureDeviceInput(device: device)
                session.beginConfiguration()
                if session.canSetSessionPreset(.medium) { session.sessionPreset = .medium }
                let old = session.inputs
                old.forEach(session.removeInput)
                guard session.canAddInput(input) else {
                    old.forEach { if session.canAddInput($0) { session.addInput($0) } }
                    session.commitConfiguration()
                    event(.failed(request, "This camera could not be opened.")); return false
                }
                session.addInput(input)
                if output == nil {
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.setSampleBufferDelegate(self, queue: queue)
                    if session.canAddOutput(output) { session.addOutput(output); self.output = output }
                }
                session.commitConfiguration()
                selectedID = device.uniqueID
            } catch { event(.failed(request, "This camera could not be opened.")); return false }
        }
        event(.prepared(request, session, options, selectedID))
        guard output != nil else { event(.failed(request, "Camera video could not be configured.")); return false }
        return true
    }

    private func captureSession() -> AVCaptureSession {
        if let session { return session }
        let value = AVCaptureSession()
        session = value
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: value, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in self?.runtimeError() }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: value, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, self.desired.withLock({ $0.running }) else { return }
                self.interrupted = true; self.awaitingFrame = false
                self.event(.interrupted(self.desired.withLock { $0.generation }))
            }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: value, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, self.desired.withLock({ $0.running }), let session = self.session else { return }
                let request = self.desired.withLock { $0.generation }
                self.interrupted = false
                self.event(.resuming(request))
                self.awaitFrames(request)
                if !session.isRunning { session.startRunning() }
            }
        })
        return value
    }

    private func runtimeError() {
        let request = desired.withLock { $0 }
        guard request.running else { return }
        awaitingFrame = false
        if resetAttempts == 0, let session, !session.isRunning {
            resetAttempts += 1
            event(.resuming(request.generation))
            awaitFrames(request.generation)
            session.startRunning()
        } else {
            if session?.isRunning == true { session?.stopRunning() }
            event(.failed(request.generation, "Camera stopped. Try again."))
        }
    }

    private func awaitFrames(_ generation: Int) {
        awaitingFrame = true
        frameGeneration = generation
        frameWaitID += 1
        let waitID = frameWaitID
        queue.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.frameWaitID == waitID, self.awaitingFrame, !self.interrupted,
                  self.desired.withLock({ $0.running && $0.generation == generation }) else { return }
            self.awaitingFrame = false
            if self.session?.isRunning == true { self.session?.stopRunning() }
            self.event(.failed(generation, "No video arrived from the camera. Try again."))
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard awaitingFrame, !interrupted, CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
        let request = desired.withLock { $0 }
        guard request.running, request.generation == frameGeneration else { return }
        awaitingFrame = false
        event(.firstFrame(request.generation))
    }

    func stop(generation: Int) {
        desired.withLock { $0 = Request(generation: generation, running: false) }
        queue.async { [self] in
            awaitingFrame = false
            if session?.isRunning == true { session?.stopRunning() }
        }
    }

    func shutdown() {
        desired.withLock { $0.running = false; $0.generation += 1 }
        queue.async { [self] in
            if session?.isRunning == true { session?.stopRunning() }
            observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        }
    }

    private static func discoverVideoDevices() -> [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) { types = [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera] }
        else { types = [.builtInWideAngleCamera, .externalUnknown] }
        var ids: Set<String> = []
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
            .filter { ids.insert($0.uniqueID).inserted }
    }

    private static func systemImage(for device: AVCaptureDevice) -> String {
        if #available(macOS 14.0, *) {
            if device.deviceType == .continuityCamera { return "iphone" }
            if device.deviceType == .deskViewCamera { return "rectangle.inset.filled.and.person.filled" }
        }
        return device.deviceType == .builtInWideAngleCamera ? "laptopcomputer" : "video"
    }
}

struct CameraPreviewLayerView: NSViewRepresentable {
    @ObservedObject var camera: CameraController
    let presentationID: UUID
    let ownerID: UUID
    let isPresented: Bool
    let isMirrored: Bool

    func makeNSView(context: Context) -> CameraPreviewHostView {
        let view = CameraPreviewHostView()
        view.camera = camera; view.presentationID = presentationID; view.ownerID = ownerID
        camera.register(view)
        return view
    }

    func updateNSView(_ view: CameraPreviewHostView, context: Context) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard isPresented, camera.isPresentationActive(presentationID), camera.status == .running, let session = camera.session else {
            view.detach(); return
        }
        if view.preview.session !== session { view.preview.session = session }
        view.preview.isHidden = false
        view.preview.frame = view.bounds
        if let connection = view.preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        view.preview.setAffineTransform(isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
    }

    static func dismantleNSView(_ view: CameraPreviewHostView, coordinator: ()) {
        view.detach()
        view.camera?.unregister(view)
    }
}

final class CameraPreviewHostView: NSView {
    let preview = AVCaptureVideoPreviewLayer()
    weak var camera: CameraController?
    var presentationID = UUID()
    var ownerID = UUID()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 12
        preview.videoGravity = .resizeAspectFill
        preview.isHidden = true
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        preview.frame = bounds
        CATransaction.commit()
    }
    func detach() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        preview.isHidden = true
        preview.session = nil
        CATransaction.commit()
    }
}
