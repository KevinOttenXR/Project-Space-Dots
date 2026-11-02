// Compile with AppModel.swift for a booted visionOS simulator, then run with
// xcrun simctl spawn booted <compiled executable>.
import Foundation
import SwiftUI

@main
struct MovieDimmingChecks {
    @MainActor static func main() {
        let model = AppModel()
        precondition(!model.youtubePlaybackHasStarted,
                     "Startup must not be playing")

        model.experienceScreen = .theMoment
        precondition(!model.youtubePlaybackHasStarted,
                     "Explanation must not be playing")

        // A playing status while the start screen is visible must not dim.
        model.youtubePlayerDidUpdate(time: 0.0, duration: 69.0, state: 1)
        precondition(!model.youtubePlaybackHasStarted,
                     "Pre-start playback status must be ignored")

        // Real playback activates Apple's native preference immediately.
        model.shouldShowStartScreen = false
        model.youtubePlayerDidUpdate(time: 0.0, duration: 69.0, state: 1)
        precondition(model.youtubePlaybackHasStarted,
                     "Real playback must be detected")

        model.resetTheMomentPlayback()
        precondition(!model.youtubePlaybackHasStarted,
                     "Reset must stop playback")

        print("PASS: native movie dimming is direct and playback-driven")
    }
}
