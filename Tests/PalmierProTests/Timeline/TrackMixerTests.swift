import Foundation
import Testing
@testable import PalmierPro

@Suite("Track mixer — solo audibility, gain")
struct TrackMixerTests {

    @Test func mutedTrackIsInaudible() {
        var muted = Fixtures.audioTrack()
        muted.muted = true
        let audible = Fixtures.audioTrack()
        let tl = Fixtures.timeline(tracks: [muted, audible])
        #expect(tl.trackIsAudible(muted) == false)
        #expect(tl.trackIsAudible(audible) == true)
    }

    @Test func soloSilencesEveryOtherLane() {
        var soloed = Fixtures.audioTrack()
        soloed.soloed = true
        let other = Fixtures.audioTrack()
        let tl = Fixtures.timeline(tracks: [soloed, other])
        #expect(tl.hasSoloedTrack)
        #expect(tl.trackIsAudible(soloed) == true)
        #expect(tl.trackIsAudible(other) == false)
    }

    @Test func muteWinsOverSoloOnTheSameLane() {
        var lane = Fixtures.audioTrack()
        lane.soloed = true
        lane.muted = true
        let tl = Fixtures.timeline(tracks: [lane, Fixtures.audioTrack()])
        #expect(tl.trackIsAudible(lane) == false)
    }

    @Test func gainAndSoloSurviveCodableRoundTrip() throws {
        var track = Fixtures.audioTrack()
        track.gain = 0.5
        track.soloed = true
        let decoded = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(track))
        #expect(decoded.gain == 0.5)
        #expect(decoded.soloed == true)
    }

    @Test func gainDefaultsToUnityForLegacyTracksWithoutTheField() throws {
        let legacy = #"{"id":"t1","type":"audio","muted":false,"hidden":false,"syncLocked":true,"clips":[],"displayHeight":50}"#
        let decoded = try JSONDecoder().decode(Track.self, from: Data(legacy.utf8))
        #expect(decoded.gain == 1.0)
        #expect(decoded.soloed == false)
    }
}
