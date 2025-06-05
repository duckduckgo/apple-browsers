//
//  MaliciousSiteDetectorTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Foundation
import Networking
import XCTest

@testable import MaliciousSiteProtection

class MaliciousSiteDetectorTests: XCTestCase {

    private var mockAPIClient: MockMaliciousSiteProtectionAPIClient!
    private var mockDataManager: MockMaliciousSiteProtectionDataManager!
    private var mockEventMapping: MockEventMapping!
    private var detector: MaliciousSiteDetector!
    private var isScamProtectionSupported = false
    private var shouldRemoveWWWInCanonicalization = true

    override func setUp() async throws {
        mockAPIClient = MockMaliciousSiteProtectionAPIClient()
        mockDataManager = MockMaliciousSiteProtectionDataManager()
        mockEventMapping = MockEventMapping()
        detector = MaliciousSiteDetector(apiClient: mockAPIClient, dataManager: mockDataManager, eventMapping: mockEventMapping, supportedThreatsProvider: { return self.isScamProtectionSupported ? ThreatKind.allCases : ThreatKind.allCases.filter{ $0 != .scam } }, shouldRemoveWWWInCanonicalization: { self.shouldRemoveWWWInCanonicalization })
    }

    override func tearDown() async throws {
        mockAPIClient = nil
        mockDataManager = nil
        mockEventMapping = nil
        detector = nil
    }

    func testIsMaliciousWithLocalFilterHit() async throws {
        let filter = Filter(hash: "255a8a793097aeea1f06a19c08cde28db0eb34c660c6e4e7480c9525d034b16d", regex: ".*malicious.*")
        try await mockDataManager.store(FilterDictionary(revision: 0, items: [filter]), for: .filterSet(threatKind: .phishing))
        try await mockDataManager.store(HashPrefixSet(revision: 0, items: ["255a8a79"]), for: .hashPrefixes(threatKind: .phishing))

        let url = URL(string: "https://malicious.com/")!

        let result = await detector.evaluate(url)

        XCTAssertEqual(result, .phishing)
    }

    func testIsScamWithLocalFilterHitReturnsNilIfFlagOff() async throws {
        isScamProtectionSupported = false
        let filter = Filter(hash: "5392ef04dc5f963fe5bc9545365de61312d7070df12aafff87e65ec55a7803a4", regex: ".*scam.*")
        try await mockDataManager.store(FilterDictionary(revision: 0, items: [filter]), for: .filterSet(threatKind: .scam))
        try await mockDataManager.store(HashPrefixSet(revision: 0, items: ["5392ef04"]), for: .hashPrefixes(threatKind: .scam))

        let url = URL(string: "https://scam.com/")!

        let result = await detector.evaluate(url)

        XCTAssertNil(result)
    }

    func testIsScamWithLocalFilterHit() async throws {
        isScamProtectionSupported = true
        let filter = Filter(hash: "5392ef04dc5f963fe5bc9545365de61312d7070df12aafff87e65ec55a7803a4", regex: ".*scam.*")
        try await mockDataManager.store(FilterDictionary(revision: 0, items: [filter]), for: .filterSet(threatKind: .scam))
        try await mockDataManager.store(HashPrefixSet(revision: 0, items: ["5392ef04"]), for: .hashPrefixes(threatKind: .scam))

        let url = URL(string: "https://scam.com/")!

        let result = await detector.evaluate(url)

        XCTAssertEqual(result, .scam)
    }

    func testIsMaliciousWithApiMatch() async throws {
        try await mockDataManager.store(FilterDictionary(revision: 0, items: []), for: .filterSet(threatKind: .phishing))
        try await mockDataManager.store(HashPrefixSet(revision: 0, items: ["a379a6f6"]), for: .hashPrefixes(threatKind: .phishing))

        let url = URL(string: "https://example.com/mal")!

        let result = await detector.evaluate(url)

        XCTAssertEqual(result, .phishing)
    }

    func testIsMaliciousWithHashPrefixMatch() async throws {
        let filter = Filter(hash: "notamatch", regex: ".*malicious.*")
        try await mockDataManager.store(FilterDictionary(revision: 0, items: [filter]), for: .filterSet(threatKind: .phishing))
        try await mockDataManager.store(HashPrefixSet(revision: 0, items: ["4c64eb24" /* matches safe.com */]), for: .hashPrefixes(threatKind: .phishing))

        let url = URL(string: "https://safe.com")!

        let result = await detector.evaluate(url)

        XCTAssertNil(result)
    }

