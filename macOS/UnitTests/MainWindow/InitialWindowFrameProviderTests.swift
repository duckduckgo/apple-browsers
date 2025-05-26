//
//  InitialWindowFrameProviderTests.swift
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

import XCTest
import Cocoa

@testable import DuckDuckGo_Privacy_Browser

final class InitialWindowFrameProviderTests: XCTestCase {

    func testWhenVisibleFrameIsWide_thenAspectRatioIsCappedAndCentered() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 2000, height: 1000)
        let frame = InitialWindowFrameProvider.initialFrame(visibleFrame: visibleFrame)

        let expectedWidth: CGFloat = 900 * (16.0/9.0) // 900 height -> width cap
        let expectedHeight: CGFloat = 900
        let expectedX: CGFloat = (2000 - expectedWidth) / 2
        let expectedY: CGFloat = (1000 - expectedHeight) / 2

        XCTAssertEqual(frame.size.width, expectedWidth, accuracy: 0.1)
        XCTAssertEqual(frame.size.height, expectedHeight, accuracy: 0.1)
        XCTAssertEqual(frame.origin.x, expectedX, accuracy: 0.1)
        XCTAssertEqual(frame.origin.y, expectedY, accuracy: 0.1)
    }

    func testWhenVisibleFrameIsSmall_thenMinimumSizeAndPosition() {
        let visibleFrame = NSRect(x: 10, y: 20, width: 100, height: 100)
        let frame = InitialWindowFrameProvider.initialFrame(visibleFrame: visibleFrame)

        XCTAssertEqual(frame.size.width, 300)
        XCTAssertEqual(frame.size.height, 300)
        XCTAssertEqual(frame.origin.x, 10)
        XCTAssertEqual(frame.origin.y, 20)
    }

    func testWhenVisibleFrameIsVeryLarge_thenMaximumSizeAppliedAndCentered() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 5000, height: 3000)
        let frame = InitialWindowFrameProvider.initialFrame(visibleFrame: visibleFrame)

        XCTAssertEqual(frame.size.width, 1600)
        XCTAssertEqual(frame.size.height, 1200)

        let expectedX: CGFloat = (5000 - 1600) / 2
        let expectedY: CGFloat = (3000 - 1200) / 2
        XCTAssertEqual(frame.origin.x, expectedX)
        XCTAssertEqual(frame.origin.y, expectedY)
    }

    func testWhenVisibleFrameIsStandard_thenNoAspectRatioCap() {
        let visibleFrame = NSRect(x: 100, y: 200, width: 1600, height: 1200)
        let frame = InitialWindowFrameProvider.initialFrame(visibleFrame: visibleFrame)

        let expectedWidth: CGFloat = 1600 * 0.9
        let expectedHeight: CGFloat = 1200 * 0.9
        let expectedX = 100 + (1600 - expectedWidth) / 2
        let expectedY = 200 + (1200 - expectedHeight) / 2

        XCTAssertEqual(frame.size.width, expectedWidth, accuracy: 0.1)
        XCTAssertEqual(frame.size.height, expectedHeight, accuracy: 0.1)
        XCTAssertEqual(frame.origin.x, expectedX, accuracy: 0.1)
        XCTAssertEqual(frame.origin.y, expectedY, accuracy: 0.1)
    }
}
