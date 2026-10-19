import AppKit
import AVFoundation
import Foundation
import SwiftUI
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
    func thePackShipsAllThirtyTwoUniquelyNamedSounds() {
        let pack = NotificationSoundService.bundledSounds
        // Pinned: a file dropped from (or left over in) the bundle shows here.
        #expect(pack.count == 32)
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
    func aCustomFileNamedLikeThePackStaysCustom() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchTuneSoundTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notchtune.wav")
        try Data([0]).write(to: file)

        #expect(NotificationSoundService.source(for: "notchtune.wav", customDirectory: directory) == .custom(file))
        // A shipping pack id still resolves to the pack.
        let first = try #require(NotificationSoundService.bundledSounds.first)
        #expect(NotificationSoundService.source(for: first.id, customDirectory: directory) == .bundled(first.url))
    }

    @Test
    func slugsBecomeTitles() {
        #expect(NotificationSoundService.title(forSlug: "ding-dong") == "Ding Dong")
        #expect(NotificationSoundService.title(forSlug: "coin") == "Coin")
    }

    /// The sound menu (built, never shown or played). One flat list of 32 +
    /// 14 sounds ran 1228 pt tall, taller than a laptop screen, so macOS hid
    /// part of it behind scroll arrows. The pack now sits in place and the
    /// rest in submenus.
    @Test
    func theSoundMenuFitsOnALaptopScreenWithEverySoundReachable() throws {
        let pack = NotificationSoundService.bundledSounds
        let system = NotificationSoundService.availableSounds()
        let sections = SoundSettingsPane.soundSections(pack: pack, system: system, custom: ["chime.aiff"], title: { $0 })

        for selected in [try #require(pack.first).id, "Bottle"] {
            let menu = SettingsPopUpMenu<String>.menu(
                title: "", selection: selected, sections: sections,
                inlineSections: SoundSettingsPane.inlineSoundSections,
                target: SettingsPopUpMenu<String>.Coordinator()
            )
            // a 13-inch MacBook Air's screen, less the menu bar, is about 919 pt
            #expect(menu.size.height <= 900, "the menu is \(menu.size.height) pt tall")

            // (item 0 is the pull-down's own title, never listed)
            let rows = menu.items.dropFirst().filter { !$0.isSeparatorItem && !$0.isSectionHeader }
            #expect(rows.filter { $0.submenu == nil }.map(\.title) == pack.map(\.title))
            let submenus = rows.compactMap(\.submenu)
            #expect(submenus.map { $0.items.map(\.title) } == [system, ["chime"]])

            let checked = (rows + submenus.flatMap(\.items)).filter { $0.state == .on }.map(\.title)
            let expected = pack.first { $0.id == selected }?.title ?? selected
            #expect(checked == [expected])
        }
    }

    /// The real control, in the real (themed) Sound pane: the click on the
    /// capsule lands on an AppKit pull-down whose menu holds every sound. Before, the click opened a SwiftUI menu that the
    /// window's custom toggle style emptied (headers, nothing to pick).
    @Test
    func theSoundPaneCapsuleOpensAMenuWithEverySound() async throws {
        // the real pane under the window's theme (hosted alone: a whole
        // SettingsView would follow other tests' tab switches)
        let model = AppModel()
        let controller = NSHostingController(rootView: SoundSettingsPane(model: model).settingsTheme())
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 640, height: 900),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 640, height: 900))
        // on the window list (far off every screen), so the pane lays out
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.close() }
        try? await Task.sleep(for: .milliseconds(400))
        controller.view.layoutSubtreeIfNeeded()

        func popUps(_ view: NSView) -> [NSPopUpButton] {
            ((view as? NSPopUpButton).map { [$0] } ?? []) + view.subviews.flatMap(popUps)
        }
        let all = popUps(controller.view)
        // the notification sound comes first; the nudge sound is the last
        let button = try #require(all.first)
        #expect(button.pullsDown)
        // a click on the capsule's centre goes to the pop-up button
        let root = try #require(controller.view.superview)
        let centre = root.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
        #expect(controller.view.hitTest(centre) === button)
        // and so for every menu capsule on the pane (the nudge timing too):
        // each opens a menu with something to pick
        for popUp in all {
            let choices = (popUp.menu?.items ?? []).flatMap { [$0] + ($0.submenu?.items ?? []) }
            #expect(choices.contains { $0.action != nil && $0.target != nil && $0.isEnabled }, "\(popUp.title)")
        }

        let menu = try #require(button.menu)
        let rows = menu.items.dropFirst().filter { !$0.isSeparatorItem && !$0.isSectionHeader }
        let pack = NotificationSoundService.bundledSounds
        #expect(rows.filter { $0.submenu == nil }.map(\.title) == pack.map(\.title))
        #expect(rows.allSatisfy { $0.isEnabled && ($0.submenu != nil || $0.action != nil) })
        let systemMenu = try #require(rows.compactMap(\.submenu).first)
        #expect(systemMenu.items.map(\.title) == NotificationSoundService.availableSounds())
        let checked = (rows + systemMenu.items).filter { $0.state == .on }.map(\.title)
        #expect(checked == [SettingsMenuPicker<String>.title(
            for: model.selectedSoundName,
            in: SoundSettingsPane.soundSections(pack: pack, system: NotificationSoundService.availableSounds(), custom: [], title: { $0 })
        )])
    }

    /// Picking from the menu (the item's own target and action, as AppKit
    /// fires them) changes the choice, from the list and from a submenu,
    /// under the Settings theme. The test's own binding: nothing plays.
    @Test
    func pickingASoundFromTheMenuSelectsIt() throws {
        let pack = NotificationSoundService.bundledSounds
        let sections = SoundSettingsPane.soundSections(
            pack: pack, system: NotificationSoundService.availableSounds(), custom: [], title: { $0 }
        )
        var value = "Bottle"
        let view = NSHostingView(rootView: SettingsMenuPicker(
            "Notification sound",
            selection: Binding(get: { value }, set: { value = $0 }),
            sections: sections,
            inlineSections: SoundSettingsPane.inlineSoundSections
        ).settingsTheme())
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
        view.layoutSubtreeIfNeeded()

        func popUp(_ view: NSView) -> NSPopUpButton? {
            (view as? NSPopUpButton) ?? view.subviews.lazy.compactMap(popUp).first
        }
        let button = try #require(popUp(view))
        let menu = try #require(button.menu)
        #expect(menu.items.first?.title == "Bottle")

        let last = try #require(pack.last)
        menu.performActionForItem(at: try #require(menu.items.firstIndex { $0.title == last.title }))
        #expect(value == last.id)
        let systemMenu = try #require(menu.items.compactMap(\.submenu).first)
        systemMenu.performActionForItem(at: try #require(systemMenu.items.firstIndex { $0.title == "Glass" }))
        #expect(value == "Glass")
    }
}
