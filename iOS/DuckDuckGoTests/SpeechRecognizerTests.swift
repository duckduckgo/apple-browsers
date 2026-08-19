//
//  SpeechRecognizerTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import AVFoundation
import Testing
@testable import DuckDuckGo

@Suite("Speech Recognizer Tests")
struct SpeechRecognizerTests {

    // AVFAudio raises `IsFormatSampleRateAndChannelCountValid` if a tap is installed with either value at zero.
    @available(iOS 16, macOS 13, *)
    @Test(
        "Degraded input format is rejected",
        .timeLimit(.minutes(1)),
        arguments: zip(
            [0, 0, 44100] as [Double],
            [0, 1, 0] as [AVAudioChannelCount]
        )
    )
    func testWhenFormatHasNoSampleRateOrNoChannelsThenItIsNotValidForRecording(sampleRate: Double,
                                                                               channelCount: AVAudioChannelCount) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount))

        #expect(SpeechRecognizer.isValidRecordingFormat(format) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Usable input format is accepted", .timeLimit(.minutes(1)))
    func testWhenFormatHasSampleRateAndChannelsThenItIsValidForRecording() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))

        #expect(SpeechRecognizer.isValidRecordingFormat(format))
    }
}
