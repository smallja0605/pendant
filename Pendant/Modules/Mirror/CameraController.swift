import AVFoundation
import Observation

/// Front camera for the mirror. The camera runs only while the mirror page is visible: `start()` when it appears,
/// `stop()` the moment the capsule closes or the page changes (so the camera light goes off).
@MainActor
@Observable
final class CameraController {
    static let shared = CameraController()

    enum State: Equatable { case unknown, notDetermined, denied, noCamera, ready }

    private(set) var state: State = .unknown
    private(set) var isRunning = false
    private(set) var devices: [CameraInfo] = []

    struct CameraInfo: Identifiable, Equatable {
        let id: String
        let name: String
    }

    /// Not observed: the preview layer reads it directly.
    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let queue = DispatchQueue(label: "com.smallja.pendant.camera")
    @ObservationIgnored private var configuredID: String?

    func refreshAccess() async {
        switch await PermissionsService.state(for: .camera) {
        case .allowed:
            reloadDevices()
            state = devices.isEmpty ? .noCamera : .ready
        case .denied: state = .denied
        default: state = .notDetermined
        }
    }

    func requestAccess() async {
        await PermissionsService.request(.camera)
        await refreshAccess()
        if state == .ready { start() }
    }

    func reloadDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified
        )
        devices = discovery.devices.map { CameraInfo(id: $0.uniqueID, name: $0.localizedName) }
    }

    private var chosenDevice: AVCaptureDevice? {
        let wanted = AppSettings.shared.mirrorCameraID
        if !wanted.isEmpty, let device = AVCaptureDevice(uniqueID: wanted) { return device }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
    }

    func start() {
        guard state == .ready, !isRunning, let device = chosenDevice else { return }
        isRunning = true
        let id = device.uniqueID
        queue.async { [session] in
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }
        }
        configuredID = id
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// The camera choice changed in settings: restart with the new one.
    func restart() {
        guard isRunning else { return }
        stop()
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            start()
        }
    }
}
