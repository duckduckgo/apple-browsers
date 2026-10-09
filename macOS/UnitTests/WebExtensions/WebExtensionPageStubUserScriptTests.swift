//
//  WebExtensionPageStubUserScriptTests.swift
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

import WebExtensions
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@available(macOS 15.4, *)
final class WebExtensionPageStubUserScriptTests: XCTestCase {

    private var script: WebExtensionPageStubUserScript!

    override func setUp() {
        super.setUp()
        script = WebExtensionPageStubUserScript()
    }

    override func tearDown() {
        script = nil
        super.tearDown()
    }

    func testThatSourceIsTheThirdPartyScriptsInLoaderOrder() {
        XCTAssertEqual(script.source, WebExtensionLoader.thirdPartyScriptSources.joined(separator: "\n"))
        XCTAssertTrue(script.source.contains(WebExtensionAPICompatibilityScript.source))
        XCTAssertTrue(script.source.contains(WebExtensionAPIStubScript.source))
    }

    func testThatScriptIsInjectedAtDocumentStart() {
        XCTAssertEqual(script.injectionTime, .atDocumentStart)
    }

    func testThatScriptRunsInAllFrames() {
        XCTAssertFalse(script.forMainFrameOnly)
    }

    func testThatScriptRunsInPageContentWorld() {
        XCTAssertTrue(script.requiresRunInPageContentWorld)
    }

    func testThatScriptListensForCompatibilityReportsAndIdleRequests() {
        XCTAssertEqual(script.messageNames, [WebExtensionAPICompatibilityScript.messageHandlerName,
                                             WebExtensionAPIStubScript.idleMessageHandlerName])
    }

    func testThatScriptIsCreatedForInternalUsers() {
        XCTAssertNotNil(WebExtensionPageStubUserScript.make(isInternalUser: true))
    }

    func testThatScriptIsNotCreatedForOtherUsers() {
        XCTAssertNil(WebExtensionPageStubUserScript.make(isInternalUser: false))
    }
}
