import AVFoundation
import Combine
import SwiftUI

struct CameraDeviceOption: Identifiable, Equatable {
    let uniqueID: String
    let localizedName: String

    var id: String {
        uniqueID
    }
}

@MainActor
final class CameraService: ObservableObject, @unchecked Sendable {
    enum State: Equatable {
        case checkingPermission
        case ready
        case permissionDenied
        case cameraUnavailable
        case configurationFailed(String)
    }

    @Published private(set) var state: State = .checkingPermission
    @Published private(set) var availableVideoDevices: [CameraDeviceOption] = []

    var session: AVCaptureSession {
        sessionRunner.session
    }

    private let settingsStore: SettingsStore
    private let permissionService: CameraPermissionService
    private let lifecycleToken = CameraLifecycleToken()
    private let sessionRunner = CameraSessionRunner()
    private var settingsCancellables = Set<AnyCancellable>()
    private var isActive = false

    init(
        settingsStore: SettingsStore,
        permissionService: CameraPermissionService = CameraPermissionService()
    ) {
        self.settingsStore = settingsStore
        self.permissionService = permissionService

        refreshAvailableVideoDevices()
        observeSettings()
    }

    deinit {
        lifecycleToken.advance()
        sessionRunner.stop()
    }

    func start() {
        assertMainThread()

        isActive = true
        refreshAvailableVideoDevices()
        let generation = lifecycleToken.advance()

        switch permissionService.currentState {
        case .authorized:
            state = .checkingPermission
            startSession(generation: generation)
        case .notDetermined:
            state = .checkingPermission
            permissionService.requestAccess { [self] permissionState in
                Task { @MainActor in
                    handle(permissionState, generation: generation)
                }
            }
        case .denied, .restricted:
            state = .permissionDenied
        }
    }

    func stop() {
        assertMainThread()
        isActive = false
        invalidateAndStopSession()
    }

    func refreshAvailableVideoDevices() {
        availableVideoDevices = CameraDeviceDiscovery.availableVideoDevices()
    }

    private func observeSettings() {
        settingsStore.$selectedCameraUniqueID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.restartForSelectedCameraChange()
            }
            .store(in: &settingsCancellables)

    }

    private func restartForSelectedCameraChange() {
        assertMainThread()
        refreshAvailableVideoDevices()

        guard isActive else {
            return
        }

        invalidateAndStopSession()
        start()
    }

    private func invalidateAndStopSession() {
        lifecycleToken.advance()
        sessionRunner.stop()
    }

    private func handle(_ permissionState: CameraPermissionService.PermissionState, generation: Int) {
        assertMainThread()

        guard lifecycleToken.isCurrent(generation) else {
            return
        }

        switch permissionState {
        case .authorized:
            startSession(generation: generation)
        case .notDetermined:
            state = .checkingPermission
        case .denied, .restricted:
            state = .permissionDenied
        }
    }

    private func startSession(generation: Int) {
        sessionRunner.start(
            selectedDeviceUniqueID: selectedDeviceUniqueID,
            generation: generation,
            lifecycleToken: lifecycleToken
        ) { [self] generation, result in
            Task { @MainActor in
                guard lifecycleToken.isCurrent(generation) else {
                    return
                }

                switch result {
                case .ready:
                    state = .ready
                    refreshAvailableVideoDevices()
                case .cameraUnavailable:
                    state = .cameraUnavailable
                    refreshAvailableVideoDevices()
                case .configurationFailed(let message):
                    state = .configurationFailed(message)
                    refreshAvailableVideoDevices()
                }
            }
        }
    }

    private var selectedDeviceUniqueID: String? {
        settingsStore.selectedCameraUniqueID.isEmpty ? nil : settingsStore.selectedCameraUniqueID
    }

    private func assertMainThread() {
        assert(Thread.isMainThread, "CameraService must be driven from the main thread.")
    }
}

nonisolated final class CameraLifecycleToken: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0

    @discardableResult
    func advance() -> Int {
        lock.lock()
        defer {
            lock.unlock()
        }

        generation += 1
        return generation
    }

    func isCurrent(_ generation: Int) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }

        return self.generation == generation
    }
}

