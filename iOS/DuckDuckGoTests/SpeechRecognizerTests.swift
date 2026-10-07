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
import XCTest
import FeatureFlags_iOS
import Combine
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

@MainActor
@Suite("Voice Search Recognition Routing")
struct VoiceSearchRecognitionRoutingTests {
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func selectsEngineUsingFlag(enabled: Bool) async {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: enabled ? [.speechAnalyzer] : [])
        let legacy = RecordingSpeechRecognizer()
        let modern = RecordingSpeechRecognizer()
        let started = XCTestExpectation(description: "Recording starts")
        legacy.onStart = { started.fulfill() }
        modern.onStart = { started.fulfill() }
        let recognizer = VoiceSearchSpeechRecognizer(featureFlagger: flagger, legacy: legacy, makeAnalyzerRecognizer: { modern })
        recognizer.startRecording(resultHandler: { _, _, _ in }, volumeCallback: { _ in })
        #expect(await XCTWaiter.fulfillment(of: [started], timeout: 2) == .completed)
        #expect(modern.startCount == (enabled ? 1 : 0))
        #expect(legacy.startCount == (enabled ? 0 : 1))
        recognizer.stopRecording()
        #expect(modern.stopCount == (enabled ? 1 : 0))
        #expect(legacy.stopCount == (enabled ? 0 : 1))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func unsupportedAnalyzerFallsBackToLegacy() async {
        let legacy = RecordingSpeechRecognizer()
        let started = XCTestExpectation(description: "Legacy starts")
        legacy.onStart = { started.fulfill() }
        let recognizer = VoiceSearchSpeechRecognizer(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.speechAnalyzer]),
                                                     legacy: legacy, makeAnalyzerRecognizer: { nil })
        recognizer.startRecording(resultHandler: { _, _, _ in }, volumeCallback: { _ in })
        #expect(await XCTWaiter.fulfillment(of: [started], timeout: 2) == .completed)
        #expect(legacy.startCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func flagChangeAppliesToNextSession() async {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.speechAnalyzer])
        let legacy = RecordingSpeechRecognizer()
        let modern = RecordingSpeechRecognizer()
        let modernStarted = XCTestExpectation(description: "Modern starts")
        modern.onStart = { modernStarted.fulfill() }
        let recognizer = VoiceSearchSpeechRecognizer(featureFlagger: flagger, legacy: legacy, makeAnalyzerRecognizer: { modern })
        recognizer.startRecording(resultHandler: { _, _, _ in }, volumeCallback: { _ in })
        #expect(await XCTWaiter.fulfillment(of: [modernStarted], timeout: 2) == .completed)
        flagger.enabledFeatureFlags = []
        flagger.triggerUpdate()
        #expect(modern.stopCount == 0)
        let legacyStarted = XCTestExpectation(description: "Legacy starts")
        legacy.onStart = { legacyStarted.fulfill() }
        recognizer.startRecording(resultHandler: { _, _, _ in }, volumeCallback: { _ in })
        #expect(await XCTWaiter.fulfillment(of: [legacyStarted], timeout: 2) == .completed)
        #expect(modern.stopCount == 1)
        #expect(legacy.startCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func cancellationDuringSelectionDoesNotStartRecording() async {
        let legacy = RecordingSpeechRecognizer()
        let modern = RecordingSpeechRecognizer()
        let selecting = XCTestExpectation(description: "Selection starts")
        let selected = XCTestExpectation(description: "Selection returns")
        var resume: CheckedContinuation<SpeechRecognizerProtocol?, Never>?
        let recognizer = VoiceSearchSpeechRecognizer(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.speechAnalyzer]),
                                                     legacy: legacy, makeAnalyzerRecognizer: {
            let result = await withCheckedContinuation { continuation in
                resume = continuation
                selecting.fulfill()
            }
            selected.fulfill()
            return result
        })
        recognizer.startRecording(resultHandler: { _, _, _ in }, volumeCallback: { _ in })
        #expect(await XCTWaiter.fulfillment(of: [selecting], timeout: 2) == .completed)
        recognizer.stopRecording()
        resume?.resume(returning: modern)
        #expect(await XCTWaiter.fulfillment(of: [selected], timeout: 2) == .completed)
        #expect(modern.startCount == 0)
        #expect(legacy.startCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func failureKeepsOverlayOpenWithRecoveryMessage() async {
        let recognizer = RecordingSpeechRecognizer()
        let model = VoiceSearchFeedbackViewModel(speechRecognizer: recognizer, aiChatSettings: MockAIChatSettingsProvider())
        let delegate = FeedbackDelegate()
        model.delegate = delegate
        let displayed = XCTestExpectation(description: "Error displayed")
        let observation = model.$errorMessage.compactMap { $0 }.first().sink { _ in displayed.fulfill() }
        model.startSpeechRecognizer()
        recognizer.resultHandler?(nil, SpeechRecognizerError.modelUnavailable, true)
        #expect(await XCTWaiter.fulfillment(of: [displayed], timeout: 2) == .completed)
        #expect(model.errorMessage == UserText.voiceSearchModelUnavailable)
        #expect(delegate.completionCount == 0)
        #expect(recognizer.stopCount == 1)
        let previousHandler = recognizer.resultHandler
        model.startSpeechRecognizer()
        #expect(recognizer.startCount == 2)
        #expect(model.errorMessage == nil)
        previousHandler?(nil, SpeechRecognizerError.modelUnavailable, true)
        let staleCallbackProcessed = XCTestExpectation(description: "Old callback processed")
        DispatchQueue.main.async { staleCallbackProcessed.fulfill() }
        #expect(await XCTWaiter.fulfillment(of: [staleCallbackProcessed], timeout: 2) == .completed)
        #expect(model.errorMessage == nil)
        model.cancel()
        #expect(delegate.completionCount == 1)
        withExtendedLifetime(observation) { }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func failureAfterPartialResultPreservesQuery() async {
        let recognizer = RecordingSpeechRecognizer()
        let model = VoiceSearchFeedbackViewModel(speechRecognizer: recognizer, aiChatSettings: MockAIChatSettingsProvider())
        let delegate = FeedbackDelegate()
        let completed = XCTestExpectation(description: "Query completed")
        delegate.onFinish = { completed.fulfill() }
        model.delegate = delegate
        model.startSpeechRecognizer()
        recognizer.resultHandler?("weather tomorrow", nil, false)
        recognizer.resultHandler?(nil, SpeechRecognizerError.audioInputUnavailable, true)
        #expect(await XCTWaiter.fulfillment(of: [completed], timeout: 2) == .completed)
        #expect(delegate.query == "weather tomorrow")
        #expect(delegate.completionCount == 1)
        #expect(model.errorMessage == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func errorMessagesDescribeRecovery() {
        #expect(VoiceSearchFeedbackViewModel.message(for: SpeechRecognizerError.recognitionUnavailable) == UserText.voiceSearchRecognitionUnavailable)
        #expect(VoiceSearchFeedbackViewModel.message(for: SpeechRecognizerError.modelUnavailable) == UserText.voiceSearchModelUnavailable)
        #expect(VoiceSearchFeedbackViewModel.message(for: SpeechRecognizerError.audioInputUnavailable) == UserText.voiceSearchAudioUnavailable)
        #expect(VoiceSearchFeedbackViewModel.message(for: NSError(domain: "other", code: 1)) == UserText.voiceSearchFailed)
    }
}

private final class RecordingSpeechRecognizer: SpeechRecognizerProtocol {
    var isAvailable = true
    var startCount = 0
    var stopCount = 0
    var onStart: (() -> Void)?
    var resultHandler: ((String?, Error?, Bool) -> Void)?

    static func requestMicAccess(withHandler handler: @escaping (Bool) -> Void) { handler(true) }
    func getVolumeLevel(from channelData: UnsafeMutablePointer<Float>) -> Float { 0 }
    func stopRecording() { stopCount += 1 }
    func startRecording(resultHandler: @escaping (String?, Error?, Bool) -> Void, volumeCallback: @escaping (Float) -> Void) {
        self.resultHandler = resultHandler
        startCount += 1
        onStart?()
    }
}

private final class FeedbackDelegate: VoiceSearchFeedbackViewModelDelegate {
    var completionCount = 0
    var query: String?
    var onFinish: (() -> Void)?

    func voiceSearchFeedbackViewModel(_ model: VoiceSearchFeedbackViewModel, didFinishQuery query: String?, target: VoiceSearchTarget) {
        completionCount += 1
        self.query = query
        onFinish?()
    }
}
