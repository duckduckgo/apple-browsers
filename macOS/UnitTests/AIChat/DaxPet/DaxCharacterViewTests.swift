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
    private var mouseLocation = NSPoint(x: -1000, y: -1000)
    private var character: DaxCharacterView!
    private var window: NSWindow?

    override func setUp() {
        super.setUp()
        idleTime = 0
        character = DaxCharacterView(reduceMotion: { true },
                                     idleTime: { [unowned self] in idleTime },
                                     mouseLocation: { [unowned self] in mouseLocation })
    }

    override func tearDown() {
        window?.close()
        window = nil
        character = nil
        super.tearDown()
    }

    /// Puts Dax on screen at a known place, so cursor positions can be over him or not.
    private func showCharacter() -> NSRect {
        let frame = NSRect(origin: NSPoint(x: 200, y: 200), size: DaxCharacterView.preferredSize)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = character
        self.window = window
        return window.convertToScreen(character.convert(character.bounds, to: nil))
    }

    /// Strokes the cursor left and right across Dax, one frame per move.
    private func pet(frames: Int, over frame: NSRect) {
        for index in 0..<frames {
            mouseLocation = NSPoint(x: frame.midX + (index.isMultiple(of: 2) ? -20 : 20), y: frame.midY)
            character.step()
        }
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

    // MARK: - Petting

    func testWhenTheCursorStrokesDaxBackAndForthThenHeIsPetted() {
        let frame = showCharacter()

        pet(frames: 10, over: frame)

        XCTAssertTrue(character.isBeingPetted)
    }

    func testWhenTheCursorStrokesBesideDaxThenHeIsNotPetted() {
        let frame = showCharacter().offsetBy(dx: 400, dy: 0)

        pet(frames: 30, over: frame)

        XCTAssertFalse(character.isBeingPetted)
    }

    func testWhenPettingStopsThenDaxCalmsDown() {
        let frame = showCharacter()
        pet(frames: 10, over: frame)

        for _ in 0..<90 { character.step() }

        XCTAssertFalse(character.isBeingPetted)
    }

    func testWhenPettedLongEnoughThenDaxShowsHisLoveOnce() {
        let frame = showCharacter()
        var loved = 0
        character.onLovedPetting = { loved += 1 }

        pet(frames: 30, over: frame)
        XCTAssertEqual(loved, 0)

        pet(frames: Int(DaxCharacterView.lovedPettingDuration * 30) + 10, over: frame)

        XCTAssertEqual(loved, 1)
    }

    // MARK: - Dragging

    func testWhenCarriedToTheRightThenDaxLeansBack() {
        _ = showCharacter()
        character.beginDrag()

        for _ in 0..<5 {
            window?.setFrameOrigin(NSPoint(x: (window?.frame.minX ?? 0) + 20, y: 200))
            character.step()
        }

        XCTAssertTrue(character.isBeingDragged)
        XCTAssertGreaterThan(character.dragTilt, 0.1)
    }

    func testWhenCarriedToTheLeftThenDaxLeansTheOtherWay() {
        _ = showCharacter()
        character.beginDrag()

        for _ in 0..<5 {
            window?.setFrameOrigin(NSPoint(x: (window?.frame.minX ?? 0) - 20, y: 200))
            character.step()
        }

        XCTAssertLessThan(character.dragTilt, -0.1)
    }

    func testWhenPutDownThenDaxStraightensUp() {
        _ = showCharacter()
        character.beginDrag()
        window?.setFrameOrigin(NSPoint(x: 300, y: 200))
        character.step()

        character.endDrag()
        for _ in 0..<60 { character.step() }

        XCTAssertFalse(character.isBeingDragged)
        XCTAssertEqual(character.dragTilt, 0, accuracy: 0.01)
    }

    func testWhenCarriedThenTheCursorMovingWithHimIsNotPetting() {
        let frame = showCharacter()
        character.beginDrag()

        pet(frames: 30, over: frame)

        XCTAssertFalse(character.isBeingPetted)
    }

    // MARK: - Screen edges

    private func showCharacter(nearLeftEdgeBy gap: CGFloat) throws -> NSRect {
        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let frame = showCharacter()
        window?.setFrameOrigin(NSPoint(x: screen.minX + gap, y: screen.minY + 100))
        return window?.frame ?? frame
    }

    func testWhenStandingAgainstTheLeftEdgeThenDaxFeelsTheWall() throws {
        _ = try showCharacter(nearLeftEdgeBy: 0)

        character.step()

        XCTAssertEqual(character.wallProximity, -1, accuracy: 0.001)
    }

    func testWhenStandingNearTheLeftEdgeThenDaxFeelsItLess() throws {
        _ = try showCharacter(nearLeftEdgeBy: DaxCharacterView.wallDistance / 2)

        character.step()

        XCTAssertEqual(character.wallProximity, -0.5, accuracy: 0.001)
    }

    func testWhenStandingAwayFromTheEdgesThenDaxFeelsNoWall() throws {
        _ = try showCharacter(nearLeftEdgeBy: 300)

        character.step()

        XCTAssertEqual(character.wallProximity, 0)
    }
    // MARK: - Poses

    private func makeLivelyCharacter() -> DaxCharacterView {
        DaxCharacterView(reduceMotion: { false },
                         idleTime: { [unowned self] in idleTime },
                         mouseLocation: { [unowned self] in mouseLocation })
    }

    func testWhenThinkingThenDaxPondersUntilHeIsDone() {
        character = makeLivelyCharacter()

        character.mood = .thinking
        XCTAssertTrue(character.isPondering)

        character.mood = .idle
        XCTAssertFalse(character.isPondering)
    }

    func testWhenMotionIsReducedThenDaxThinksWithoutTheWing() {
        character.mood = .thinking

        XCTAssertFalse(character.isPondering)
    }

    func testWhenCelebratingThenDaxFlapsForAMoment() {
        character = makeLivelyCharacter()

        character.celebrate()
        XCTAssertTrue(character.isCelebrating)

        for _ in 0..<40 { character.step() }
        XCTAssertFalse(character.isCelebrating)
    }

    func testWhenPettedLongEnoughThenDaxAlsoFlaps() {
        character = makeLivelyCharacter()
        let frame = showCharacter()

        pet(frames: Int(DaxCharacterView.lovedPettingDuration * 30) + 10, over: frame)

        XCTAssertTrue(character.isCelebrating)
    }

    // MARK: - Strolls

    func testWhenStrollingThenDaxWalksOutAndComesBackToHisSpot() throws {
        character = makeLivelyCharacter()
        let start = try showCharacter(nearLeftEdgeBy: 300).origin
        var ended = 0
        character.onStrollEnded = { ended += 1 }

        character.stroll(by: 30)
        var furthest: CGFloat = 0
        for _ in 0..<300 where character.isStrolling {
            character.step()
            furthest = max(furthest, (window?.frame.minX ?? 0) - start.x)
        }

        XCTAssertEqual(furthest, 30, accuracy: 0.5)
        XCTAssertFalse(character.isStrolling)
        XCTAssertEqual(window?.frame.origin, start)
        XCTAssertEqual(ended, 1)
    }

    func testWhenStrollingLeftThenDaxWalksLeft() throws {
        character = makeLivelyCharacter()
        let start = try showCharacter(nearLeftEdgeBy: 300).origin

        character.stroll(by: -30)
        for _ in 0..<10 { character.step() }

        XCTAssertLessThan(window?.frame.minX ?? 0, start.x)
    }

    func testWhenSomethingHappensMidStrollThenDaxStopsWhereHeIs() throws {
        character = makeLivelyCharacter()
        let start = try showCharacter(nearLeftEdgeBy: 300).origin
        var ended = 0
        character.onStrollEnded = { ended += 1 }
        character.stroll(by: 60)
        for _ in 0..<10 { character.step() }

        character.mood = .listening
        character.step()

        XCTAssertFalse(character.isStrolling)
        XCTAssertNotEqual(window?.frame.origin, start)
        XCTAssertEqual(ended, 1)
    }

    func testWhenMotionIsReducedThenDaxNeverStrolls() throws {
        _ = try showCharacter(nearLeftEdgeBy: 300)

        character.stroll(by: 30)

        XCTAssertFalse(character.isStrolling)
    }
}
