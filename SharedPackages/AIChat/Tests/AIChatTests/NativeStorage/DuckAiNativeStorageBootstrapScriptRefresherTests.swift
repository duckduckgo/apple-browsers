//
//  DuckAiNativeStorageBootstrapScriptRefresherTests.swift
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

import UserScript
import WebKit
import XCTest
@testable import AIChat

@MainActor
final class DuckAiNativeStorageBootstrapScriptRefresherTests: XCTestCase {

    private var mockHandler: MockDuckAiNativeStorageHandler!
    private var userContentController: WKUserContentController!

    override func setUp() async throws {
        try await super.setUp()
        mockHandler = MockDuckAiNativeStorageHandler()
        userContentController = WKUserContentController()
    }

    func testWhenRefreshedThenContentControllerHasAllStaticScriptsPlusBootstrap() {
        let staticScript = WKUserScript(source: "window.__static = 1;", injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        let sut = DuckAiNativeStorageBootstrapScriptRefresher(
            handler: mockHandler,
            originRules: [.exactOrSubdomain(hostname: "duck.ai")]
        )

        sut.refresh(on: userContentController, staticScripts: [staticScript])

        XCTAssertEqual(userContentController.userScripts.count, 2)
        XCTAssertTrue(userContentController.userScripts.contains { $0.source.contains("__static = 1") })
        XCTAssertTrue(userContentController.userScripts.contains { $0.source.contains("__nativeStorageEntries") })
    }

    func testWhenRefreshedThenBootstrapSourceReflectsCurrentHandlerState() throws {
        mockHandler.stubbedGetAllEntries = ["setting_kae": "d"]
        let sut = DuckAiNativeStorageBootstrapScriptRefresher(
            handler: mockHandler,
            originRules: [.exactOrSubdomain(hostname: "duck.ai")]
        )

        sut.refresh(on: userContentController, staticScripts: [])

        let bootstrap = try XCTUnwrap(userContentController.userScripts.first { $0.source.contains("__nativeStorageEntries") })
        XCTAssertTrue(bootstrap.source.contains("\"setting_kae\":\"d\""))
    }

    func testWhenRefreshedTwiceThenOnlyOneBootstrapRemains() {
        let sut = DuckAiNativeStorageBootstrapScriptRefresher(
            handler: mockHandler,
            originRules: [.exactOrSubdomain(hostname: "duck.ai")]
        )

        mockHandler.stubbedGetAllEntries = ["setting_kae": "d"]
        sut.refresh(on: userContentController, staticScripts: [])

        mockHandler.stubbedGetAllEntries = ["setting_kae": "l"]
        sut.refresh(on: userContentController, staticScripts: [])

        let bootstraps = userContentController.userScripts.filter { $0.source.contains("__nativeStorageEntries") }
        XCTAssertEqual(bootstraps.count, 1)
        XCTAssertTrue(bootstraps[0].source.contains("\"setting_kae\":\"l\""))
        XCTAssertFalse(bootstraps[0].source.contains("\"setting_kae\":\"d\""))
    }

    func testWhenRefreshedThenStaticScriptsArePreservedAcrossCalls() {
        let staticScript = WKUserScript(source: "window.__static = 1;", injectionTime: .atDocumentStart, forMainFrameOnly: false)
        let sut = DuckAiNativeStorageBootstrapScriptRefresher(
            handler: mockHandler,
            originRules: []
        )

        sut.refresh(on: userContentController, staticScripts: [staticScript])
        sut.refresh(on: userContentController, staticScripts: [staticScript])

        XCTAssertEqual(userContentController.userScripts.filter { $0.source.contains("__static = 1") }.count, 1)
    }

    // MARK: - isInScope

    func testWhenExactRuleMatchesHostThenIsInScopeIsTrue() {
        let sut = DuckAiNativeStorageBootstrapScriptRefresher(
            handler: mockHandler,
            originRules: [.exact(hostname: "debug.example.com")]
        )
        XCTAssertTrue(sut.isInScope(url: URL(string: "https://debug.example.com/chat")!))
    }

    func testWhenExactRuleDoesNotMatchHostThenIsInScopeIsFalse() {
        let sut = DuckAiNativeStorageBootstrapScriptRefresher(
            handler: mockHandler,
            originRules: [.exact(hostname: "debug.example.com")]
        )
        XCTAssertFalse(sut.isInScope(url: URL(string: "https://other.example.com/")!))
    }

    func testWhenExactOrSubdomainRuleMatchesExactHostThenIsInScopeIsTrue() {
        let sut = DuckAiNativeStorageBootstrapScriptRefresher(
            handler: mockHandler,
            originRules: [.exactOrSubdomain(hostname: "duck.ai")]
        )
        XCTAssertTrue(sut.isInScope(url: URL(string: "https://duck.ai/")!))
    }

    func testWhenExactOrSubdomainRuleMatchesSubdomainThenIsInScopeIsTrue() {
        let sut = DuckAiNativeStorageBootstrapScriptRefresher(
            handler: mockHandler,
            originRules: [.exactOrSubdomain(hostname: "duck.ai")]
        )
        XCTAssertTrue(sut.isInScope(url: URL(string: "https://euw-serp-dev-testing19.duck.ai/")!))
    }

    func testWhenHostSharesOnlySuffixWithoutLeadingDotThenIsInScopeIsFalse() {
        let sut = DuckAiNativeStorageBootstrapScriptRefresher(
            handler: mockHandler,
            originRules: [.exactOrSubdomain(hostname: "duck.ai")]
        )
        XCTAssertFalse(sut.isInScope(url: URL(string: "https://evilduck.ai/")!))
    }

    func testWhenUrlHasNoHostThenIsInScopeIsFalse() {
        let sut = DuckAiNativeStorageBootstrapScriptRefresher(
            handler: mockHandler,
            originRules: [.exactOrSubdomain(hostname: "duck.ai")]
        )
        XCTAssertFalse(sut.isInScope(url: URL(string: "about:blank")!))
    }

    func testWhenNoOriginRulesThenIsInScopeIsFalse() {
        let sut = DuckAiNativeStorageBootstrapScriptRefresher(
            handler: mockHandler,
            originRules: []
        )
        XCTAssertFalse(sut.isInScope(url: URL(string: "https://duck.ai/")!))
    }
}
