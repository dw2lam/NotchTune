import AppKit
import SwiftUI

enum MusicConstants {
    static let podcastThresholdDurationSec = 900.0
    static let podcastRewindDurationSec = 15.0

    enum Opacity {
        static let primary = 0.8
        static let secondary = 0.6
    }

    enum Spotify {
        static let bundleID = "com.spotify.client"
    }

    enum AppleMusic {
        static let bundleID = "com.apple.Music"
    }

    static var mainAnimation: Animation {
        Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.7)
    }
}
