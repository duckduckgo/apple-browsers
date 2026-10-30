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
        XCTAssertEqual(SponsorBlockSubfeature(isEnabled: { true }).featureName, "sponsorBlock")
    }

    func testMessageOriginPolicyAllowsOnlyYouTubeAndDuckPlayerEmbed() {
        let policy = SponsorBlockSubfeature(isEnabled: { true }).messageOriginPolicy
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
        let subfeature = SponsorBlockSubfeature(isEnabled: { true })
        XCTAssertNotNil(subfeature.handler(forMethodNamed: "getSegments"))
        XCTAssertNil(subfeature.handler(forMethodNamed: "log"))
        XCTAssertNil(subfeature.handler(forMethodNamed: "unknownMethod"))
    }

    @MainActor
    func testGetSegmentsResolvesToEmptyWhenLookupFails() async throws {
        let provider = SponsorBlockSegmentsProvider(load: { _ in throw URLError(.notConnectedToInternet) })
        let subfeature = SponsorBlockSubfeature(segmentsProvider: provider, isEnabled: { true })
        let handler = try XCTUnwrap(subfeature.handler(forMethodNamed: "getSegments"))
        let response = try await handler(["videoID": "dQw4w9WgXcQ"], WKScriptMessage.mock(name: "getSegments", body: [:]))
        let segments = try XCTUnwrap(response as? SponsorBlockSubfeature.GetSegmentsResponse).segments
        XCTAssertEqual(segments, [])
    }

    @MainActor
    func testGetSegmentsAnswersEmptyWithoutLookupWhenDisabled() async throws {
        let provider = SponsorBlockSegmentsProvider(load: { _ in
            XCTFail("No lookup while the feature is disabled")
            throw URLError(.badURL)
        })
        let subfeature = SponsorBlockSubfeature(segmentsProvider: provider, isEnabled: { false })
        let handler = try XCTUnwrap(subfeature.handler(forMethodNamed: "getSegments"))
        let response = try await handler(["videoID": "dQw4w9WgXcQ"], WKScriptMessage.mock(name: "getSegments", body: [:]))
        let segments = try XCTUnwrap(response as? SponsorBlockSubfeature.GetSegmentsResponse).segments
        XCTAssertEqual(segments, [])
    }

    @MainActor
    func testGetSegmentsIgnoresCategoriesSentByThePage() async throws {
        let provider = SponsorBlockSegmentsProvider(load: { request in
            let url = request.url!.absoluteString
            XCTAssertTrue(url.contains("%22sponsor%22"), url)
            XCTAssertFalse(url.contains("selfpromo"), url)
            return (Data("[]".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let subfeature = SponsorBlockSubfeature(segmentsProvider: provider, isEnabled: { true })
        let handler = try XCTUnwrap(subfeature.handler(forMethodNamed: "getSegments"))
        _ = try await handler(["videoID": "dQw4w9WgXcQ", "categories": ["selfpromo"]], WKScriptMessage.mock(name: "getSegments", body: [:]))
    }

    @MainActor
    func testGetSegmentsWithBadParamsThrowsSoBrokerRepliesWithError() async throws {
        let provider = SponsorBlockSegmentsProvider(load: { _ in
            XCTFail("Invalid params must not reach the network")
            throw URLError(.badURL)
        })
        let subfeature = SponsorBlockSubfeature(segmentsProvider: provider, isEnabled: { true })
        let handler = try XCTUnwrap(subfeature.handler(forMethodNamed: "getSegments"))
        do {
            _ = try await handler(["videoID": "too-short"], WKScriptMessage.mock(name: "getSegments", body: [:]))
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Invalid getSegments param: videoID")
        }
    }
}
