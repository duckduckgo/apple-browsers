//
//  AudioSessionManagerTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Testing
@testable import DuckDuckGo

@Suite("Video Player - Audio Session Manager")
struct AudioSessionManagerTests {
    private var sut: AudioSessionManager!
    private var audioSessionSpy: AVAudioSessionSpy!

    init() {
        audioSessionSpy = AVAudioSessionSpy()
        sut = AudioSessionManager(audioSession: audioSessionSpy)
    }

    @Test("Check Audio Session Parameters Are Set Correctly")
    func checkSetPlaybackSessionActiveSetsCategoryToPlayback_ModeMoviePlayback_AndOptionMixWithOthers() {
        // GIVEN
        #expect(audioSessionSpy.category == nil)
        #expect(audioSessionSpy.mode == nil)
        #expect(audioSessionSpy.categoryOptions.isEmpty)

        // WHEN
        sut.setPlaybackSessionActive()

        // THEN
        #expect(audioSessionSpy.category == .playback)
        #expect(audioSessionSpy.mode == .moviePlayback)
        #expect(audioSessionSpy.categoryOptions == [.mixWithOthers])
    }

    @Test("Check AVAudioSession Is Activated")
    func checkSetPlaybackSessionActiveActivatesTheUnderlyingAVSession() {
        // GIVEN
        #expect(!audioSessionSpy.active)

        // WHEN
        sut.setPlaybackSessionActive()

        // THEN
        #expect(audioSessionSpy.active)
        #expect(audioSessionSpy.activeOptions.isEmpty)
    }

    @Test("Check AVAudioSession Is Deactivated")
    func checkSetPlaybackSessionInactiveDeactivatesTheUnderlyingAVSession() {
        // GIVEN
        sut.setPlaybackSessionActive()
        #expect(audioSessionSpy.active)

        // WHEN
        sut.setPlaybackSessionInactive()

        // THEN
        #expect(!audioSessionSpy.active)
        #expect(audioSessionSpy.activeOptions.isEmpty)
    }

}
