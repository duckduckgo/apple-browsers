//
//  InlineVoiceToTextSessionTests.swift
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

import XCTest
@testable import DuckDuckGo

@MainActor
final class InlineVoiceToTextSessionTests: XCTestCase {

    private var recognizer: MockInlineSpeechRecognizer!
    private var changes: [String] = []
    private var ends: [(text: String, reason: InlineVoiceToTextSession.EndReason)] = []

    override func setUp() {
        super.setUp()
        recognizer = MockInlineSpeechRecognizer()
        changes = []
        ends = []
    }

    override func tearDown() {
        recognizer = nil
        super.tearDown()
    }

    private func makeSession(baseText: String = "") -> InlineVoiceToTextSession {
        let session = InlineVoiceToTextSession(baseText: baseText,
                                               speechRecognizer: recognizer,
                                               dispatchToMain: { work in MainActor.assumeIsolated(work) })
        session.onTextChange = { [weak self] in self?.changes.append($0) }
        session.onEnd = { [weak self] in self?.ends.append(($0, $1)) }
        return session
    }

    func testComposeJoinsTranscriptToTypedTextWithOneSpace() {
        XCTAssertEqual(InlineVoiceToTextSession.compose(baseText: "", transcript: "hello"), "hello")
        XCTAssertEqual(InlineVoiceToTextSession.compose(baseText: "weather", transcript: "in Lisbon"), "weather in Lisbon")
        XCTAssertEqual(InlineVoiceToTextSession.compose(baseText: "weather ", transcript: "in Lisbon"), "weather in Lisbon")
        XCTAssertEqual(InlineVoiceToTextSession.compose(baseText: "weather", transcript: ""), "weather")
    }

    func testWhenStartedThenRecordsAndReportsEachPartialTranscript() {
        let session = makeSession()

        session.start()
        recognizer.emit("Congratulate John")
        recognizer.emit("Congratulate John on his new pro")

        XCTAssertTrue(session.isListening)
        XCTAssertEqual(recognizer.startCount, 1)
        XCTAssertEqual(changes, ["Congratulate John", "Congratulate John on his new pro"])
        XCTAssertTrue(ends.isEmpty)
    }

    func testWhenTextWasTypedThenTranscriptIsAppendedToIt() {
        let session = makeSession(baseText: "weather")

        session.start()
        recognizer.emit("in Lisbon")

        XCTAssertEqual(changes, ["weather in Lisbon"])
    }

    func testWhenSpeechFinishesThenEndsOnceWithFinalText() {
        let session = makeSession()

        session.start()
        recognizer.emit("hello there", isFinal: true)
        recognizer.emit("ignored after the end")

        XCTAssertFalse(session.isListening)
        XCTAssertEqual(ends.count, 1)
        XCTAssertEqual(ends.first?.text, "hello there")
        XCTAssertEqual(ends.first?.reason, .speechFinished)
        XCTAssertEqual(recognizer.stopCount, 1)
    }

    func testWhenStoppedThenKeepsTranscriptAndStopsRecording() {
        let session = makeSession(baseText: "ducks")

        session.start()
        recognizer.emit("and geese")
        session.stop()
        session.stop()

        XCTAssertEqual(ends.count, 1)
        XCTAssertEqual(ends.first?.text, "ducks and geese")
        XCTAssertEqual(ends.first?.reason, .stopped)
        XCTAssertEqual(recognizer.stopCount, 1)
    }

    func testWhenRecordingFailsBeforeAnySpeechThenEndsAsFailedWithOriginalText() {
        let session = makeSession(baseText: "typed")

        session.start()
        recognizer.emit(nil, error: TestError.failed, isFinal: true)

        XCTAssertEqual(ends.first?.text, "typed")
        XCTAssertEqual(ends.first?.reason, .failed)
        XCTAssertTrue(changes.isEmpty)
    }

    func testWhenRecordingFailsAfterSpeechThenEndsAsFailedKeepingWhatWasHeard() {
        let session = makeSession()

        session.start()
        recognizer.emit("half a sen")
        recognizer.emit(nil, error: TestError.failed, isFinal: false)

        XCTAssertEqual(ends.first?.text, "half a sen")
        XCTAssertEqual(ends.first?.reason, .failed)
    }

    func testWhenStoppedThenCannotBeRestarted() {
        let session = makeSession()

        session.start()
        session.stop()
        session.start()

        XCTAssertEqual(recognizer.startCount, 1)
        XCTAssertFalse(session.isListening)
    }

    private enum TestError: Error {
        case failed
    }
}

final class MockInlineSpeechRecognizer: SpeechRecognizerProtocol {

    var isAvailable = true
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var resultHandler: ((String?, Error?, Bool) -> Void)?

    static func requestMicAccess(withHandler handler: @escaping (Bool) -> Void) {
        handler(true)
    }

    func getVolumeLevel(from channelData: UnsafeMutablePointer<Float>) -> Float { 0 }

    func startRecording(resultHandler: @escaping (String?, Error?, Bool) -> Void,
                        volumeCallback: @escaping (Float) -> Void) {
        startCount += 1
        self.resultHandler = resultHandler
    }

    func stopRecording() {
        stopCount += 1
    }

    func emit(_ text: String?, error: Error? = nil, isFinal: Bool = false) {
        resultHandler?(text, error, isFinal)
    }
}
