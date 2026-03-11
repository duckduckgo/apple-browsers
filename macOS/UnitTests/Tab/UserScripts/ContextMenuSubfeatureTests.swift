//
//  ContextMenuSubfeatureTests.swift
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
import WebKit

@testable import DuckDuckGo_Privacy_Browser

final class ContextMenuSubfeatureTests: XCTestCase {

    private var subfeature: ContextMenuSubfeature!
    private var mockDelegate: MockContextMenuDelegate!

    @MainActor
    override func setUp() {
        super.setUp()
        subfeature = ContextMenuSubfeature()
        mockDelegate = MockContextMenuDelegate()
        subfeature.delegate = mockDelegate
    }

    override func tearDown() {
        subfeature = nil
        mockDelegate = nil
        super.tearDown()
    }

    func testFeatureNameIsContextMenu() {
        XCTAssertEqual(subfeature.featureName, "contextMenu")
    }

    func testWhenMethodIsContextMenuEventThenHandlerIsReturned() {
        XCTAssertNotNil(subfeature.handler(forMethodNamed: "contextMenuEvent"))
    }

    func testWhenMethodIsUnknownThenHandlerIsNil() {
        XCTAssertNil(subfeature.handler(forMethodNamed: "unknownMethod"))
    }

    @MainActor
    func testWhenContextMenuEventReceivedThenDelegateIsCalled() async throws {
        let handler = try XCTUnwrap(subfeature.handler(forMethodNamed: "contextMenuEvent"))

        let params: [String: Any] = [
            "selectedText": "hello world",
            "linkUrl": "https://example.com",
            "imageSrc": "image.png",
            "imageAlt": "alt text",
            "title": "tooltip",
            "elementTag": "img"
        ]

        _ = try await handler(params, WKScriptMessage())

        XCTAssertEqual(mockDelegate.receivedSelectedText, "hello world")
        XCTAssertEqual(mockDelegate.receivedLinkURL, "https://example.com")
    }

    @MainActor
    func testWhenContextMenuEventHasNullFieldsThenDelegateReceivesNils() async throws {
        let handler = try XCTUnwrap(subfeature.handler(forMethodNamed: "contextMenuEvent"))

        let params: [String: Any] = [
            "selectedText": NSNull(),
            "linkUrl": NSNull()
        ]

        _ = try await handler(params, WKScriptMessage())

        XCTAssertTrue(mockDelegate.willShowContextMenuCalled)
        XCTAssertNil(mockDelegate.receivedSelectedText)
        XCTAssertNil(mockDelegate.receivedLinkURL)
    }

    @MainActor
    func testWhenContextMenuEventHasOnlySelectedTextThenLinkURLIsNil() async throws {
        let handler = try XCTUnwrap(subfeature.handler(forMethodNamed: "contextMenuEvent"))

        let params: [String: Any] = [
            "selectedText": "some text",
            "linkUrl": NSNull(),
            "elementTag": "p"
        ]

        _ = try await handler(params, WKScriptMessage())

        XCTAssertEqual(mockDelegate.receivedSelectedText, "some text")
        XCTAssertNil(mockDelegate.receivedLinkURL)
    }
}

// MARK: - Mock

private final class MockContextMenuDelegate: ContextMenuUserScriptDelegate {
    var receivedSelectedText: String?
    var receivedLinkURL: String?
    var willShowContextMenuCalled = false

    func willShowContextMenu(withSelectedText selectedText: String?, linkURL: String?) {
        willShowContextMenuCalled = true
        receivedSelectedText = selectedText
        receivedLinkURL = linkURL
    }
}
