//
//  PromptBarPromptSubmitterTests.swift
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

import AppKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
private struct StubHostWindow: PromptBarHostWindow {
    var isVisible = true
    var isMiniaturized = false
    var isOnActiveSpace = true
    var screenFrame: NSRect?
}

@MainActor
final class PromptBarPromptSubmitterTests: XCTestCase {

    private let screenOne = NSRect(x: 0, y: 0, width: 1440, height: 900)
    private let screenTwo = NSRect(x: 1440, y: 0, width: 1920, height: 1080)

    func testWhenWindowIsOnTheSameScreenThenItCanHostThePrompt() {
        let window = StubHostWindow(screenFrame: screenOne)

        XCTAssertTrue(PromptBarPromptSubmitter.canHostPrompt(window, submittedFromScreenFrame: screenOne))
    }

    func testWhenWindowIsOnAnotherScreenThenItCannotHostThePrompt() {
        let window = StubHostWindow(screenFrame: screenTwo)

        XCTAssertFalse(PromptBarPromptSubmitter.canHostPrompt(window, submittedFromScreenFrame: screenOne))
    }

    func testWhenWindowIsOnAnotherSpaceThenItCannotHostThePrompt() {
        let window = StubHostWindow(isOnActiveSpace: false, screenFrame: screenOne)

        XCTAssertFalse(PromptBarPromptSubmitter.canHostPrompt(window, submittedFromScreenFrame: screenOne))
    }

    func testWhenWindowIsMiniaturizedThenItCannotHostThePrompt() {
        let window = StubHostWindow(isMiniaturized: true, screenFrame: screenOne)

        XCTAssertFalse(PromptBarPromptSubmitter.canHostPrompt(window, submittedFromScreenFrame: screenOne))
    }

    func testWhenWindowIsHiddenThenItCannotHostThePrompt() {
        let window = StubHostWindow(isVisible: false, screenFrame: screenOne)

        XCTAssertFalse(PromptBarPromptSubmitter.canHostPrompt(window, submittedFromScreenFrame: screenOne))
    }

    func testWhenWindowIsOffscreenThenItCannotHostAScreenScopedPrompt() {
        let window = StubHostWindow(screenFrame: nil)

        XCTAssertFalse(PromptBarPromptSubmitter.canHostPrompt(window, submittedFromScreenFrame: screenOne))
    }

    /// With no source screen there is nothing to match against, so reusing a window beats opening one.
    func testWhenSourceScreenIsUnknownThenAnyVisibleWindowCanHostThePrompt() {
        let window = StubHostWindow(screenFrame: screenTwo)

        XCTAssertTrue(PromptBarPromptSubmitter.canHostPrompt(window, submittedFromScreenFrame: nil))
    }

    func testWhenSourceScreenIsUnknownThenAnOffSpaceWindowStillCannotHostThePrompt() {
        let window = StubHostWindow(isOnActiveSpace: false, screenFrame: screenTwo)

        XCTAssertFalse(PromptBarPromptSubmitter.canHostPrompt(window, submittedFromScreenFrame: nil))
    }

    func testWhenPlacingANewWindowThenItIsCenteredOnTheTargetScreen() {
        let droppingPoint = PromptBarPromptSubmitter.newWindowDroppingPoint(in: screenTwo)

        XCTAssertEqual(droppingPoint.x, screenTwo.midX)
        XCTAssertEqual(droppingPoint.y, screenTwo.maxY)
    }

    /// The dropping point is the window's top-center, so a window placed with it stays on the
    /// screen it was placed on rather than cascading onto another display.
    func testWhenPlacingANewWindowThenTheResultingFrameStaysOnTheTargetScreen() {
        let droppingPoint = PromptBarPromptSubmitter.newWindowDroppingPoint(in: screenTwo)
        let windowSize = NSSize(width: 1024, height: 768)
        let origin = NSRect(origin: .zero, size: windowSize).frameOrigin(fromDroppingPoint: droppingPoint)

        let frame = NSRect(origin: origin, size: windowSize)
        XCTAssertTrue(screenTwo.contains(frame))
    }
}
