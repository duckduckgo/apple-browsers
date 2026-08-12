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

    private func body(hasSelection: Bool, token: String) -> [String: Any] {
        ["hasSelection": hasSelection, "frameToken": token]
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

    // MARK: - Tracking

    func testNoFrameIsTrackedInitially() {
        XCTAssertNil(sut.frameWithSelection)
    }

    func testTracksTheFrameThatReportsASelection() {
        sut.update(with: body(hasSelection: true, token: "a"), from: frame())

        XCTAssertNotNil(sut.frameWithSelection)
    }

    func testTheTrackedFrameCanClearItsOwnClaim() {
        sut.update(with: body(hasSelection: true, token: "a"), from: frame())

        sut.update(with: body(hasSelection: false, token: "a"), from: frame())

        XCTAssertNil(sut.frameWithSelection)
    }

    /// Selecting in an iframe collapses the main frame's selection, whose empty report can arrive last.
    func testAnotherFrameCannotClearTheTrackedFramesClaim() {
        let iframe = frame(host: "iframe.example")
        sut.update(with: body(hasSelection: true, token: "iframe"), from: iframe)

        sut.update(with: body(hasSelection: false, token: "mainFrame"), from: frame(isMainFrame: true))

        XCTAssertNotNil(sut.frameWithSelection)
    }

    func testTheMostRecentReportingFrameWins() {
        sut.update(with: body(hasSelection: true, token: "first"), from: frame(host: "first.example"))
        sut.update(with: body(hasSelection: true, token: "second"), from: frame(host: "second.example"))

        // The second frame now owns the claim, so only its token can release it.
        sut.update(with: body(hasSelection: false, token: "first"), from: frame(host: "first.example"))
        XCTAssertNotNil(sut.frameWithSelection)

        sut.update(with: body(hasSelection: false, token: "second"), from: frame(host: "second.example"))
        XCTAssertNil(sut.frameWithSelection)
    }

    func testReadAcceptsTextFromTheTrackedDocument() {
        sut.update(with: body(hasSelection: true, token: "expected"), from: frame())

        let text = sut.frameWithSelection?.selectedText(from: ["frameToken": "expected", "selectedText": "selection"])

        XCTAssertEqual(text, "selection")
    }

    func testReadRejectsTextFromAReplacementDocument() {
        sut.update(with: body(hasSelection: true, token: "expected"), from: frame())

        let text = sut.frameWithSelection?.selectedText(from: ["frameToken": "replacement", "selectedText": "wrong selection"])

        XCTAssertNil(text)
    }

    func testResetReleasesTheTrackedFrame() {
        sut.update(with: body(hasSelection: true, token: "a"), from: frame())

        sut.reset()

        XCTAssertNil(sut.frameWithSelection)
    }

    // MARK: - Malformed input

    func testAnUnreadableBodyLeavesTheTrackedFrameAlone() {
        sut.update(with: body(hasSelection: true, token: "a"), from: frame())

        sut.update(with: "not a dictionary", from: frame())
        sut.update(with: ["somethingElse": true], from: frame())
        sut.update(with: ["hasSelection": "yes", "frameToken": "a"], from: frame())
        sut.update(with: ["hasSelection": false], from: frame())

        XCTAssertNotNil(sut.frameWithSelection)
    }
}
