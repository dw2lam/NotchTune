import AppKit
import Foundation
import Testing
@testable import NotchTuneApp

struct AgentAppIconProviderTests {
    /// Every bundled brand logo must actually draw something: a blank PNG
    /// renders as an empty square in the island's usage header.
    @Test @MainActor
    func everyBundledAgentLogoHasVisiblePixels() throws {
        let urls = Bundle.appResources.urls(forResourcesWithExtension: "png", subdirectory: nil) ?? []
        let logoURLs = urls.filter { $0.lastPathComponent.hasPrefix("agent-logo-") }
        #expect(logoURLs.count >= Set(AgentAppIconProvider.bundledLogoNames.values).count)

        for url in logoURLs {
            let image = try #require(NSImage(contentsOf: url), "\(url.lastPathComponent) does not decode")
            #expect(
                AgentAppIconProvider.hasVisiblePixels(image),
                "\(url.lastPathComponent) is fully transparent"
            )
        }
    }

    @Test @MainActor
    func everyMappedProviderResolvesItsBundledLogo() {
        for title in AgentAppIconProvider.bundledLogoNames.keys {
            #expect(
                AgentAppIconProvider.bundledLogo(forProviderTitle: title) != nil,
                "no visible bundled logo for \(title)"
            )
        }
        #expect(AgentAppIconProvider.bundledLogo(forProviderTitle: "Factory") == nil)
    }

    @Test @MainActor
    func fullyTransparentImageCountsAsMissing() throws {
        #expect(!AgentAppIconProvider.hasVisiblePixels(try image64(dot: false)))
        // One opaque pixel is enough to count as a logo.
        #expect(AgentAppIconProvider.hasVisiblePixels(try image64(dot: true)))
    }

    private func image64(dot: Bool) throws -> NSImage {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        if dot, let pixels = rep.bitmapData {
            let offset = 12 * rep.bytesPerRow + 40 * 4
            for channel in 0..<4 {
                pixels[offset + channel] = 255
            }
        }
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.addRepresentation(rep)
        return image
    }
}
