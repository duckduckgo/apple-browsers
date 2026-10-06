//
//  WebExtensionScopedUserScriptTests.swift
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

import WebKit
import XCTest

@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class WebExtensionScopedUserScriptTests: XCTestCase {

    func testWhenScriptIsMade_ThenItKeepsSourceInjectionTimeAndFrames() throws {
        let script = try XCTUnwrap(WebExtensionScopedUserScript.make(source: "var x = 1;",
                                                                      injectionTime: .atDocumentStart,
                                                                      forMainFrameOnly: false,
                                                                      includeMatchPatterns: ["webkit-extension://abc/*"]))

        XCTAssertEqual(script.source, "var x = 1;")
        XCTAssertEqual(script.injectionTime, .atDocumentStart)
        XCTAssertFalse(script.isForMainFrameOnly)
    }

    func testWhenScriptIsRemoved_ThenOtherScriptsStay() throws {
        let userContentController = WKUserContentController()
        let other = WKUserScript(source: "var other = 1;", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let scoped = try XCTUnwrap(WebExtensionScopedUserScript.make(source: "var scoped = 1;",
                                                                      injectionTime: .atDocumentStart,
                                                                      forMainFrameOnly: false,
                                                                      includeMatchPatterns: ["webkit-extension://abc/*"]))
        userContentController.addUserScript(other)
        userContentController.addUserScript(scoped)

        WebExtensionScopedUserScript.remove(scoped, from: userContentController)

        XCTAssertEqual(userContentController.userScripts.map(\.source), ["var other = 1;"])
    }
}
