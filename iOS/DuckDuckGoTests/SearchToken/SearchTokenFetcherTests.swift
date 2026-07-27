//
//  SearchTokenFetcherTests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo

final class SearchTokenFetcherTests: XCTestCase {

    // MARK: retrieveToken / TTL

    func testRetrieveReturnsNilWhenEmpty() {
        let sut = SearchTokenFetcher(requester: MockSearchTokenRequester())
        XCTAssertNil(sut.retrieveToken())
    }

    func testRetrieveReturnsTokenWhileAlive() async {
        let clock = Clock(Date(timeIntervalSince1970: 1000))
        let requester = MockSearchTokenRequester()
        requester.tokenToReturn = "abc"
        let sut = SearchTokenFetcher(requester: requester, ttlProvider: { 300 }, now: clock.now)
        await sut.fetchIfNeeded(userAgent: "UA") // caches "abc" at t0
        clock.advance(299) // still within TTL
        XCTAssertEqual(sut.retrieveToken(), "abc")
    }

    func testRetrieveReturnsNilAfterExpiry() async {
        let clock = Clock(Date(timeIntervalSince1970: 1000))
        let requester = MockSearchTokenRequester()
        requester.tokenToReturn = "abc"
        let sut = SearchTokenFetcher(requester: requester, ttlProvider: { 300 }, now: clock.now)
        await sut.fetchIfNeeded(userAgent: "UA") // caches "abc" at t0
        clock.advance(300) // exactly TTL -> expired
        XCTAssertNil(sut.retrieveToken())
    }

    // MARK: fetch success

    func testFetchStoresTokenAndPassesUserAgent() async {
        let clock = Clock(Date(timeIntervalSince1970: 1000))
        let requester = MockSearchTokenRequester()
        requester.tokenToReturn = "tok-123"
        let sut = SearchTokenFetcher(requester: requester, now: clock.now)

        await sut.fetchIfNeeded(userAgent: "UA/1.0")

        XCTAssertEqual(sut.retrieveToken(), "tok-123")
        XCTAssertEqual(requester.lastUserAgent, "UA/1.0")
    }

    // MARK: refresh-ahead skip window

    func testSkipsWhenTokenStillFresh() async {
        let clock = Clock(Date(timeIntervalSince1970: 1000))
        let requester = MockSearchTokenRequester()
        requester.tokenToReturn = "fresh"
        let sut = SearchTokenFetcher(requester: requester, ttlProvider: { 300 }, windowProvider: { 120 }, now: clock.now)
        await sut.fetchIfNeeded(userAgent: "UA") // caches "fresh" at t0 (callCount 1)
        clock.advance(100) // remaining 200 > window 120 -> skip
        await sut.fetchIfNeeded(userAgent: "UA")
        XCTAssertEqual(requester.callCount, 1) // second call skipped
        XCTAssertEqual(sut.retrieveToken(), "fresh")
    }

    func testFetchesWhenWithinWindow() async {
        let clock = Clock(Date(timeIntervalSince1970: 1000))
        let requester = MockSearchTokenRequester()
        requester.tokenToReturn = "old"
        let sut = SearchTokenFetcher(requester: requester, ttlProvider: { 300 }, windowProvider: { 120 }, now: clock.now)
        await sut.fetchIfNeeded(userAgent: "UA") // caches "old" at t0 (callCount 1)
        clock.advance(200) // remaining 100 <= window 120 -> fetch
        requester.tokenToReturn = "new"
        await sut.fetchIfNeeded(userAgent: "UA")
        XCTAssertEqual(requester.callCount, 2)
        XCTAssertEqual(sut.retrieveToken(), "new")
    }

    // MARK: coalescing + failure

    func testConcurrentTriggersCoalesceIntoOneRequest() async {
        let clock = Clock(Date(timeIntervalSince1970: 1000))
        let gate = Gate()
        let requester = MockSearchTokenRequester()
        requester.onRequest = {
            await gate.signalEntered()
            await gate.waitUntilOpen()
        }
        let sut = SearchTokenFetcher(requester: requester, now: clock.now)

        async let first: Void = sut.fetchIfNeeded(userAgent: "UA")
        await gate.waitUntilEntered()          // first fetch is now in flight (isFetching == true)
        await sut.fetchIfNeeded(userAgent: "UA") // sees isFetching -> coalesced, no second request
        await gate.open()
        await first

        XCTAssertEqual(requester.callCount, 1)
    }

    func testFailureKeepsPreviousTokenAndDoesNotExtendExpiry() async {
        let clock = Clock(Date(timeIntervalSince1970: 1000))
        let requester = MockSearchTokenRequester()
        requester.tokenToReturn = "old"
        let sut = SearchTokenFetcher(requester: requester, ttlProvider: { 300 }, windowProvider: { 120 }, now: clock.now)
        await sut.fetchIfNeeded(userAgent: "UA") // caches "old" at t0
        clock.advance(200) // within window -> attempts a fetch
        requester.error = URLError(.notConnectedToInternet)
        await sut.fetchIfNeeded(userAgent: "UA")
        XCTAssertEqual(sut.retrieveToken(), "old") // failed fetch keeps the previous token

        // The failed fetch must NOT reset fetchedAt: advancing past the ORIGINAL t0 expiry must expire it.
        clock.advance(101) // total 301 since t0 > ttl 300
        XCTAssertNil(sut.retrieveToken())
    }
}

// MARK: - Test doubles

private final class MockSearchTokenRequester: SearchTokenRequesting {
    var tokenToReturn = "tok"
    var error: Error?
    private(set) var callCount = 0
    private(set) var lastUserAgent: String?
    var onRequest: (() async -> Void)?

    func requestToken(userAgent: String) async throws -> String {
        callCount += 1
        lastUserAgent = userAgent
        await onRequest?()
        if let error { throw error }
        return tokenToReturn
    }
}

/// Mutable clock; `now` reads the current value each call (captured by reference).
private final class Clock {
    private(set) var value: Date
    init(_ start: Date) { value = start }
    func advance(_ seconds: TimeInterval) { value = value.addingTimeInterval(seconds) }
    var now: () -> Date { { self.value } }
}

/// Coordinates deterministic ordering between the test and the in-flight request stub.
private actor Gate {
    private var opened = false
    private var entered = false
    private var openWaiters: [CheckedContinuation<Void, Never>] = []
    private var enteredWaiter: CheckedContinuation<Void, Never>?

    func signalEntered() {
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func waitUntilOpen() async {
        if opened { return }
        await withCheckedContinuation { openWaiters.append($0) }
    }

    func open() {
        opened = true
        openWaiters.forEach { $0.resume() }
        openWaiters.removeAll()
    }
}
