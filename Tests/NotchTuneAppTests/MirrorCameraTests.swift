import Foundation
import Testing
@testable import NotchTuneApp

@MainActor
struct MirrorCameraTests {
    private func freshDefaults() -> UserDefaults {
        let name = "mirror-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test
    func testsAndHarnessRunsNeverTouchTheCamera() {
        // The app model's camera in a test process is simulated: starting
        // it must not wake the Mac's camera.
        let model = AppModel()
        #expect(model.mirror.isSimulated)
        model.mirror.start()
        #expect(!model.mirror.isRunning)
        model.mirror.stop()
    }

    @Test
    func mirroredByDefaultAndChoicesPersist() {
        let defaults = freshDefaults()
        let camera = MirrorCamera(defaults: defaults, isSimulated: true, stillImage: nil)
        #expect(camera.isMirrored)
        #expect(camera.zoom == .one)

        camera.isMirrored = false
        camera.zoom = .two
        camera.selectedDeviceID = "harness"

        let reopened = MirrorCamera(defaults: defaults, isSimulated: true, stillImage: nil)
        #expect(!reopened.isMirrored)
        #expect(reopened.zoom == .two)
        #expect(reopened.selectedDeviceID == "harness")
    }

    @Test
    func zoomCyclesBackToOne() {
        #expect(MirrorZoom.one.next == .oneAndHalf)
        #expect(MirrorZoom.oneAndHalf.next == .two)
        #expect(MirrorZoom.two.next == .one)
    }

    @Test
    func aMissingCameraFallsBackToTheFirstOne() {
        let camera = MirrorCamera(defaults: freshDefaults(), isSimulated: true, stillImage: nil)
        camera.selectedDeviceID = "unplugged"
        #expect(camera.activeDeviceID == "harness")
        #expect(camera.activeDeviceName == "FaceTime HD Camera")
    }

    @Test
    func theMirrorSpansTheWidthAndExpandOnlyMakesItTaller() {
        let normal = MirrorPanelView.pictureHeight(width: 600, isExpanded: false, cap: 2000)
        let expanded = MirrorPanelView.pictureHeight(width: 600, isExpanded: true, cap: 2000)
        #expect(normal == 338) // 16:9 across the full width
        #expect(expanded == 600)
    }

    @Test
    func anExpandedMirrorStopsAtTheScreenWithItsControlsOnScreen() {
        let cap: CGFloat = 500
        let height = MirrorPanelView.pictureHeight(width: 600, isExpanded: true, cap: cap)
        let content = height + MirrorPanelView.controlsHeight + MirrorPanelView.spacing
            + MirrorPanelView.topPadding + MirrorPanelView.bottomPadding
        #expect(content <= cap)
        #expect(height < 600)
    }

    @Test
    func expandedPersists() {
        let defaults = freshDefaults()
        let camera = MirrorCamera(defaults: defaults, isSimulated: true, stillImage: nil)
        #expect(!camera.isExpanded)
        camera.isExpanded = true
        #expect(MirrorCamera(defaults: defaults, isSimulated: true, stillImage: nil).isExpanded)
    }
}
