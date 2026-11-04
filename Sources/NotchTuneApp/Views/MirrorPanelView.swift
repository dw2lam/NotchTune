@preconcurrency import AVFoundation
import SwiftUI

/// The Mirror tab: a hand mirror from the Mac's camera, laid out like the
/// Music tab — the picture where the cover sits, its controls beside it.
struct MirrorPanelView: View {
    var camera: MirrorCamera
    /// The notch is open on this tab; the camera runs only then.
    var isLive: Bool
    var horizontalPadding: CGFloat = 24

    static let frameHeight: CGFloat = 166
    static let frameWidth: CGFloat = 296
    private static let headerHeight: CGFloat = 26
    private static let rowHeight: CGFloat = 38

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            mirrorFrame
            controls
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: Self.frameHeight)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .task(id: isLive) {
            if isLive {
                camera.start()
            } else {
                camera.stop()
            }
        }
        .onDisappear { camera.stop() }
    }

    // MARK: Picture

    private var mirrorFrame: some View {
        ZStack {
            Color.white.opacity(0.04)

            switch camera.access {
            case .granted:
                picture
                    .transition(.opacity)
            case .notDetermined:
                accessPrompt(
                    title: "See yourself",
                    detail: "The camera stays off until you open this tab.",
                    button: "Turn On Camera",
                    action: camera.requestAccess
                )
            case .denied:
                accessPrompt(
                    title: "Camera access is off",
                    detail: "Allow NotchTune in Privacy & Security.",
                    button: "Open Settings",
                    action: camera.openPrivacySettings
                )
            }
        }
        .frame(width: Self.frameWidth, height: Self.frameHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.2), value: camera.access)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mirror")
    }

    @ViewBuilder
    private var picture: some View {
        if camera.isSimulated {
            Group {
                if let still = camera.stillImage {
                    Image(nsImage: still)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [Color(white: 0.32), Color(white: 0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .scaleEffect(x: camera.isMirrored ? -1 : 1, y: 1)
            .scaleEffect(camera.zoom.rawValue)
            .frame(width: Self.frameWidth, height: Self.frameHeight)
            .clipped()
        } else {
            MirrorVideoView(
                session: camera.capture.session,
                isMirrored: camera.isMirrored,
                zoom: camera.zoom.rawValue
            )
        }
    }

    private func accessPrompt(
        title: String,
        detail: String,
        button: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "camera.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.bottom, 2)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
            Text(detail)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
            Button(button, action: action)
                .buttonStyle(MirrorCapsuleButtonStyle())
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            cameraMenu
                .frame(height: Self.headerHeight)

            VStack(spacing: 6) {
                controlRow(
                    systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                    title: "Flip",
                    detail: camera.isMirrored ? "Mirrored, like a mirror" : "As others see you",
                    isOn: camera.isMirrored
                ) {
                    camera.isMirrored.toggle()
                }
                controlRow(
                    systemImage: camera.zoom == .one ? "plus.magnifyingglass" : "minus.magnifyingglass",
                    title: "Zoom",
                    detail: camera.zoom.label,
                    isOn: camera.zoom != .one
                ) {
                    withAnimation(.smooth(duration: 0.3)) { camera.zoom = camera.zoom.next }
                }
            }

            Spacer(minLength: 0)

            statusLine
        }
        .disabled(camera.access != .granted)
        .opacity(camera.access == .granted ? 1 : 0.45)
    }

    /// The camera picker: a drop-down capsule, styled like the Music
    /// library's section picker.
    private var cameraMenu: some View {
        Menu {
            ForEach(camera.devices) { device in
                Button {
                    camera.selectedDeviceID = device.id
                } label: {
                    if device.id == camera.activeDeviceID {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
            if camera.devices.isEmpty {
                Text("No camera found")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "video.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text(camera.activeDeviceName ?? "Camera")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 12)
            .frame(height: Self.headerHeight)
            .background(.white.opacity(0.04), in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.07), lineWidth: 0.5) }
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose a camera")
        .accessibilityLabel("Camera: \(camera.activeDeviceName ?? "none")")
    }

    private func controlRow(
        systemImage: String,
        title: String,
        detail: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(isOn ? 0.92 : 0.6))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(isOn ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.46))
                        .contentTransition(.opacity)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(height: Self.rowHeight)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(MirrorRowButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(detail)
    }

    private var statusLine: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(camera.isRunning || camera.isSimulated ? Color.green : Color.white.opacity(0.3))
                .frame(width: 5, height: 5)
            Text("Camera is on only while Mirror is open")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.34))
                .lineLimit(1)
        }
    }
}

/// A list-row button: a soft fill on hover, a slight press, and the notch's
/// button haptic.
private struct MirrorRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MirrorRowBody(configuration: configuration)
    }
}

private struct MirrorRowBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .background(
                .white.opacity(configuration.isPressed ? 0.1 : (isHovering ? 0.06 : 0)),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { isHovering = $0 }
            .notchHapticOnPress(configuration.isPressed)
    }
}

private struct MirrorCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(.white.opacity(configuration.isPressed ? 0.75 : 0.9), in: Capsule())
            .notchHapticOnPress(configuration.isPressed)
    }
}

/// The live camera picture. Mirroring is set on the preview connection
/// (every time the session starts, since inputs come and go) and zoom
/// crops by growing the preview layer past the view's rounded bounds.
private struct MirrorVideoView: NSViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool
    let zoom: CGFloat

    func makeNSView(context: Context) -> MirrorVideoNSView {
        MirrorVideoNSView(session: session)
    }

    func updateNSView(_ view: MirrorVideoNSView, context: Context) {
        view.isMirrored = isMirrored
        view.zoom = zoom
    }
}

final class MirrorVideoNSView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer
    nonisolated(unsafe) private var startObserver: NSObjectProtocol?

    var isMirrored = true {
        didSet { if isMirrored != oldValue { applyMirroring() } }
    }

    var zoom: CGFloat = 1 {
        didSet { if zoom != oldValue { needsLayout = true } }
    }

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
        startObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.didStartRunningNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyMirroring() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let startObserver {
            NotificationCenter.default.removeObserver(startObserver)
        }
    }

    override func layout() {
        super.layout()
        let width = bounds.width * zoom
        let height = bounds.height * zoom
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        previewLayer.frame = CGRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
        CATransaction.commit()
        applyMirroring()
    }

    private func applyMirroring() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = isMirrored
    }
}
