//
//  WebExtensionPermissionsMessageHandlerTests.swift
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
@_spi(Testing) import Persistence
import WebKit
import XCTest
@testable import WebExtensions

@available(macOS 15.4, *)
@MainActor
final class WebExtensionPermissionsMessageHandlerTests: XCTestCase {

    private static let extensionHost = "6c8e4a2b-1f3d-4e5a-9b7c-0d2e4f6a8b1c"

    private var handler: WebExtensionPermissionsMessageHandler!
    private var context: WKWebExtensionContext!
    private var controller: WebExtensionPermissionController!

    override func setUp() async throws {
        try await super.setUp()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Permissions Test", "version": "1.0",
                                       "optional_permissions": ["privacy"]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("manifest.json"))
        context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: directory))
        context.uniqueIdentifier = "bitwarden"

        controller = WebExtensionPermissionController(store: WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore()),
                                                          installationStore: InstalledWebExtensionStoringMock(),
                                                          prompter: ApprovingPrompter())
        try await controller.prepare(context)
        handler = WebExtensionPermissionsMessageHandler()
        handler.controller = { [unowned self] in controller }
        handler.extensionContext = { [unowned self] url in
            url.host == Self.extensionHost ? context : nil
        }
    }

    override func tearDown() {
        handler = nil
        context = nil
        controller = nil
        super.tearDown()
    }

    func testWhenTheExtensionAsks_ThenRequestGrantsAndContainsAndGetAllSeeIt() async {
        controller.recordUserGesture(for: context)
        let request = await answer(["action": "request", "permissions": ["privacy"]])
        let contains = await answer(["action": "contains", "permissions": ["privacy"]])
        let all = await answer(["action": "getAll"])

        XCTAssertEqual(request as? Bool, true)
        XCTAssertEqual(contains as? Bool, true)
        XCTAssertEqual(all as? [String], ["privacy"])
    }

    func testWhenTheExtensionRemovesPrivacy_ThenItIsNoLongerHeld() async {
        controller.recordUserGesture(for: context)
        _ = await answer(["action": "request", "permissions": ["privacy"]])

        let removed = await answer(["action": "remove", "permissions": ["privacy"]])
        let contains = await answer(["action": "contains", "permissions": ["privacy"]])

        XCTAssertEqual(removed as? Bool, true)
        XCTAssertEqual(contains as? Bool, false)
    }

    func testWhenAWebsiteOrAnUnloadedExtensionAsks_ThenNothingIsGranted() async {
        let website = await handler.answer(body: ["action": "request", "permissions": ["privacy"]],
                                           originProtocol: "https", originHost: "example.com")
        let unloaded = await handler.answer(body: ["action": "request", "permissions": ["privacy"]],
                                            originProtocol: "webkit-extension", originHost: "other")

        let contains = await answer(["action": "contains", "permissions": ["privacy"]])

        XCTAssertEqual(website as? Bool, false)
        XCTAssertEqual(unloaded as? Bool, false)
        XCTAssertEqual(contains as? Bool, false)
    }

    func testWhenTheRequestNamesAPermissionTheAppDoesNotKeep_ThenItAnswersFalse() async {
        let answered = await answer(["action": "request", "permissions": ["privacy", "tabs"]])

        XCTAssertEqual(answered as? Bool, false)
    }

    func testWhenThereIsNoPermissionController_ThenNothingIsHeld() async {
        handler.controller = { nil }

        let request = await answer(["action": "request", "permissions": ["privacy"]])
        let all = await answer(["action": "getAll"])

        XCTAssertEqual(request as? Bool, false)
        XCTAssertEqual(all as? [String], [])
    }

    func testRequestWithoutGestureIsRefusedEvenWithAClaimedGestureInTheBody() async {
        let result = await answer(["action": "request", "permissions": ["privacy"], "userGesture": true])

        XCTAssertEqual(result as? Bool, false)
        XCTAssertFalse(controller.isGranted(.privacy, to: context.uniqueIdentifier))
    }

    func testPageWorldCannotRecordAGesture() async {
        handler.recordUserGesture(originProtocol: "webkit-extension", originHost: Self.extensionHost, contentWorld: .page)

        let result = await answer(["action": "request", "permissions": ["privacy"]])

        XCTAssertEqual(result as? Bool, false)
    }

    func testWebsiteCannotRecordAGestureEvenInTheIsolatedWorld() async {
        handler.recordUserGesture(originProtocol: "https", originHost: Self.extensionHost, contentWorld: .defaultClient)

        let result = await answer(["action": "request", "permissions": ["privacy"]])

        XCTAssertEqual(result as? Bool, false)
    }

    func testIsolatedGestureAuthorizesOneRequestForTheSameExtensionAcrossPages() async {
        handler.recordUserGesture(originProtocol: "webkit-extension", originHost: Self.extensionHost, contentWorld: .defaultClient)

        let result = await answer(["action": "request", "permissions": ["privacy"]])
        let secondPage = await answer(["action": "request", "permissions": ["privacy"]])

        XCTAssertEqual(result as? Bool, true)
        XCTAssertEqual(secondPage as? Bool, false)
    }

    func testPreparedRequestIsCompletedWithItsIdentifierOnlyOnce() async throws {
        handler.recordUserGesture(originProtocol: "webkit-extension", originHost: Self.extensionHost, contentWorld: .defaultClient)
        let prepared = await answer(["action": "prepareRequest", "permissions": ["privacy"]])
        let identifier = try XCTUnwrap(prepared as? String)

        let request: [String: Any] = ["action": "request", "permissions": ["privacy"], "requestIdentifier": identifier]
        let granted = await answer(request)
        let replay = await answer(request)

        XCTAssertEqual(granted as? Bool, true)
        XCTAssertEqual(replay as? Bool, false)
    }

    private func answer(_ body: [String: Any]) async -> Any {
        await handler.answer(body: body, originProtocol: "webkit-extension", originHost: Self.extensionHost)
    }
}

@available(macOS 15.4, *)
@MainActor
private final class ApprovingPrompter: WebExtensionPermissionPrompting {
    func confirmInstallation(of webExtension: WKWebExtension, permissions: WebExtensionPermissionRequest) async -> WebExtensionPermissionInstallationPromptResult {
        .granted(privateDataAccess: false)
    }

    func confirmPermissions(_ permissions: WebExtensionPermissionRequest, for context: WKWebExtensionContext) async -> WebExtensionPermissionPromptResult {
        .granted
    }
}
#endif
