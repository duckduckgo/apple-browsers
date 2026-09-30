//
//  WebExtensionAPICompatibilityClassifierTests.swift
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
@testable import WebExtensions

final class WebExtensionAPICompatibilityClassifierTests: XCTestCase {

    private typealias Issue = WebExtensionAPICompatibilityClassifier.Issue

    // MARK: - Error Messages

    func testWhenAnObjectIsUndefined_ThenTheParentOfTheReadPropertyIsMissing() {
        XCTAssertEqual(
            classify("undefined is not an object (evaluating 'chrome.notifications.onClicked')"),
            Issue(kind: .missing, api: "chrome.notifications"))
        XCTAssertEqual(
            classify("TypeError: undefined is not an object (evaluating 'chrome.tts.speak.call')"),
            Issue(kind: .missing, api: "chrome.tts.speak"))
    }

    func testWhenTheRootIsAnAlias_ThenItIsNormalizedToChrome() {
        XCTAssertEqual(
            classify("undefined is not an object (evaluating 'browser.tts.speak')"),
            Issue(kind: .missing, api: "chrome.tts"))
        XCTAssertEqual(
            classify("undefined is not an object (evaluating 'globalThis.chrome.tts.speak')"),
            Issue(kind: .missing, api: "chrome.tts"))
    }

    func testWhenAFunctionIsMissing_ThenItsPathIsMissing() {
        XCTAssertEqual(
            classify("chrome.tabs.captureVisibleTab is not a function. (In 'chrome.tabs.captureVisibleTab()', 'chrome.tabs.captureVisibleTab' is undefined)"),
            Issue(kind: .missing, api: "chrome.tabs.captureVisibleTab"))
    }

    func testWhenWebKitRejectsACall_ThenItIsInvalidArgs() {
        XCTAssertEqual(
            classify("Invalid call to tabs.query(). The 'queryInfo' value is invalid, because an object is expected."),
            Issue(kind: .invalidArgs, api: "chrome.tabs.query"))
        XCTAssertEqual(
            classify("Invalid call to browser.windows.create(). The 'createData' value is invalid, because it is not an object."),
            Issue(kind: .invalidArgs, api: "chrome.windows.create"))
    }

    func testWhenAnInvalidCallIsNotAboutAValue_ThenItIsDropped() {
        XCTAssertNil(classify("Invalid call to windows.create(). Something else"))
        XCTAssertNil(classify("Invalid call to tabs.query()."))
    }

    func testWhenLastErrorIsRead_ThenItIsNotMissing() {
        XCTAssertNil(classify("undefined is not an object (evaluating 'chrome.runtime.lastError.message')"))
        XCTAssertNil(classify("undefined is not an object (evaluating 'browser.runtime.lastError.message.length')"))
        XCTAssertNil(classify("chrome.runtime.lastError.reset is not a function. (In 'chrome.runtime.lastError.reset()')"))
        XCTAssertEqual(
            classify("undefined is not an object (evaluating 'chrome.runtime.lastErrors.message')"),
            Issue(kind: .missing, api: "chrome.runtime.lastErrors"))
    }

    func testWhenTheMessageIsNotAboutAnAPI_ThenItIsDropped() {
        XCTAssertNil(classify("Script error."))
        XCTAssertNil(classify("undefined is not an object (evaluating 'e.data.value')"))
        XCTAssertNil(classify("undefined is not an object (evaluating 'chrome.runtime')"))
        XCTAssertNil(classify("undefined is not an object (evaluating 'this.service.load(https://example.com/secret)')"))
        XCTAssertNil(classify("myHelper.run is not a function. (In 'myHelper.run()', 'myHelper.run' is undefined)"))
        XCTAssertNil(classify("Invalid call to tabs.query(https://example.com)"))
        XCTAssertNil(classify(""))
    }

    func testWhenThePathIsTooLong_ThenItIsDropped() {
        let path = (0..<40).map { "segment\($0)" }.joined(separator: ".")
        XCTAssertNil(classify("Invalid call to \(path)()"))
    }

    // MARK: - Reported APIs

    func testWhenThePageNamesAnAPIPath_ThenItIsPrefixedWithChrome() {
        XCTAssertEqual(
            WebExtensionAPICompatibilityClassifier.issue(kind: .stubbed, reportedAPI: "notifications.onClicked.addListener"),
            Issue(kind: .stubbed, api: "chrome.notifications.onClicked.addListener"))
    }

    func testWhenThePageNamesAPermission_ThenItIsKept() {
        XCTAssertEqual(
            WebExtensionAPICompatibilityClassifier.issue(kind: .missing, reportedAPI: "permission:idle"),
            Issue(kind: .missing, api: "permission:idle"))
    }

    func testWhenTheReportedAPIIsNotAPath_ThenItIsDropped() {
        let reported = ["", "https://example.com/a", "a b", "a..b", "permission:", "permission:a b", "permission:https://x.y", "a.b()"]
        for api in reported {
            XCTAssertNil(WebExtensionAPICompatibilityClassifier.issue(kind: .stubbed, reportedAPI: api), api)
        }
    }

    // MARK: - Dropped Permissions

    func testWhenWebKitDropsAPermission_ThenItIsListed() {
        let manifest: [String: Any] = [
            "permissions": ["storage", "privacy", "idle", "https://*/*", "<all_urls>"],
            "optional_permissions": ["notifications", "*://example.com/*"],
            "host_permissions": ["https://example.com/*"]
        ]

        let dropped = WebExtensionAPICompatibilityClassifier.droppedPermissions(inManifest: manifest,
                                                                                webKitPermissions: ["storage", "idle"])

        XCTAssertEqual(dropped, ["notifications"])
    }

    func testWhenTheStubScriptProvidesAPermission_ThenItIsNotListed() {
        let manifest: [String: Any] = ["permissions": ["privacy", "offscreen", "downloads"]]

        XCTAssertEqual(WebExtensionAPICompatibilityClassifier.droppedPermissions(inManifest: manifest, webKitPermissions: []),
                       ["downloads"])
    }

    func testWhenWebKitKeepsEveryPermission_ThenNothingIsListed() {
        let manifest: [String: Any] = ["permissions": ["storage"], "optional_permissions": ["tabs"]]

        XCTAssertEqual(
            WebExtensionAPICompatibilityClassifier.droppedPermissions(inManifest: manifest, webKitPermissions: ["storage", "tabs"]),
            [])
    }

    func testWhenManifestHasNoPermissions_ThenNothingIsListed() {
        XCTAssertEqual(WebExtensionAPICompatibilityClassifier.droppedPermissions(inManifest: [:], webKitPermissions: []), [])
    }

    func testWhenAPermissionNameIsNotAName_ThenItIsNotListed() {
        let manifest: [String: Any] = ["permissions": ["a b", "x\ny", "ok"]]

        XCTAssertEqual(WebExtensionAPICompatibilityClassifier.droppedPermissions(inManifest: manifest, webKitPermissions: []), ["ok"])
    }

    // MARK: - Helpers

    private func classify(_ message: String) -> Issue? {
        WebExtensionAPICompatibilityClassifier.classify(errorMessage: message)
    }
}
