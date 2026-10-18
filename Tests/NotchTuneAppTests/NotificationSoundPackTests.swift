import AppKit
import AVFoundation
import Foundation
import Testing
@testable import NotchTuneApp

/// The bundled NotchTune sound pack. Silent by design: these read and
/// measure the files, and resolve names — nothing here ever plays a sound.
@MainActor
struct NotificationSoundPackTests {
    private struct Samples {
        let values: [Float]
        let sampleRate: Double

        var duration: Double { Double(values.count) / sampleRate }
        var peak: Float { values.map(abs).max() ?? 0 }
        var mean: Double { values.reduce(0.0) { $0 + Double($1) } / Double(max(1, values.count)) }

        /// RMS of the loudest 100 ms (25 ms hop), in dBFS.
        var loudestWindowDB: Double {
            let window = Int(0.1 * sampleRate), hop = Int(0.025 * sampleRate)
            var best = 0.0
            var start = 0
            repeat {
                let slice = values[start..<min(values.count, start + window)]
                let power = slice.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, slice.count))
                best = max(best, power)
                start += hop
            } while start + window <= values.count
            return 10 * log10(max(best, 1e-12))
        }
    }

    private func samples(_ sound: NotificationSoundService.BundledSound) throws -> Samples {
        let file = try AVAudioFile(forReading: sound.url)
        let frames = AVAudioFrameCount(file.length)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        try file.read(into: buffer)
        let channel = try #require(buffer.floatChannelData?[0])
        return Samples(
            values: Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))),
            sampleRate: file.processingFormat.sampleRate
        )
    }

    @Test
    func thePackShipsADozenOrMoreUniquelyNamedSounds() {
        let pack = NotificationSoundService.bundledSounds
        #expect(pack.count >= 12)
        #expect(Set(pack.map(\.id)).count == pack.count)
        #expect(Set(pack.map(\.title)).count == pack.count)
        #expect(pack.allSatisfy { $0.id.hasPrefix(NotificationSoundService.bundledSoundPrefix) })
        // Listed by title, so the menu reads alphabetically.
        #expect(pack.map(\.title) == pack.map(\.title).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    @Test
    func everySoundIsShortCleanAndBelowTheCeiling() throws {
        for sound in NotificationSoundService.bundledSounds {
            let audio = try samples(sound)
            #expect((0.15...1.201).contains(audio.duration), "\(sound.title) lasts \(audio.duration)s")
            // About −1 dBFS or lower.
            #expect(audio.peak <= 0.892, "\(sound.title) peaks at \(audio.peak)")
            #expect(abs(audio.mean) < 0.001, "\(sound.title) has DC \(audio.mean)")
            // Starts and ends on silence: no click at either edge.
            #expect(abs(audio.values.first ?? 1) < 0.001, "\(sound.title) starts at \(audio.values.first ?? 1)")
            #expect(abs(audio.values.last ?? 1) < 0.001, "\(sound.title) ends at \(audio.values.last ?? 1)")
            let tail = audio.values.suffix(Int(0.005 * audio.sampleRate)).map(abs).max() ?? 1
            #expect(tail < audio.peak * 0.02, "\(sound.title) is still ringing at the cut")
        }
    }

    @Test
    func theSoundsAreLevelMatchedSoNoneJumpsOut() throws {
        let levels = try NotificationSoundService.bundledSounds.map { try samples($0).loudestWindowDB }
        // The macOS alert sounds' loudest 100 ms sits around here too.
        #expect(levels.allSatisfy { (-27.0)...(-18.0) ~= $0 }, "levels: \(levels)")
        #expect((levels.max() ?? 0) - (levels.min() ?? 0) <= 6, "spread: \(levels)")
    }

    @Test
    func everySoundDecodesWithoutPlaying() throws {
        for sound in NotificationSoundService.bundledSounds {
            let decoded = try #require(NSSound(contentsOf: sound.url, byReference: true), "\(sound.title)")
            #expect(decoded.duration > 0.1)
            #expect(!decoded.isPlaying)
        }
    }

    @Test
    func storedNamesResolveToTheRightSource() throws {
        let first = try #require(NotificationSoundService.bundledSounds.first)
        #expect(NotificationSoundService.source(for: first.id) == .bundled(first.url))
        // Selections saved before the pack existed keep working.
        #expect(NotificationSoundService.source(for: "Bottle") == .system("Bottle"))
        #expect(NotificationSoundService.source(for: NotificationSoundService.nudgeDefaultSoundName) == .system("Submarine"))
        // A pack sound that no longer ships falls back to the default.
        #expect(NotificationSoundService.source(for: "notchtune.retired-sound") == .system(NotificationSoundService.defaultSoundName))
    }

    @Test
    func slugsBecomeTitles() {
        #expect(NotificationSoundService.title(forSlug: "ding-dong") == "Ding Dong")
        #expect(NotificationSoundService.title(forSlug: "coin") == "Coin")
    }
}