nonisolated final class CameraSessionRunner: @unchecked Sendable {
    enum StartResult: Sendable {
        case ready
        case cameraUnavailable
        case configurationFailed(String)
    }

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.brooksdubois.WindowPane.camera-session")
    private var isConfigured = false
    private var configuredSelectionID: String?

    func start(
        selectedDeviceUniqueID: String?,
        generation: Int,
        lifecycleToken: CameraLifecycleToken,
        completion: @escaping @Sendable (Int, StartResult) -> Void
    ) {
        sessionQueue.async { [self] in
            guard lifecycleToken.isCurrent(generation) else {
                return
            }

            do {
                try configureSessionIfNeeded(selectedDeviceUniqueID: selectedDeviceUniqueID)
            } catch {
                completion(generation, .configurationFailed(error.localizedDescription))
                return
            }

            guard isConfigured else {
                completion(generation, .cameraUnavailable)
                return
            }

            guard lifecycleToken.isCurrent(generation) else {
                return
            }

            if !session.isRunning {
                session.startRunning()
            }

            guard lifecycleToken.isCurrent(generation) else {
                return
            }

            completion(generation, .ready)
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            guard session.isRunning else {
                return
            }

            session.stopRunning()
        }
    }

    private func configureSessionIfNeeded(selectedDeviceUniqueID: String?) throws {
        guard !isConfigured || configuredSelectionID != selectedDeviceUniqueID else {
            return
        }

        let camera = resolvedCamera(selectedDeviceUniqueID: selectedDeviceUniqueID)

        guard let camera else {
            session.beginConfiguration()
            clearVideoInputs()
            session.commitConfiguration()
            isConfigured = false
            configuredSelectionID = selectedDeviceUniqueID
            return
        }

        let input = try AVCaptureDeviceInput(device: camera)

        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }

        session.sessionPreset = .high

        clearVideoInputs()

        guard session.canAddInput(input) else {
            isConfigured = false
            configuredSelectionID = nil
            return
        }

        session.addInput(input)
        isConfigured = true
        configuredSelectionID = selectedDeviceUniqueID
    }

    private func resolvedCamera(selectedDeviceUniqueID: String?) -> AVCaptureDevice? {
        guard let selectedDeviceUniqueID, !selectedDeviceUniqueID.isEmpty else {
            return AVCaptureDevice.default(for: .video)
        }

        return CameraDeviceDiscovery.device(uniqueID: selectedDeviceUniqueID)
    }

    private func clearVideoInputs() {
        session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .filter { $0.device.hasMediaType(.video) }
            .forEach { session.removeInput($0) }
    }
}

private enum CameraDeviceDiscovery {
    nonisolated static func availableVideoDevices() -> [CameraDeviceOption] {
        discoverySession.devices.map {
            CameraDeviceOption(uniqueID: $0.uniqueID, localizedName: $0.localizedName)
        }
    }

    nonisolated static func device(uniqueID: String?) -> AVCaptureDevice? {
        guard let uniqueID, !uniqueID.isEmpty else {
            return nil
        }

        return discoverySession.devices.first { $0.uniqueID == uniqueID }
    }

    nonisolated private static var discoverySession: AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )
    }

    nonisolated private static var deviceTypes: [AVCaptureDevice.DeviceType] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]

        if #available(macOS 14.0, *) {
            types.append(.external)
        } else {
            types.append(.externalUnknown)
        }

        if #available(macOS 14.0, *) {
            types.append(.continuityCamera)
        }

        return types
    }
}

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool

    func makeNSView(context: Context) -> CameraPreviewLayerView {
        let view = CameraPreviewLayerView()
        view.configure(session: session, isMirrored: isMirrored)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewLayerView, context: Context) {
        nsView.configure(session: session, isMirrored: isMirrored)
    }
}

final class CameraPreviewLayerView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var isMirrored = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer = previewLayer
        previewLayer.videoGravity = .resizeAspectFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(session: AVCaptureSession, isMirrored: Bool) {
        self.isMirrored = isMirrored

        if previewLayer.session !== session {
            previewLayer.session = session
        }

        previewLayer.videoGravity = .resizeAspectFill
        updateMirroringIfPossible()
    }

    override func layout() {
        super.layout()

        previewLayer.frame = bounds
        updateMirroringIfPossible()
    }

    private func updateMirroringIfPossible() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else {
            return
        }

        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = isMirrored
    }
}
