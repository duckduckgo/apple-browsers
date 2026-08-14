//
//  SelectionFrameUserScriptTests.swift
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

import BrowserServicesKitTestsUtils
import WebKit
import XCTest
@testable import DuckDuckGo

final class SelectionFrameUserScriptTests: XCTestCase {

    private var sut: SelectionFrameUserScript!

    override func setUp() {
        super.setUp()
        sut = SelectionFrameUserScript(isEnabled: true)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    private func frame(isMainFrame: Bool = false, host: String = "example.com") -> WKFrameInfo {
        .mock(isMainFrame: isMainFrame, securityOriginHost: host)
    }

    private func body(hasSelection: Bool, timestamp: Double = 1) -> [String: Any] {
        ["hasSelection": hasSelection, "eventTimestamp": timestamp]
    }

    // MARK: - Messaging

    func testWhenInspectingFeatureNameThenItMatchesContentScopeScripts() {
        XCTAssertEqual(sut.featureName, "textSelection")
    }

    func testWhenRequestingKnownMethodsThenHandlersAreReturned() {
        XCTAssertNotNil(sut.handler(forMethodNamed: "isEnabled"))
        XCTAssertNotNil(sut.handler(forMethodNamed: "selectionFrameChanged"))
    }

    func testWhenRequestingUnknownMethodThenHandlerIsNil() {
        XCTAssertNil(sut.handler(forMethodNamed: "unknown"))
    }

    func testWhenFeatureIsEnabledThenEnableRequestReturnsTrue() async throws {
        let handler = try XCTUnwrap(sut.handler(forMethodNamed: "isEnabled"))

        let response = try await handler([:], WKScriptMessage())

        XCTAssertEqual(response as? SelectionFrameEnabledResponse, SelectionFrameEnabledResponse(enabled: true))
    }

    func testWhenFeatureIsDisabledThenEnableRequestReturnsFalse() async throws {
        sut = SelectionFrameUserScript(isEnabled: false)
        let handler = try XCTUnwrap(sut.handler(forMethodNamed: "isEnabled"))

        let response = try await handler([:], WKScriptMessage())

        XCTAssertEqual(response as? SelectionFrameEnabledResponse, SelectionFrameEnabledResponse(enabled: false))
    }

    // MARK: - Frame Claims

    func testNoFrameClaimExistsInitially() {
        XCTAssertNil(sut.frameWithSelection)
    }

    func testStoresTheFrameThatReportsASelection() {
        sut.update(with: body(hasSelection: true), from: frame())

        XCTAssertNotNil(sut.frameWithSelection)
    }

    func testTheClaimingFrameCanClearItsOwnClaim() {
        sut.update(with: body(hasSelection: true, timestamp: 1), from: frame())

        sut.update(with: body(hasSelection: false, timestamp: 2), from: frame())

        XCTAssertNil(sut.frameWithSelection)
    }

    func testAnOlderClearFromAnotherFrameCannotClearTheCurrentClaim() {
        let iframe = frame(host: "iframe.example")
        sut.update(with: body(hasSelection: true, timestamp: 2), from: iframe)

        sut.update(with: body(hasSelection: false, timestamp: 1), from: frame(isMainFrame: true))

        XCTAssertNotNil(sut.frameWithSelection)
    }

    func testTheMostRecentReportingFrameWins() {
        sut.update(with: body(hasSelection: true, timestamp: 1), from: frame(host: "first.example"))
        sut.update(with: body(hasSelection: true, timestamp: 2), from: frame(host: "second.example"))

        sut.update(with: body(hasSelection: false, timestamp: 3), from: frame(host: "first.example"))
        XCTAssertNil(sut.frameWithSelection)
    }

    func testAnOlderClaimCannotReplaceANewerClaim() {
        sut.update(with: body(hasSelection: true, timestamp: 2), from: frame(host: "newer.example"))

        sut.update(with: body(hasSelection: true, timestamp: 1), from: frame(host: "older.example"))

        let text = sut.frameWithSelection?.selectedText(from: ["eventTimestamp": 2.0, "selectedText": "selection"])
        XCTAssertEqual(text, "selection")
    }

    func testAnOlderClearCannotReleaseANewerClaim() {
        sut.update(with: body(hasSelection: true, timestamp: 2), from: frame())

        sut.update(with: body(hasSelection: false, timestamp: 1), from: frame())

        XCTAssertNotNil(sut.frameWithSelection)
    }

    func testAnAcceptedClearPreventsAnOlderClaimFromArrivingLate() {
        sut.update(with: body(hasSelection: true, timestamp: 1), from: frame())
        sut.update(with: body(hasSelection: false, timestamp: 3), from: frame())

        sut.update(with: body(hasSelection: true, timestamp: 2), from: frame(host: "late.example"))

        XCTAssertNil(sut.frameWithSelection)
    }

    func testReadAcceptsTextFromTheCurrentSelection() {
        sut.update(with: body(hasSelection: true, timestamp: 1), from: frame())

        let text = sut.frameWithSelection?.selectedText(from: ["eventTimestamp": 1.0, "selectedText": "selection"])

        XCTAssertEqual(text, "selection")
    }

    func testReadRejectsTextFromAReplacementSelection() {
        sut.update(with: body(hasSelection: true, timestamp: 1), from: frame())

        let text = sut.frameWithSelection?.selectedText(from: ["eventTimestamp": 2.0, "selectedText": "wrong selection"])

        XCTAssertNil(text)
    }

    func testResetReleasesTheFrameClaim() {
        sut.update(with: body(hasSelection: true, timestamp: 2), from: frame())

        sut.reset()

        XCTAssertNil(sut.frameWithSelection)

        sut.update(with: body(hasSelection: true, timestamp: 1), from: frame())
        XCTAssertNotNil(sut.frameWithSelection)
    }

    // MARK: - Malformed input

    func testAnUnreadableBodyLeavesTheCurrentFrameClaimAlone() {
        sut.update(with: body(hasSelection: true), from: frame())

        sut.update(with: "not a dictionary", from: frame())
        sut.update(with: ["somethingElse": true], from: frame())
        sut.update(with: ["hasSelection": "yes", "eventTimestamp": 2.0], from: frame())
        sut.update(with: ["hasSelection": false], from: frame())
        sut.update(with: ["hasSelection": true, "eventTimestamp": "newer"], from: frame())
        sut.update(with: body(hasSelection: true, timestamp: .infinity), from: frame())

        XCTAssertNotNil(sut.frameWithSelection)
    }
}
