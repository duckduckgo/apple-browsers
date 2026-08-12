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
        sut = SelectionFrameUserScript()
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

    // MARK: - Injection

    func testRunsInEveryFrame() {
        XCTAssertFalse(sut.forMainFrameOnly)
    }

    func testInjectsAtDocumentStart() {
        XCTAssertEqual(sut.injectionTime, .atDocumentStart)
    }

    /// A rename on one side only would silently stop tracking.
    func testListensOnTheNameTheScriptPostsTo() {
        XCTAssertEqual(sut.messageNames, ["selectionFrameChanged"])
        XCTAssertTrue(sut.source.contains("messageHandlers.selectionFrameChanged"))
    }

    /// An empty source means the resource is missing from the bundle.
    func testTheScriptIsBundledWithTheApp() {
        XCTAssertFalse(sut.source.isEmpty)
    }

    func testOnlyReportsOnTheEmptyToNonEmptyTransition() {
        XCTAssertTrue(sut.source.contains("lastHasSelection"))
        XCTAssertTrue(sut.source.contains("selectionchange"))
    }

    func testEachFrameMintsATokenAndSendsItWithEveryMessage() {
        XCTAssertTrue(sut.source.contains("var frameToken ="))
        XCTAssertTrue(sut.source.contains("frameToken: frameToken"))
    }

    func testReadSelectionReturnsTheFrameTokenWithTheText() {
        XCTAssertTrue(sut.source.contains("readSelection"))
        XCTAssertTrue(sut.source.contains("selectedText:"))
    }

    func testAFrameReleasesItsClaimOnPageHide() {
        XCTAssertTrue(sut.source.contains("pagehide"))
    }

    func testAFrameRestoresItsClaimFromTheBackForwardCache() {
        XCTAssertTrue(sut.source.contains("pageshow"))
        XCTAssertTrue(sut.source.contains("event.persisted"))
    }

    /// A selection appearing must not wait on the debounce.
    func testASelectionAppearingIsReportedImmediately() {
        XCTAssertTrue(sut.source.contains("post(true)"))
    }

    /// A frame that never held a selection has no claim to release.
    func testOnlyAFrameThatHeldASelectionReportsOnPageHide() {
        XCTAssertTrue(sut.source.contains("lastHasSelection === true"))
    }

    /// Covers the mechanism only: storing at selection time rules out mutation that fires no
    /// selectionchange, not a page that replaces the selection and so updates what is stored.
    func testTheTextIsSnapshotWhenSelectedRatherThanWhenRead() {
        XCTAssertTrue(sut.source.contains("var spent = snapshot"))
        XCTAssertTrue(sut.source.contains("snapshot = text"))
    }

    /// A submitted selection must not be re-attachable: losing focus hides it without firing
    /// selectionchange, so a later sheet open would otherwise pick up text the user cannot see.
    func testReadingASelectionSpendsItAndReArmsReporting() {
        XCTAssertTrue(sut.source.contains("var spent = snapshot"))
        XCTAssertTrue(sut.source.contains("snapshot = ''"))
        XCTAssertTrue(sut.source.contains("lastHasSelection = null"))
        XCTAssertTrue(sut.source.contains("selectedText: spent"))
    }

    /// An out-of-view third-party iframe could otherwise select its own text and have that read instead.
    func testASubframeOnlyClaimsTheSelectionWhileFocusIsInsideIt() {
        XCTAssertTrue(sut.source.contains("ancestorOrigins"))
        XCTAssertTrue(sut.source.contains("document.hasFocus()"))
    }

    /// The text is read later, only once the user picks a menu item.
    func testNeverSendsTheSelectedText() {
        XCTAssertFalse(sut.source.contains("postMessage({ text"))
        XCTAssertTrue(sut.source.contains("hasSelection: hasSelection"))
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