    func testIsMaliciousWithFullHashMatch() async throws {
        // 4c64eb2468bcd3e113b37167e6b819aeccf550f974a6082ef17fb74ca68e823b
        let filter = Filter(hash: "4c64eb2468bcd3e113b37167e6b819aeccf550f974a6082ef17fb74ca68e823b", regex: "https://safe.com/maliciousURI")
        try await mockDataManager.store(FilterDictionary(revision: 0, items: [filter]), for: .filterSet(threatKind: .phishing))
        try await mockDataManager.store(HashPrefixSet(revision: 0, items: ["4c64eb24"]), for: .hashPrefixes(threatKind: .phishing))

        let url = URL(string: "https://safe.com")!

        let result = await detector.evaluate(url)

        XCTAssertNil(result)
    }

    func testIsMaliciousWithNoHashPrefixMatch() async throws {
        let filter = Filter(hash: "testHash", regex: ".*malicious.*")
        try await mockDataManager.store(FilterDictionary(revision: 0, items: [filter]), for: .filterSet(threatKind: .phishing))
        try await mockDataManager.store(HashPrefixSet(revision: 0, items: ["testPrefix"]), for: .hashPrefixes(threatKind: .phishing))

        let url = URL(string: "https://safe.com")!

        let result = await detector.evaluate(url)

        XCTAssertNil(result)
    }

    func testWhenMatchesApiFailsThenEventIsFired() async throws {
        let e = expectation(description: "matchesForHashPrefix called")
        mockAPIClient.matchesForHashPrefix = { _ in
            let error = Networking.APIRequestV2.Error.urlSession(URLError(.badServerResponse))
            XCTAssertFalse(error.isTimedOut)
            e.fulfill()
            throw error
        }

        try await mockDataManager.store(HashPrefixSet(revision: 0, items: ["255a8a79"]), for: .hashPrefixes(threatKind: .phishing))

        let url = URL(string: "https://malicious.com/")!
        let result = await detector.evaluate(url)
        XCTAssertNil(result)

        await fulfillment(of: [e], timeout: 0)

        XCTAssertEqual(mockEventMapping.events.count, 1)
        switch mockEventMapping.events.last {
        case .matchesApiFailure(APIRequestV2.Error.urlSession(URLError.badServerResponse)):
            break
        case .none:
            XCTFail( "No event fired")
        case .some(let event):
            XCTFail("Unexpected event \(event)")
        }
    }

    func testWhenMatchesApiFailsWithTimeoutThenEventIsFired() async throws {
        let e = expectation(description: "matchesForHashPrefix called")
        mockAPIClient.matchesForHashPrefix = { _ in
            let error = Networking.APIRequestV2.Error.urlSession(URLError(.timedOut))
            XCTAssertTrue(error.isTimedOut) // should match testWhenMatchesRequestTimeouts_TimeoutErrorThrown!
            e.fulfill()
            throw error
        }

        try await mockDataManager.store(HashPrefixSet(revision: 0, items: ["255a8a79"]), for: .hashPrefixes(threatKind: .phishing))

        let url = URL(string: "https://malicious.com/")!
        let result = await detector.evaluate(url)
        XCTAssertNil(result)

        await fulfillment(of: [e], timeout: 0)

        XCTAssertEqual(mockEventMapping.events.count, 1)
        switch mockEventMapping.events.last {
        case .matchesApiTimeout:
            break
        case .none:
            XCTFail( "No event fired")
        case .some(let event):
            XCTFail("Unexpected event \(event)")
        }
    }

    func testWhenLocalFilterHitAndFilterSetSmallerThanHundredThenClientSideHitParameterIsNil() async throws {
        // GIVEN
        let filter = Filter(hash: "255a8a793097aeea1f06a19c08cde28db0eb34c660c6e4e7480c9525d034b16d", regex: ".*malicious.*")
        try await mockDataManager.store(FilterDictionary(revision: 0, items: [filter]), for: .filterSet(threatKind: .phishing))
        try await mockDataManager.store(HashPrefixSet(revision: 0, items: ["255a8a79"]), for: .hashPrefixes(threatKind: .phishing))
        let url = URL(string: "https://malicious.com/")!

        // WHEN
        _ = await detector.evaluate(url)

        // THEN
        XCTAssertEqual(mockEventMapping.events.count, 1)
        switch mockEventMapping.events.last {
        case let .errorPageShown(_, clientSideHit):
            XCTAssertNil(clientSideHit)
        default:
            XCTFail("Wrong event fired")
        }
    }

    func testWhenLocalFilterHitAndFilterSetGreaterThanHundredThenClientSideHitParameterIsSent() async throws {
        // GIVEN
        let maliciousFilter = Filter(hash: "255a8a793097aeea1f06a19c08cde28db0eb34c660c6e4e7480c9525d034b16d", regex: ".*malicious.*")
        let filters = (1...100).map { i in
            Filter(hash: "255a8a793097aeea1f06a19c08cde28db0eb34c660c6e4e7480c9525d034b16d\(i)", regex: ".*malicious.*")
        } + [maliciousFilter]
        try await mockDataManager.store(FilterDictionary(revision: 0, items: filters), for: .filterSet(threatKind: .phishing))
        try await mockDataManager.store(HashPrefixSet(revision: 0, items: ["255a8a79"]), for: .hashPrefixes(threatKind: .phishing))
        let url = URL(string: "https://malicious.com/")!

        // WHEN
        _ = await detector.evaluate(url)

        // THEN
        XCTAssertEqual(mockEventMapping.events.count, 1)
        switch mockEventMapping.events.last {
        case let .errorPageShown(_, clientSideHit):
            XCTAssertNotNil(clientSideHit)
        default:
            XCTFail("Wrong event fired")
        }
    }

