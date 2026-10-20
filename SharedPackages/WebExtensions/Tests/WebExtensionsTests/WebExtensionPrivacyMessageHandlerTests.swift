//
//  WebExtensionPrivacyMessageHandlerTests.swift
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
import XCTest
@testable import WebExtensions

@available(macOS 15.4, *)
@MainActor
final class WebExtensionPrivacyMessageHandlerTests: XCTestCase {

    private static let extensionHost = "6c8e4a2b-1f3d-4e5a-9b7c-0d2e4f6a8b1c"

    private var handler: WebExtensionPrivacyMessageHandler!
    private var store: WebExtensionPrivacySettingsStore!

    override func setUp() {
        super.setUp()
        store = WebExtensionPrivacySettingsStore(keyValueStore: InMemoryThrowingKeyValueStore())
        store.canControl = { $0 == "bitwarden" }
        handler = WebExtensionPrivacyMessageHandler()
        handler.store = store
        handler.extensionIdentifier = { url in
            url.host == Self.extensionHost ? "bitwarden" : nil
        }
    }

    override func tearDown() {
        handler = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Who Is Answered

    func testWhenAWebsiteAsks_ThenItIsRejected() {
        let result = handler.answer(body: ["action": "get", "setting": "passwordSavingEnabled"],
                                    originProtocol: "https", originHost: "example.com")

        XCTAssertNil(result.reply)
        XCTAssertNotNil(result.error)
    }

    func testWhenAPageOfAnExtensionThatIsNotLoadedAsks_ThenItIsRejected() {
        let result = handler.answer(body: ["action": "get", "setting": "passwordSavingEnabled"],
                                    originProtocol: "webkit-extension", originHost: "unknown")

        XCTAssertNil(result.reply)
        XCTAssertNotNil(result.error)
    }

    func testWhenTheSettingIsUnknown_ThenTheRequestIsRejected() {
        let result = answer(["action": "get", "setting": "webRTCIPHandlingPolicy"])

        XCTAssertNil(result.reply)
        XCTAssertNotNil(result.error)
    }

    // MARK: - Get, Set and Clear

    func testWhenTheExtensionTurnsPasswordSavingOff_ThenTheStoreRecordsItAndGetReportsControl() {
        let setResult = answer(["action": "set", "setting": "passwordSavingEnabled", "value": false])
        XCTAssertNil(setResult.error)
        XCTAssertEqual(store.identifierTurningOff(.passwordSavingEnabled), "bitwarden")

        let details = answer(["action": "get", "setting": "passwordSavingEnabled"]).reply as? [String: Any]
        XCTAssertEqual(details?["value"] as? Bool, false)
        XCTAssertEqual(details?["levelOfControl"] as? String, "controlled_by_this_extension")
    }

    func testWhenTheExtensionClearsTheSetting_ThenItNoLongerControlsIt() {
        _ = answer(["action": "set", "setting": "passwordSavingEnabled", "value": false])

        let result = answer(["action": "clear", "setting": "passwordSavingEnabled"])

        XCTAssertNil(result.error)
        XCTAssertNil(store.controllingIdentifier(for: .passwordSavingEnabled))
    }

    func testWhenTheExtensionMayNotControlSettings_ThenSetIsRejected() {
        store.canControl = { _ in false }

        let result = answer(["action": "set", "setting": "passwordSavingEnabled", "value": false])

        XCTAssertNotNil(result.error)
        XCTAssertNil(store.controllingIdentifier(for: .passwordSavingEnabled))
        let details = answer(["action": "get", "setting": "passwordSavingEnabled"]).reply as? [String: Any]
        XCTAssertEqual(details?["levelOfControl"] as? String, "not_controllable")
    }

    func testWhenSetHasNoValue_ThenItIsRejected() {
        let result = answer(["action": "set", "setting": "passwordSavingEnabled"])

        XCTAssertNotNil(result.error)
        XCTAssertNil(store.controllingIdentifier(for: .passwordSavingEnabled))
    }

    // MARK: - Helpers

    private func answer(_ body: [String: Any]) -> (reply: Any?, error: String?) {
        handler.answer(body: body, originProtocol: "webkit-extension", originHost: Self.extensionHost)
    }
}
#endif
