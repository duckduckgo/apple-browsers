//
//  DaxCharacterViewTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class DaxCharacterViewTests: XCTestCase {

    private var idleTime: TimeInterval = 0
    private var character: DaxCharacterView!

    override func setUp() {
        super.setUp()
        idleTime = 0
        character = DaxCharacterView(reduceMotion: { true }, idleTime: { [unowned self] in idleTime })
    }

    override func tearDown() {
        character = nil
        super.tearDown()
    }

    // MARK: - Sleep

    func testWhenTheMacIsLeftAlonePastTheSleepDelayThenDaxFallsAsleep() {
        var changes: [Bool] = []
        character.onSleepChange = { changes.append($0) }

        idleTime = DaxCharacterView.sleepDelay - 1
        character.step()
        XCTAssertFalse(character.isAsleep)

        idleTime = DaxCharacterView.sleepDelay
        character.step()
        character.step()

        XCTAssertTrue(character.isAsleep)
        XCTAssertEqual(changes, [true])
    }

    func testWhenInputResumesThenDaxWakesUp() {
        idleTime = DaxCharacterView.sleepDelay
        character.step()
        var changes: [Bool] = []
        character.onSleepChange = { changes.append($0) }

        idleTime = 0
        character.step()

        XCTAssertFalse(character.isAsleep)
        XCTAssertEqual(changes, [false])
    }

    func testWhenDaxIsListeningThenHeNeverFallsAsleep() {
        character.mood = .listening
        idleTime = DaxCharacterView.sleepDelay * 2

        character.step()

        XCTAssertFalse(character.isAsleep)
    }

    func testWhenDaxIsWokenByAMoodChangeThenHeStaysAwake() {
        idleTime = DaxCharacterView.sleepDelay
        character.step()

        character.mood = .thinking
        character.step()

        XCTAssertFalse(character.isAsleep)
    }
}
