//
//  QuitSurveyReturnUserHandlerTests.swift
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

import PixelKit
import PixelKitTestingUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class QuitSurveyReturnUserHandlerTests: XCTestCase {

    private var persistor: MockQuitSurveyPersistor!
    private var pixelMock: PixelKitMock!
    private var installDate: Date!
    private var currentDate: Date!

    override func setUp() {
        super.setUp()
        persistor = MockQuitSurveyPersistor()
        pixelMock = PixelKitMock(expecting: [])
        installDate = Date()
        currentDate = installDate
    }

    override func tearDown() {
        persistor = nil
        pixelMock = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeHandler() -> QuitSurveyReturnUserHandler {
        QuitSurveyReturnUserHandler(
            persistor: persistor,
            installDate: installDate,
            dateProvider: { [unowned self] in currentDate },
            pixelFiring: pixelMock
        )
    }

    private func advanceDays(_ days: Double) {
        currentDate = installDate.addingTimeInterval(days * 24 * 60 * 60)
    }

    // MARK: - No Pending State

    func testWhenNoPendingStateNoPixelFires() {
        let handler = makeHandler()
        advanceDays(10)

        handler.fireReturnUserPixelIfNeeded()

        XCTAssertTrue(pixelMock.actualFireCalls.isEmpty)
    }

    // MARK: - Thumbs Down (reasons) Path

    func testWhenThumbsDownOnlyAndWithinWindowFiresReturnUserPixel() {
        persistor.pendingReturnUserReasons = "reason=1"
        let handler = makeHandler()
        advanceDays(10)

        handler.fireReturnUserPixelIfNeeded()

        let fired = pixelMock.actualFireCalls.first { $0.pixel.name == QuitSurveyPixelName.quitSurveyReturnUser.rawValue }
        XCTAssertNotNil(fired)
    }

    func testWhenThumbsDownFiresPixelReasonsAreCleared() {
        persistor.pendingReturnUserReasons = "reason=1"
        let handler = makeHandler()
        advanceDays(10)

        handler.fireReturnUserPixelIfNeeded()

        XCTAssertNil(persistor.pendingReturnUserReasons)
    }

    func testWhenThumbsDownFiresThumbsUpFlagIsNotTouched() {
        persistor.pendingReturnUserReasons = "reason=1"
        let handler = makeHandler()
        advanceDays(10)

        handler.fireReturnUserPixelIfNeeded()

        XCTAssertNil(persistor.hasSelectedThumbsUp)
    }

    // MARK: - Thumbs Up Path

    func testWhenThumbsUpOnlyAndWithinWindowFiresThumbsUpReturnPixel() {
        persistor.hasSelectedThumbsUp = true
        let handler = makeHandler()
        advanceDays(10)

        handler.fireReturnUserPixelIfNeeded()

        let fired = pixelMock.actualFireCalls.first { $0.pixel.name == QuitSurveyPixelName.quitSurveyThumbsUpReturnUser.rawValue }
        XCTAssertNotNil(fired)
    }

    func testWhenThumbsUpFiresPixelFlagIsCleared() {
        persistor.hasSelectedThumbsUp = true
        let handler = makeHandler()
        advanceDays(10)

        handler.fireReturnUserPixelIfNeeded()

        XCTAssertNil(persistor.hasSelectedThumbsUp)
    }

    func testWhenThumbsUpFiresPendingReasonsAreNotTouched() {
        persistor.hasSelectedThumbsUp = true
        let handler = makeHandler()
        advanceDays(10)

        handler.fireReturnUserPixelIfNeeded()

        XCTAssertNil(persistor.pendingReturnUserReasons)
    }

    // MARK: - Before Day 8 Window

    func testWhenBeforeDay8NoPixelFires() {
        persistor.pendingReturnUserReasons = "reason=1"
        let handler = makeHandler()
        advanceDays(5)

        handler.fireReturnUserPixelIfNeeded()

        XCTAssertTrue(pixelMock.actualFireCalls.isEmpty)
    }

    func testWhenBeforeDay8StateIsPreserved() {
        persistor.pendingReturnUserReasons = "reason=1"
        persistor.hasSelectedThumbsUp = true
        let handler = makeHandler()
        advanceDays(5)

        handler.fireReturnUserPixelIfNeeded()

        XCTAssertEqual(persistor.pendingReturnUserReasons, "reason=1")
        XCTAssertEqual(persistor.hasSelectedThumbsUp, true)
    }

    func testThumbsUpBeforeDay8NoPixelFires() {
        persistor.hasSelectedThumbsUp = true
        let handler = makeHandler()
        advanceDays(5)

        handler.fireReturnUserPixelIfNeeded()

        XCTAssertTrue(pixelMock.actualFireCalls.isEmpty)
    }

    // MARK: - After Day 14 Window

    func testWhenAfterDay14NoPixelFires() {
        persistor.pendingReturnUserReasons = "reason=1"
        let handler = makeHandler()
        advanceDays(15)

        handler.fireReturnUserPixelIfNeeded()

        XCTAssertTrue(pixelMock.actualFireCalls.isEmpty)
    }

    func testWhenAfterDay14BothFlagsAreCleared() {
        persistor.pendingReturnUserReasons = "reason=1"
        persistor.hasSelectedThumbsUp = true
        let handler = makeHandler()
        advanceDays(15)

        handler.fireReturnUserPixelIfNeeded()

        XCTAssertNil(persistor.pendingReturnUserReasons)
        XCTAssertNil(persistor.hasSelectedThumbsUp)
    }

    // MARK: - Both Flags Set

    func testWhenBothFlagsSetReasonsPixelFiresFirst() {
        persistor.pendingReturnUserReasons = "reason=1"
        persistor.hasSelectedThumbsUp = true
        let handler = makeHandler()
        advanceDays(10)

        handler.fireReturnUserPixelIfNeeded()

        let fired = pixelMock.actualFireCalls.map { $0.pixel.name }
        XCTAssertTrue(fired.contains(QuitSurveyPixelName.quitSurveyReturnUser.rawValue))
        XCTAssertFalse(fired.contains(QuitSurveyPixelName.quitSurveyThumbsUpReturnUser.rawValue))
    }

    func testWhenBothFlagsSetReasonsAreClearedButThumbsUpRemains() {
        persistor.pendingReturnUserReasons = "reason=1"
        persistor.hasSelectedThumbsUp = true
        let handler = makeHandler()
        advanceDays(10)

        handler.fireReturnUserPixelIfNeeded()

        XCTAssertNil(persistor.pendingReturnUserReasons)
        XCTAssertEqual(persistor.hasSelectedThumbsUp, true)
    }
}
