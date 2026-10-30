//
//  SponsorBlockSubfeatureTests.swift
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
@testable import BrowserServicesKit
@testable import UserScript

final class SponsorBlockSubfeatureTests: XCTestCase {

    func testFeatureNameMatchesContentScopeScriptsFeature() {
        XCTAssertEqual(SponsorBlockSubfeature().featureName, "sponsorBlock")
    }

    func testMessageOriginPolicyAllowsOnlyYouTubeAndDuckPlayerEmbed() {
        let policy = SponsorBlockSubfeature().messageOriginPolicy
        XCTAssertTrue(policy.isAllowed("youtube.com"))
        XCTAssertTrue(policy.isAllowed("www.youtube.com"))
        XCTAssertTrue(policy.isAllowed("m.youtube.com"))
        XCTAssertTrue(policy.isAllowed("youtube-nocookie.com"))
        XCTAssertTrue(policy.isAllowed("www.youtube-nocookie.com"))
        XCTAssertFalse(policy.isAllowed("music.youtube.com"))
        XCTAssertFalse(policy.isAllowed("notyoutube.com"))
        XCTAssertFalse(policy.isAllowed("example.com"))
    }

    func testHandlerRouting() {
        let subfeature = SponsorBlockSubfeature()
        XCTAssertNotNil(subfeature.handler(forMethodNamed: "log"))
        XCTAssertNotNil(subfeature.handler(forMethodNamed: "getSegments"))
        XCTAssertNil(subfeature.handler(forMethodNamed: "unknownMethod"))
    }

    @MainActor
    func testLogHandlerReturnsNoResponse() async throws {
        let handler = try XCTUnwrap(SponsorBlockSubfeature().handler(forMethodNamed: "log"))
        let response = try await handler(["message": "hello"], WKScriptMessage.mock(name: "log", body: [:]))
        XCTAssertNil(response)
    }

    @MainActor
    func testGetSegmentsWithBadParamsThrowsSoBrokerRepliesWithError() async throws {
        let provider = SponsorBlockSegmentsProvider(load: { _ in
            XCTFail("Invalid params must not reach the network")
            throw URLError(.badURL)
        })
        let handler = try XCTUnwrap(SponsorBlockSubfeature(segmentsProvider: provider).handler(forMethodNamed: "getSegments"))
        do {
            _ = try await handler(["videoID": "too-short"], WKScriptMessage.mock(name: "getSegments", body: [:]))
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Invalid getSegments param: videoID")
        }
    }
}
