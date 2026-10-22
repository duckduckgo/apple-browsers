//
//  WebExtensionActionPopupMessageHandlerTests.swift
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

#if os(macOS)
import WebKit
import XCTest
@testable import WebExtensions

@available(macOS 15.4, *)
@MainActor
final class WebExtensionActionPopupMessageHandlerTests: XCTestCase {

    private static let extensionHost = "6c8e4a2b-1f3d-4e5a-9b7c-0d2e4f6a8b1c"

    private var handler: WebExtensionActionPopupMessageHandler!
    private var context: WKWebExtensionContext!
    private var performedActions: [(context: WKWebExtensionContext, tab: any WKWebExtensionTab)] = []

    override func setUp() async throws {
        try await super.setUp()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Action Popup Test", "version": "1.0",
                                       "action": ["default_popup": "popup.html"]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("manifest.json"))
        context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: directory))

        performedActions = []
        handler = WebExtensionActionPopupMessageHandler()
        handler.extensionContext = { [unowned self] url in
            url.host == Self.extensionHost ? context : nil
        }
        handler.performAction = { [unowned self] context, tab in
            performedActions.append((context, tab))
        }
    }

    override func tearDown() {
        handler = nil
        context = nil
        performedActions = []
        super.tearDown()
    }

    func testWhenALoadedExtensionPageInATabAsks_ThenTheActionIsPerformedForThatTab() throws {
        let tab = FakeTab()

        try handler.openPopup(originProtocol: "webkit-extension", originHost: Self.extensionHost, tab: tab)

        XCTAssertEqual(performedActions.count, 1)
        XCTAssertTrue(performedActions.first?.context === context)
        XCTAssertTrue(performedActions.first?.tab === tab)
    }

    func testWhenAWebsiteAsks_ThenItIsRefusedAndNothingOpens() {
        XCTAssertThrowsError(try handler.openPopup(originProtocol: "https", originHost: "example.com", tab: FakeTab())) {
            XCTAssertEqual($0 as? WebExtensionActionPopupMessageHandler.Failure, .notAnExtensionPage)
        }
        XCTAssertTrue(performedActions.isEmpty)
    }

    func testWhenAnUnloadedExtensionAsks_ThenItIsRefusedAndNothingOpens() {
        XCTAssertThrowsError(try handler.openPopup(originProtocol: "webkit-extension", originHost: "other", tab: FakeTab())) {
            XCTAssertEqual($0 as? WebExtensionActionPopupMessageHandler.Failure, .notAnExtensionPage)
        }
        XCTAssertThrowsError(try handler.openPopup(originProtocol: "webkit-extension", originHost: "", tab: FakeTab())) {
            XCTAssertEqual($0 as? WebExtensionActionPopupMessageHandler.Failure, .notAnExtensionPage)
        }
        XCTAssertTrue(performedActions.isEmpty)
    }

    func testWhenThereIsNoTab_ThenItIsRefusedAndNothingOpens() {
        XCTAssertThrowsError(try handler.openPopup(originProtocol: "webkit-extension", originHost: Self.extensionHost, tab: nil)) {
            XCTAssertEqual($0 as? WebExtensionActionPopupMessageHandler.Failure, .noTab)
        }
        XCTAssertTrue(performedActions.isEmpty)
    }
}

@available(macOS 15.4, *)
private final class FakeTab: NSObject, WKWebExtensionTab {}
#endif