    func testWhenMatchesAPIAndFilterSetSmallerThanHundredThenClientSideHitParameterIsNil() async throws {
        // GIVEN
        try await mockDataManager.store(HashPrefixSet(revision: 0, items: ["a379a6f6"]), for: .hashPrefixes(threatKind: .phishing))
        let url = URL(string: "https://example.com/mal")!

        // WHEN
        _ = await detector.evaluate(url)

        // THEN
        XCTAssertEqual(mockEventMapping.events.count, 1)
        switch mockEventMapping.events.last {
        case let .errorPageShown(_, clientSideHit):
            XCTAssertNil(clientSideHit)
        default:
            XCTFail("Wrong event fired")
        }
    }

    func testWhenMatchesAPIAndFilterSetGreaterThanHundredThenClientSideHitParameterIsSet() async throws {
        // GIVEN
        let maliciousFilter = Filter(hash: "255a8a793097aeea1f06a19c08cde28db0eb34c660c6e4e7480c9525d034b16d", regex: ".*malicious.*")
        let filters = (1...100).map { i in
            Filter(hash: "255a8a793097aeea1f06a19c08cde28db0eb34c660c6e4e7480c9525d034b16d\(i)", regex: ".*malicious.*")
        } + [maliciousFilter]
        try await mockDataManager.store(FilterDictionary(revision: 0, items: filters), for: .filterSet(threatKind: .phishing))
        try await mockDataManager.store(HashPrefixSet(revision: 0, items: ["a379a6f6"]), for: .hashPrefixes(threatKind: .phishing))
        let url = URL(string: "https://example.com/mal")!

        // WHEN
         _ = await detector.evaluate(url)

        // THEN
        XCTAssertEqual(mockEventMapping.events.count, 1)
        switch mockEventMapping.events.last {
        case let .errorPageShown(_, clientSideHit):
            XCTAssertNotNil(clientSideHit)
        default:
            XCTFail("Wrong event fired")
        }
    }

    // MARK: - WWW Canonicalization Tests

    func testMaliciousDetectionWithWWWRemovalEnabled() async throws {
        // GIVEN
        shouldRemoveWWWInCanonicalization = true
        let filter = Filter(hash: "255a8a793097aeea1f06a19c08cde28db0eb34c660c6e4e7480c9525d034b16d", regex: ".*malicious.*")
        try await mockDataManager.store(FilterDictionary(revision: 0, items: [filter]), for: .filterSet(threatKind: .phishing))
        try await mockDataManager.store(HashPrefixSet(revision: 0, items: ["255a8a79"]), for: .hashPrefixes(threatKind: .phishing))

        // WHEN
        let wwwUrl = URL(string: "https://www.malicious.com/")!
        let nonWwwUrl = URL(string: "https://malicious.com/")!

        let wwwResult = await detector.evaluate(wwwUrl)
        let nonWwwResult = await detector.evaluate(nonWwwUrl)

        // THEN Both www and non-www URLs should match when removal is enabled
        XCTAssertEqual(wwwResult, .phishing)
        XCTAssertEqual(nonWwwResult, .phishing)
    }

    func testMaliciousDetectionWithWWWRemovalDisabled() async throws {
        // GIVEN
        shouldRemoveWWWInCanonicalization = false
        let wwwFilter = Filter(hash: "255a8a793097aeea1f06a19c08cde28db0eb34c660c6e4e7480c9525d034b16d", regex: ".*malicious.*")
        try await mockDataManager.store(FilterDictionary(revision: 0, items: [wwwFilter]), for: .filterSet(threatKind: .phishing))
        try await mockDataManager.store(HashPrefixSet(revision: 0, items: ["255a8a79"]), for: .hashPrefixes(threatKind: .phishing))

        // WHEN
        let wwwUrl = URL(string: "https://www.malicious.com/")!
        let nonWwwUrl = URL(string: "https://malicious.com/")!

        let wwwResult = await detector.evaluate(wwwUrl)
        let nonWwwResult = await detector.evaluate(nonWwwUrl)

        // THEN www and non-www URLs should be treated differently when removal is disabled
        XCTAssertNil(wwwResult)
        XCTAssertEqual(nonWwwResult, .phishing)
    }
}
