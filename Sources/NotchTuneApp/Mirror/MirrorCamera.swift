import AppKit
@preconcurrency import AVFoundation
import Observation

/// How far the Mirror tab zooms in. The camera's own frame is cropped (Macs
/// have no optical zoom), so 2× halves the field of view.
enum MirrorZoom: Double, CaseIterable, Sendable {
    case one = 1
    case oneAndHalf = 1.5
    case two = 2

    var next: MirrorZoom {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    var label: String {
        switch self {
        case .one: "1×"
        case .oneAndHalf: "1.5×"
        case .two: "2×"
        }
    }
}

/// The camera behind the Mirror tab. It runs only while that tab is on
/// screen in the open notch, and never in the harness or in tests (that
/// would light the camera on the Mac running them).
@MainActor
@Observable
final class MirrorCamera {
    struct Device: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
    }

    enum Access: Equatable {
        /// Never asked: the tab offers to turn the camera on.
        case notDetermined
        case granted
        /// Denied or restricted: the tab points to Privacy & Security.
        case denied
    }

    private static let mirroredKey = "mirror.mirrored"
    private static let zoomKey = "mirror.zoom"
    private static let cameraKey = "mirror.camera"
    private static let expandedKey = "mirror.expanded"

    private(set) var devices: [Device] = []
    private(set) var access: Access = .notDetermined
    private(set) var isRunning = false

    /// Shows the picture flipped, like a mirror. On by default.
    var isMirrored: Bool {
        didSet { defaults.set(isMirrored, forKey: Self.mirroredKey) }
    }

    var zoom: MirrorZoom {
        didSet { defaults.set(zoom.rawValue, forKey: Self.zoomKey) }
    }

    /// The bigger mirror: the notch grows taller (never wider), as far as
    /// the screen allows.
    var isExpanded: Bool {
        didSet { defaults.set(isExpanded, forKey: Self.expandedKey) }
    }

    /// The chosen camera's `uniqueID`; `nil` until one is picked (the
    /// built-in camera, or the first one found, is used meanwhile).
    var selectedDeviceID: String? {
        didSet {
            defaults.set(selectedDeviceID, forKey: Self.cameraKey)
            if wantsRunning, access == .granted {
                capture.run(deviceID: activeDeviceID)
            }
        }
    }

    /// The picture's width as last laid out; the notch's height follows from
    /// it (`MirrorPanelView.contentHeight`). Not saved.
    @ObservationIgnored var layoutWidth: CGFloat = 0

    /// A still shown in place of the camera: harness captures (where the
    /// camera never runs) and the website.
    let stillImage: NSImage?
    /// The camera is never touched: harness runs and tests.
    let isSimulated: Bool

    let capture = MirrorCaptureSession()

    private let defaults: UserDefaults
    private var wantsRunning = false
    private var deviceObservers: [NSObjectProtocol] = []

    init(
        defaults: UserDefaults = .standard,
        isSimulated: Bool = HarnessHeadless.isActive,
        stillImage: NSImage? = MirrorCamera.harnessStill()
    ) {
        self.defaults = defaults
        self.isSimulated = isSimulated
        self.stillImage = stillImage
        isMirrored = defaults.object(forKey: Self.mirroredKey) as? Bool ?? true
        zoom = MirrorZoom(rawValue: defaults.double(forKey: Self.zoomKey)) ?? .one
        isExpanded = defaults.bool(forKey: Self.expandedKey)
        selectedDeviceID = defaults.string(forKey: Self.cameraKey)
        if isSimulated {
            devices = [Device(id: "harness", name: "FaceTime HD Camera")]
            access = .granted
            // `NOTCHTUNE_HARNESS_MIRROR_EXPANDED=1` captures the bigger mirror.
            // Set on the backing store so it isn't saved as the user's choice.
            if ProcessInfo.processInfo.environment["NOTCHTUNE_HARNESS_MIRROR_EXPANDED"] == "1" {
                _isExpanded = true
            }
        }
    }

    /// The camera in use: the chosen one if it's still connected, otherwise
    /// the built-in one, otherwise whatever is there.
    var activeDeviceID: String? {
        if let selectedDeviceID, devices.contains(where: { $0.id == selectedDeviceID }) {
            return selectedDeviceID
        }
        return devices.first?.id
    }

    var activeDeviceName: String? {
        devices.first { $0.id == activeDeviceID }?.name
    }

    /// The Mirror tab came on screen.
    func start() {
        wantsRunning = true
        guard !isSimulated else { return }
        observeDevicesIfNeeded()
        refreshDevices()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            access = .granted
            capture.run(deviceID: activeDeviceID)
            isRunning = true
        case .notDetermined:
            access = .notDetermined
        default:
            access = .denied
        }
    }

    /// The Mirror tab left the screen (another tab, or the notch closed).
    func stop() {
        wantsRunning = false
        guard !isSimulated, isRunning else { return }
        capture.stop()
        isRunning = false
    }

    /// Asks for camera access; the camera starts if the tab is still open.
    func requestAccess() {
        guard !isSimulated else { return }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                self.access = granted ? .granted : .denied
                if granted, self.wantsRunning {
                    self.start()
                }
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshDevices() {
        let found = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
        // Built-in first, then the rest by name.
        devices = found
            .sorted { lhs, rhs in
                let lhsBuiltIn = lhs.deviceType == .builtInWideAngleCamera
                let rhsBuiltIn = rhs.deviceType == .builtInWideAngleCamera
                if lhsBuiltIn != rhsBuiltIn { return lhsBuiltIn }
                return lhs.localizedName.localizedStandardCompare(rhs.localizedName) == .orderedAscending
            }
            .map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    private func observeDevicesIfNeeded() {
        guard deviceObservers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            deviceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let previous = self.activeDeviceID
                    self.refreshDevices()
                    if self.isRunning, self.activeDeviceID != previous {
                        self.capture.run(deviceID: self.activeDeviceID)
                    }
                }
            })
        }
    }

    /// `NOTCHTUNE_HARNESS_MIRROR_STILL=<image path>`.
    nonisolated static func harnessStill(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> NSImage? {
        guard let path = environment["NOTCHTUNE_HARNESS_MIRROR_STILL"] else { return nil }
        return NSImage(contentsOfFile: path)
    }
}

/// The capture session, configured and started off the main thread
/// (`startRunning` blocks while the camera wakes up).
final class MirrorCaptureSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.notchtune.mirror.capture")

    func run(deviceID: String?) {
        queue.async { [session] in
            session.beginConfiguration()
            session.sessionPreset = .high
            for input in session.inputs {
                session.removeInput(input)
            }
            if let deviceID,
               let device = AVCaptureDevice(uniqueID: deviceID),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
            // Release the camera entirely so its light goes off.
            session.beginConfiguration()
            for input in session.inputs {
                session.removeInput(input)
            }
            session.commitConfiguration()
        }
    }
}
