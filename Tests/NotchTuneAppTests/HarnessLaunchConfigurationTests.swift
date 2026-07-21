import Foundation
import Testing
@testable import NotchTuneApp

struct HarnessLaunchConfigurationTests {
    @Test
    func defaultsMatchNormalAppLaunch() {
        let configuration = HarnessLaunchConfiguration(environment: [:])

        #expect(configuration.scenario == nil)
        #expect(!configuration.presentOverlay)
        #expect(configuration.shouldStartBridge)
        #expect(configuration.shouldPerformBootAnimation)
        #expect(configuration.captureDelay == nil)
        #expect(configuration.autoExitAfter == nil)
        #expect(configuration.artifactDirectoryURL == nil)
    }

    @Test
    func parsesScenarioFlagsAndAutoExit() {
        let configuration = HarnessLaunchConfiguration(
            environment: [
                "NOTCHTUNE_HARNESS_SCENARIO": "approvalcard",
                "NOTCHTUNE_HARNESS_PRESENT_OVERLAY": "true",
                "NOTCHTUNE_HARNESS_START_BRIDGE": "no",
                "NOTCHTUNE_HARNESS_BOOT_ANIMATION": "off",
                "NOTCHTUNE_HARNESS_CAPTURE_DELAY_SECONDS": "1.5",
                "NOTCHTUNE_HARNESS_AUTO_EXIT_SECONDS": "2.5",
                "NOTCHTUNE_HARNESS_ARTIFACT_DIR": "/tmp/open-island-artifacts",
            ]
        )

        #expect(configuration.scenario == .approvalCard)
        #expect(configuration.presentOverlay)
        #expect(!configuration.shouldStartBridge)
        #expect(!configuration.shouldPerformBootAnimation)
        #expect(configuration.captureDelay == 1.5)
        #expect(configuration.autoExitAfter == 2.5)
        #expect(configuration.artifactDirectoryURL?.path == "/tmp/open-island-artifacts")
    }

    @Test
    func ignoresInvalidInputs() {
        let configuration = HarnessLaunchConfiguration(
            environment: [
                "NOTCHTUNE_HARNESS_SCENARIO": "missing",
                "NOTCHTUNE_HARNESS_PRESENT_OVERLAY": "unexpected",
                "NOTCHTUNE_HARNESS_CAPTURE_DELAY_SECONDS": "0",
                "NOTCHTUNE_HARNESS_AUTO_EXIT_SECONDS": "-1",
                "NOTCHTUNE_HARNESS_ARTIFACT_DIR": "   ",
            ]
        )

        #expect(configuration.scenario == nil)
        #expect(!configuration.presentOverlay)
        #expect(configuration.captureDelay == nil)
        #expect(configuration.autoExitAfter == nil)
        #expect(configuration.artifactDirectoryURL == nil)
    }
}
