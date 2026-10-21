//
//  DaxPetCoordinatorTests.swift
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
final class DaxPetCoordinatorTests: XCTestCase {

    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    private let secondScreen = NSRect(x: 1440, y: 0, width: 1920, height: 1080)

    private func characterFrame(at origin: NSPoint) -> NSRect {
        DaxPetView.Metrics.characterFrame().offsetBy(dx: origin.x, dy: origin.y)
    }

    func testWhenDaxIsWhollyOnScreenThenHeStaysPut() {
        let origin = NSPoint(x: 500, y: 100)

        XCTAssertEqual(DaxPetCoordinator.origin(keepingCharacterOnScreenFor: origin, visibleFrames: [screen]), origin)
    }

    func testWhenDaxHangsOffTheLeftEdgeThenHeSlidesBackOn() {
        let origin = NSPoint(x: -characterFrame(at: .zero).midX, y: 100)

        let corrected = DaxPetCoordinator.origin(keepingCharacterOnScreenFor: origin, visibleFrames: [screen])

        XCTAssertEqual(characterFrame(at: corrected).minX, screen.minX, accuracy: 0.001)
        XCTAssertEqual(corrected.y, origin.y)
    }

    func testWhenDaxHangsBelowTheBottomThenHeIsLiftedBackUp() {
        let origin = NSPoint(x: 500, y: -characterFrame(at: .zero).maxY + 10)

        let corrected = DaxPetCoordinator.origin(keepingCharacterOnScreenFor: origin, visibleFrames: [screen])

        XCTAssertEqual(characterFrame(at: corrected).minY, screen.minY, accuracy: 0.001)
    }

    func testWhenDaxStraddlesTwoScreensThenHeLandsOnTheOneHeIsMostlyOn() {
        let character = characterFrame(at: .zero)
        let origin = NSPoint(x: secondScreen.minX - character.minX - character.width * 0.3, y: 100)

        let corrected = DaxPetCoordinator.origin(keepingCharacterOnScreenFor: origin, visibleFrames: [screen, secondScreen])

        XCTAssertEqual(characterFrame(at: corrected).minX, secondScreen.minX, accuracy: 0.001)
    }
}
