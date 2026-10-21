//
//  DuckAiNativeStorageBootstrapUserScriptTests.swift
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

final class DuckAiNativeStorageBootstrapUserScriptTests: XCTestCase {

    private var mockHandler: MockDuckAiNativeStorageHandler!

    override func setUp() {
        super.setUp()
        mockHandler = MockDuckAiNativeStorageHandler()
    }

    // MARK: - UserScript protocol conformance

    func testWhenInitializedThenInjectionTimeIsAtDocumentStart() {
        let sut = DuckAiNativeStorageBootstrapUserScript(handler: mockHandler, allowedOrigins: [])
        XCTAssertEqual(sut.injectionTime, .atDocumentStart)
    }

    func testWhenInitializedThenForMainFrameOnlyIsTrue() {
        let sut = DuckAiNativeStorageBootstrapUserScript(handler: mockHandler, allowedOrigins: [])
        XCTAssertTrue(sut.forMainFrameOnly)
    }

    func testWhenInitializedThenRequiresPageContentWorldIsTrue() {
        let sut = DuckAiNativeStorageBootstrapUserScript(handler: mockHandler, allowedOrigins: [])
        XCTAssertTrue(sut.requiresRunInPageContentWorld)
    }

    func testWhenInitializedThenMessageNamesIsEmpty() {
        let sut = DuckAiNativeStorageBootstrapUserScript(handler: mockHandler, allowedOrigins: [])
        XCTAssertTrue(sut.messageNames.isEmpty)
    }

    // MARK: - Whitelisting

    func testWhenHandlerReturnsAllowedlistedEntriesThenSourceContainsThem() {
        mockHandler.stubbedGetAllEntries = [
            "setting_kae": "d",
            "duckaiSidebarCollapsed": true
        ]
        let sut = DuckAiNativeStorageBootstrapUserScript(handler: mockHandler, allowedOrigins: [])
        XCTAssertTrue(sut.source.contains("\"setting_kae\":\"d\""))
        XCTAssertTrue(sut.source.contains("\"duckaiSidebarCollapsed\":true"))
    }

    func testWhenHandlerReturnsNonAllowedlistedEntriesThenSourceOmitsThem() {
        mockHandler.stubbedGetAllEntries = [
            "setting_kae": "d",
            "someOtherKey": "private-value"
        ]
        let sut = DuckAiNativeStorageBootstrapUserScript(handler: mockHandler, allowedOrigins: [])
        XCTAssertFalse(sut.source.contains("someOtherKey"))
        XCTAssertFalse(sut.source.contains("private-value"))
    }

    func testWhenHandlerReturnsNoAllowedlistedEntriesThenSourceAssignsEmptyObject() {
        mockHandler.stubbedGetAllEntries = ["randomKey": "randomValue"]
        let sut = DuckAiNativeStorageBootstrapUserScript(handler: mockHandler, allowedOrigins: [])
        XCTAssertTrue(sut.source.contains("window.__nativeStorageEntries = {}"))
    }

    func testWhenHandlerGetAllEntriesThrowsThenSourceAssignsEmptyObject() {
        mockHandler.stubbedGetAllEntriesError = NSError(domain: "test", code: 1)
        let sut = DuckAiNativeStorageBootstrapUserScript(handler: mockHandler, allowedOrigins: [])
        XCTAssertTrue(sut.source.contains("window.__nativeStorageEntries = {}"))
    }

    // MARK: - Hostname guard

    func testWhenAllowedOriginsIsEmptyThenGuardFailsClosed() {
        mockHandler.stubbedGetAllEntries = ["setting_kae": "d"]
        let sut = DuckAiNativeStorageBootstrapUserScript(handler: mockHandler, allowedOrigins: [])
        // With no allowed origins, the assignment must be unreachable.
        XCTAssertTrue(sut.source.contains("if (!(false)) return"))
    }

    func testWhenAllowedOriginsContainsExactRuleThenSourceUsesStrictEquality() {
        let sut = DuckAiNativeStorageBootstrapUserScript(
            handler: mockHandler,
            allowedOrigins: [.exact(hostname: "debug.example.com")]
        )
        XCTAssertTrue(sut.source.contains("location.hostname === \"debug.example.com\""))
        XCTAssertFalse(sut.source.contains("endsWith"))
    }

    func testWhenAllowedOriginsContainsExactOrSubdomainRuleThenSourceChecksSuffix() {
        let sut = DuckAiNativeStorageBootstrapUserScript(
            handler: mockHandler,
            allowedOrigins: [.exactOrSubdomain(hostname: "duck.ai")]
        )
        XCTAssertTrue(sut.source.contains("location.hostname === \"duck.ai\""))
        XCTAssertTrue(sut.source.contains("location.hostname.endsWith(\".duck.ai\")"))
    }

    func testWhenAllowedOriginsHasMultipleRulesThenSourceJoinsWithOr() {
        let sut = DuckAiNativeStorageBootstrapUserScript(
            handler: mockHandler,
            allowedOrigins: [
                .exactOrSubdomain(hostname: "duck.ai"),
                .exact(hostname: "debug.example.com")
            ]
        )
        XCTAssertTrue(sut.source.contains("location.hostname === \"duck.ai\""))
        XCTAssertTrue(sut.source.contains("location.hostname === \"debug.example.com\""))
        XCTAssertTrue(sut.source.contains(" || "))
    }
}
