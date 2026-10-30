//
//  SponsorBlockSegmentsProviderTests.swift
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
@testable import BrowserServicesKit

final class SponsorBlockSegmentsProviderTests: XCTestCase {

    private typealias Provider = SponsorBlockSegmentsProvider

    private let videoID = "dQw4w9WgXcQ"
    private lazy var validQuery = try! Provider.Query(videoID: videoID)

    // MARK: - Validation

    func testVideoIDValidation() {
        XCTAssertTrue(Provider.Query.isValidVideoID("dQw4w9WgXcQ"))
        XCTAssertTrue(Provider.Query.isValidVideoID("a-b_c-d_e-f"))
        XCTAssertFalse(Provider.Query.isValidVideoID("dQw4w9WgXc"))
        XCTAssertFalse(Provider.Query.isValidVideoID("dQw4w9WgXcQQ"))
        XCTAssertFalse(Provider.Query.isValidVideoID("dQw4w9WgXc!"))
        XCTAssertFalse(Provider.Query.isValidVideoID("dQw4w9WgXcQ\n"))
        XCTAssertFalse(Provider.Query.isValidVideoID(""))
    }

    func testListValidation() {
        XCTAssertTrue(Provider.Query.isValidList(["sponsor", "self_promo"]))
        XCTAssertFalse(Provider.Query.isValidList([]))
        XCTAssertFalse(Provider.Query.isValidList(["Sponsor"]))
        XCTAssertFalse(Provider.Query.isValidList(["spon\"sor"]))
        XCTAssertFalse(Provider.Query.isValidList([String(repeating: "a", count: 33)]))
        XCTAssertFalse(Provider.Query.isValidList(Array(repeating: "sponsor", count: 21)))
    }

    func testQueryFromPageParamsReadsOnlyVideoID() throws {
        XCTAssertThrowsError(try Provider.Query(params: "not a dictionary"))
        XCTAssertThrowsError(try Provider.Query(params: ["categories": ["sponsor"]]))
        XCTAssertThrowsError(try Provider.Query(params: ["videoID": "too-short"]))

        let query = try Provider.Query(params: ["videoID": videoID, "categories": ["selfpromo"], "actionTypes": ["mute"]])
        XCTAssertEqual(query, validQuery)
        XCTAssertEqual(query.categories, ["sponsor"])
        XCTAssertEqual(query.actionTypes, ["skip"])
    }

    func testQueryRejectsInvalidLists() {
        XCTAssertThrowsError(try Provider.Query(videoID: videoID, categories: []))
        XCTAssertThrowsError(try Provider.Query(videoID: videoID, actionTypes: ["Skip"]))
    }

    // MARK: - Request

    func testHashPrefixUsesFirstFourHexCharactersOfSHA256() {
        // SHA-256("abc") = ba7816bf...
        XCTAssertEqual(Provider.hashPrefix(for: "abc"), "ba78")
        // SHA-256("dQw4w9WgXcQ") = 5f6b0b4e...
        XCTAssertEqual(Provider.hashPrefix(for: videoID), "5f6b")
    }

    func testURLEncodesListsAsPercentEncodedJSON() throws {
        let query = try Provider.Query(videoID: videoID, categories: ["sponsor", "selfpromo"], actionTypes: ["skip"])
        XCTAssertEqual(try Provider.url(for: query).absoluteString,
                       "https://web-dew-1.duckduckgo.com/sponsorblock/v1/segments/5f6b?categories=%5B%22sponsor%22%2C%22selfpromo%22%5D&actionTypes=%5B%22skip%22%5D")
    }

    // MARK: - Response

