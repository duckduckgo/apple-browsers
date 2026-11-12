//
//  AppWidthObserverTests.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

class AppWidthObserverTests: XCTestCase {

    func testWhenNotPadThenWillResizeButNotReportAsLarge() {
        let observer = AppWidthObserver()
        observer.isPad = false
        observer.currentWidth = 0
        XCTAssertTrue(observer.willResize(toWidth: 10000))
        XCTAssertFalse(observer.isLargeWidth)
    }

    func testWhenResizesToSameSizeThenWillNotResize() {
        let observer = AppWidthObserver()
        observer.isPad = true
        observer.currentWidth = 0
        XCTAssertTrue(observer.willResize(toWidth: 10000))
        XCTAssertFalse(observer.willResize(toWidth: 10000))
    }

    func testWhenInitialWidthIsLargeThenReportsAsLarge() {
        let observer = AppWidthObserver()
        observer.isPad = true
        observer.currentWidth = 0
        XCTAssertTrue(observer.willResize(toWidth: 10000))
        XCTAssertTrue(observer.isLargeWidth)
    }

    func testWhenInitialWidthIsSmallThenReportsAsSmall() {
        let observer = AppWidthObserver()
        observer.isPad = true
        observer.currentWidth = 0
        XCTAssertTrue(observer.willResize(toWidth: 100))
        XCTAssertFalse(observer.isLargeWidth)
    }

    func testWindowLayoutMatchesTheLowerSafariBreakpoint() {
        let observer = AppWidthObserver(usesWindowLayout: true)
        observer.isPad = true
        XCTAssertTrue(observer.willResize(toWidth: 500))
        XCTAssertTrue(observer.isLargeWidth)
        XCTAssertTrue(observer.willResize(toWidth: 499))
        XCTAssertFalse(observer.isLargeWidth)
    }

    func testWindowLayoutSupportsAnExpandedPhoneWindow() {
        let observer = AppWidthObserver(usesWindowLayout: true)
        observer.isPad = false
        _ = observer.willResize(toWidth: 650)
        XCTAssertTrue(observer.isLargeWidth)
        _ = observer.willResize(toWidth: 499)
        XCTAssertFalse(observer.isLargeWidth)
    }

    func testDisabledWindowLayoutKeepsTheLegacyBreakpoint() {
        let observer = AppWidthObserver()
        observer.isPad = true
        _ = observer.willResize(toWidth: 600)
        XCTAssertFalse(observer.isLargeWidth)
    }

    func testFocusedLayoutCopyPreservesTheWindowPolicy() {
        let focused = AppWidthObserver(usesWindowLayout: true)
        let copy = AppWidthObserver()
        _ = focused.willResize(toWidth: 600)
        copy.update(from: focused)
        XCTAssertTrue(copy.isLargeWidth)
        XCTAssertEqual(copy.currentWidth, 600)
        _ = focused.willResize(toWidth: 400)
        XCTAssertTrue(copy.isLargeWidth)
    }
    
}
