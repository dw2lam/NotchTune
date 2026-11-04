@preconcurrency import AVFoundation
import SwiftUI

struct MirrorContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The Mirror tab: a hand mirror from the Mac's camera. The picture spans
/// the open notch's width; its controls sit in one row underneath. Expand
/// only makes the picture taller (the notch keeps its width), as far as
/// the screen allows.
struct MirrorPanelView: View {
    var camera: MirrorCamera
    /// The notch is open on this tab; the camera runs only then.
    var isLive: Bool
    var horizontalPadding: CGFloat = 24
    /// Tallest this tab's content may be before the notch would run off the
    /// screen (`nil` before there is a screen).
    var maxContentHeight: CGFloat?

    @State private var width: CGFloat = 0

    static let controlsHeight: CGFloat = 30
    static let spacing: CGFloat = 10
    static let topPadding: CGFloat = 4
    static let bottomPadding: CGFloat = 14
    /// Height / width of the picture: a wide 16:9, or square when expanded.
    static let aspect: CGFloat = 9.0 / 16.0
    static let expandedAspect: CGFloat = 1
    private static let cornerRadius: CGFloat = 16

    /// The picture's height for a given width, fitted under `cap` (the whole
    /// tab's content budget) so the controls always stay on screen.
    static func pictureHeight(width: CGFloat, isExpanded: Bool, cap: CGFloat?) -> CGFloat {
        let natural = (width * (isExpanded ? expandedAspect : aspect)).rounded()
        guard let cap else { return natural }
        let room = cap - controlsHeight - spacing - topPadding - bottomPadding
        return max(120, min(natural, room.rounded(.down)))
    }

    private var pictureHeight: CGFloat {
        Self.pictureHeight(width: width, isExpanded: camera.isExpanded, cap: maxContentHeight)
    }

    var body: some View {
        VStack(spacing: Self.spacing) {
            mirrorFrame
            controls
                .frame(height: Self.controlsHeight)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, Self.topPadding)
        .padding(.bottom, Self.bottomPadding)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: MirrorContentHeightKey.self, value: geometry.size.height)
            }
        }
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

    /// The picture and prompts are an overlay on a plain frame, so a
    /// picture's own size (a still filling the frame, say) never feeds back
    /// into the layout.
    private var mirrorFrame: some View {
        Color.white.opacity(0.04)
            .frame(maxWidth: .infinity)
            .frame(height: pictureHeight)
            .overlay { frameContent }
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            .animation(.easeInOut(duration: 0.2), value: camera.access)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Mirror")
    }

    @ViewBuilder
    private var frameContent: some View {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        } else {
            MirrorVideoView(
                session: camera.capture.session,
                isMirrored: camera.isMirrored,
                zoom: camera.zoom.rawValue,
                cornerRadius: Self.cornerRadius
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
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.bottom, 2)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
            Button(button, action: action)
                .buttonStyle(MirrorCapsuleButtonStyle())
                .padding(.top, 6)
        }
        .padding(.horizontal, 20)
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 8) {
            cameraMenu

            Spacer(minLength: 8)

            iconButton(
                camera.zoom == .one ? "plus.magnifyingglass" : "minus.magnifyingglass",
                label: camera.zoom.label,
                help: "Zoom: \(camera.zoom.label)",
                isOn: camera.zoom != .one
            ) {
                withAnimation(.smooth(duration: 0.3)) { camera.zoom = camera.zoom.next }
            }
            iconButton(
                "arrow.left.and.right.righttriangle.left.righttriangle.right",
                help: camera.isMirrored ? "Flip: mirrored, like a mirror" : "Flip: as others see you",
                isOn: camera.isMirrored
            ) {
                camera.isMirrored.toggle()
            }
            iconButton(
                camera.isExpanded
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                help: camera.isExpanded ? "Make the mirror smaller" : "Make the mirror bigger",
                isOn: camera.isExpanded
            ) {
                withAnimation(.smooth(duration: 0.35)) { camera.isExpanded.toggle() }
            }
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
                Circle()
                    .fill(camera.isRunning || camera.isSimulated ? Color.green : Color.white.opacity(0.3))
                    .frame(width: 5, height: 5)
                Text(camera.activeDeviceName ?? "Camera")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 12)
            .frame(height: Self.controlsHeight)
            .background(.white.opacity(0.06), in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.08), lineWidth: 0.5) }
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose a camera. It's only on while Mirror is open.")
        .accessibilityLabel("Camera: \(camera.activeDeviceName ?? "none")")
    }

    private func iconButton(
        _ systemImage: String,
        label: String? = nil,
        help: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                if let label {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(.white.opacity(isOn ? 0.95 : 0.7))
            .padding(.horizontal, label == nil ? 0 : 11)
            .frame(minWidth: Self.controlsHeight, minHeight: Self.controlsHeight)
            .background(.white.opacity(isOn ? 0.16 : 0.06), in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.08), lineWidth: 0.5) }
            .contentShape(Capsule())
        }
        .buttonStyle(MirrorRowButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A control button: a soft brighten on hover, a slight press, and the
/// notch's button haptic.
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
            .brightness(configuration.isPressed ? 0.12 : (isHovering ? 0.06 : 0))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
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
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> MirrorVideoNSView {
        let view = MirrorVideoNSView(session: session)
        view.layer?.cornerRadius = cornerRadius
        return view
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