    func testParseKeepsOnlyRequestedVideoSortedAndDropsMalformedSegments() throws {
        let body = """
        [
          {"videoID": "otherVideo1", "hash": "5f6b...", "segments": [
            {"segment": [1, 2], "UUID": "other", "category": "sponsor", "actionType": "skip", "videoDuration": 100}
          ]},
          {"videoID": "\(videoID)", "hash": "5f6b0b4e...", "segments": [
            {"segment": [300.5, 310], "UUID": "second", "category": "sponsor", "actionType": "skip", "videoDuration": 600.1, "votes": 3},
            {"segment": [12.3, 45.6], "UUID": "first", "category": "sponsor", "actionType": "skip", "videoDuration": 600.1},
            {"segment": [50, 40], "UUID": "endBeforeStart", "category": "sponsor", "actionType": "skip"},
            {"segment": [50], "UUID": "missingEnd", "category": "sponsor", "actionType": "skip"},
            {"UUID": "missingTimes", "category": "sponsor", "actionType": "skip"}
          ]}
        ]
        """
        let segments = try Provider.parseSegments(from: Data(body.utf8), videoID: videoID)
        XCTAssertEqual(segments, [
            .init(start: 12.3, end: 45.6, category: "sponsor", actionType: "skip", uuid: "first", videoDuration: 600.1),
            .init(start: 300.5, end: 310, category: "sponsor", actionType: "skip", uuid: "second", videoDuration: 600.1)
        ])
    }

    func testParseReturnsEmptyWhenVideoIsNotInResponse() throws {
        let body = #"[{"videoID": "otherVideo1", "segments": [{"segment": [1, 2], "UUID": "x", "category": "sponsor", "actionType": "skip"}]}]"#
        XCTAssertEqual(try Provider.parseSegments(from: Data(body.utf8), videoID: videoID), [])
    }

    func testParseThrowsForNonArrayBody() {
        XCTAssertThrowsError(try Provider.parseSegments(from: Data(#"{"error": "x"}"#.utf8), videoID: videoID))
    }

    func testNotFoundReturnsEmptySegments() async throws {
        let provider = Provider(load: { request in (Data("Not Found".utf8), Self.response(404, for: request)) })
        let segments = try await provider.segments(for: validQuery)
        XCTAssertEqual(segments, [])
    }

    func testUnexpectedStatusThrows() async throws {
        let provider = Provider(load: { request in (Data(), Self.response(500, for: request)) })
        do {
            _ = try await provider.segments(for: validQuery)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "SponsorBlock request failed with HTTP status 500")
        }
    }

    // MARK: - Cache

    func testCachesResultsAndSharesInFlightRequests() async throws {
        let counter = LoadCounter()
        let provider = Provider(load: { request in
            await counter.increment()
            try await Task.sleep(nanoseconds: 50_000_000)
            return (Data("[]".utf8), Self.response(404, for: request))
        })
        let query = validQuery

        async let first = provider.segments(for: query)
        async let second = provider.segments(for: query)
        _ = try await (first, second)
        _ = try await provider.segments(for: query)

        let count = await counter.count
        XCTAssertEqual(count, 1)
    }

    func testExpiredEntriesAreFetchedAgain() async throws {
        let counter = LoadCounter()
        var now = Date()
        let provider = Provider(load: { request in
            await counter.increment()
            return (Data(), Self.response(404, for: request))
        }, now: { now }, timeToLive: 60)
        let query = validQuery

        _ = try await provider.segments(for: query)
        now += 61
        _ = try await provider.segments(for: query)

        let count = await counter.count
        XCTAssertEqual(count, 2)
    }

    func testLeastRecentlyUsedEntryIsEvicted() async throws {
        let counter = LoadCounter()
        let provider = Provider(load: { request in
            await counter.increment()
            return (Data(), Self.response(404, for: request))
        }, capacity: 1)
        let first = validQuery
        let second = try Provider.Query(videoID: "aaaaaaaaaaa")

        _ = try await provider.segments(for: first)
        _ = try await provider.segments(for: second)
        _ = try await provider.segments(for: first)

        let count = await counter.count
        XCTAssertEqual(count, 3)
    }

    // MARK: - Helpers

    private static func response(_ statusCode: Int, for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }
}

private actor LoadCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}
