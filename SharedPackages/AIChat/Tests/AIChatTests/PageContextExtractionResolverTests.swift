//
//  PageContextExtractionResolverTests.swift
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
@testable import AIChat

final class PageContextExtractionResolverTests: XCTestCase {

    private func nonEmptyContext() -> AIChatPageContextData {
        AIChatPageContextData(title: "Title", favicon: [], url: "https://example.com", content: "body", truncated: false, fullContentLength: 100)
    }

    private func emptyContext() -> AIChatPageContextData {
        AIChatPageContextData(title: "", favicon: [], url: "https://example.com", content: "", truncated: false, fullContentLength: 0)
    }

    private func time(_ seconds: Double) -> DispatchTime {
        DispatchTime(uptimeNanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: - Skip when there is no outstanding request

    func testWhenResolveWithNoRequestThenReturnsNil() {
        var resolver = PageContextExtractionResolver()
        XCTAssertNil(resolver.resolve(pageContext: nonEmptyContext()))
    }

    func testWhenExtraResultArrivesAfterDrainingThenReturnsNil() {
        var resolver = PageContextExtractionResolver()
        resolver.requested(trigger: .navigation)
        XCTAssertNotNil(resolver.resolve(pageContext: nonEmptyContext()))
        // A second (duplicate) result with nothing pending is skipped — the over-count fix.
        XCTAssertNil(resolver.resolve(pageContext: nonEmptyContext()))
    }

    // MARK: - Reset on navigation

    func testWhenResetThenPendingCollectionsCleared() {
        var resolver = PageContextExtractionResolver()
        resolver.requested(trigger: .navigation)
        resolver.requested(trigger: .userRequest)
        XCTAssertTrue(resolver.hasPendingCollections)

        resolver.reset()

        XCTAssertFalse(resolver.hasPendingCollections)
        // A previous page's result arriving after reset has nothing to pair with, so it can't
        // mis-attribute the next page's telemetry.
        XCTAssertNil(resolver.resolve(pageContext: nonEmptyContext()))
    }

    // MARK: - Outcome derivation

    func testWhenNonEmptyContextThenSuccess() {
        var resolver = PageContextExtractionResolver()
        resolver.requested(trigger: .navigation)
        XCTAssertEqual(resolver.resolve(pageContext: nonEmptyContext())?.outcome, .success)
    }

    func testWhenEmptyContextThenEmptyContentFailure() {
        var resolver = PageContextExtractionResolver()
        resolver.requested(trigger: .auto)
        XCTAssertEqual(resolver.resolve(pageContext: emptyContext())?.outcome, .failure(.emptyContent))
    }

    func testWhenNilContextThenDeserializeFailedFailure() {
        var resolver = PageContextExtractionResolver()
        resolver.requested(trigger: .auto)
        XCTAssertEqual(resolver.resolve(pageContext: nil)?.outcome, .failure(.deserializeFailed))
    }

    // MARK: - FIFO trigger attribution

    func testWhenTwoRequestsThenResolvedInOrderWithTheirOwnTriggers() {
        var resolver = PageContextExtractionResolver()
        resolver.requested(trigger: .navigation)
        resolver.requested(trigger: .userRequest)

        XCTAssertEqual(resolver.resolve(pageContext: nonEmptyContext())?.trigger, .navigation)
        XCTAssertEqual(resolver.resolve(pageContext: nonEmptyContext())?.trigger, .userRequest)
        XCTAssertNil(resolver.resolve(pageContext: nonEmptyContext()))
    }

    /// The review scenario: the eager pre-markup collect returns empty and the post-markup collect
    /// succeeds. Each must be reported accurately rather than one corrupting the other.
    func testWhenEagerEmptyFollowedByRealSuccessThenBothReportedCorrectly() {
        var resolver = PageContextExtractionResolver()
        resolver.requested(trigger: .navigation)
        resolver.requested(trigger: .navigation)

        let eager = resolver.resolve(pageContext: emptyContext())
        XCTAssertEqual(eager?.outcome, .failure(.emptyContent))
        XCTAssertEqual(eager?.trigger, .navigation)

        let real = resolver.resolve(pageContext: nonEmptyContext())
        XCTAssertEqual(real?.outcome, .success)
        XCTAssertEqual(real?.trigger, .navigation)
    }

    // MARK: - Latency bucketing (paired to each request's own start time)

    func testWhenUnderOneSecondThenUnder1sBucket() {
        var resolver = PageContextExtractionResolver()
        resolver.requested(trigger: .navigation, at: time(10))
        XCTAssertEqual(resolver.resolve(pageContext: nonEmptyContext(), now: time(10.5))?.latency, .under1s)
    }

    func testWhenExactlyOneSecondThenOneToFiveBucket() {
        var resolver = PageContextExtractionResolver()
        resolver.requested(trigger: .navigation, at: time(10))
        XCTAssertEqual(resolver.resolve(pageContext: nonEmptyContext(), now: time(11))?.latency, .oneToFiveSeconds)
    }

    func testWhenExactlyFiveSecondsThenOneToFiveBucket() {
        var resolver = PageContextExtractionResolver()
        resolver.requested(trigger: .navigation, at: time(10))
        XCTAssertEqual(resolver.resolve(pageContext: nonEmptyContext(), now: time(15))?.latency, .oneToFiveSeconds)
    }

    func testWhenOverFiveSecondsThenOver5sBucket() {
        var resolver = PageContextExtractionResolver()
        resolver.requested(trigger: .navigation, at: time(10))
        XCTAssertEqual(resolver.resolve(pageContext: nonEmptyContext(), now: time(16))?.latency, .over5s)
    }

    func testWhenTwoRequestsThenEachGetsItsOwnLatency() {
        var resolver = PageContextExtractionResolver()
        resolver.requested(trigger: .navigation, at: time(10))
        resolver.requested(trigger: .userRequest, at: time(14))

        // First request started at 10; resolved at 10.4 → under 1s.
        XCTAssertEqual(resolver.resolve(pageContext: nonEmptyContext(), now: time(10.4))?.latency, .under1s)
        // Second request started at 14; resolved at 20 → over 5s (not measured from the first start).
        XCTAssertEqual(resolver.resolve(pageContext: nonEmptyContext(), now: time(20))?.latency, .over5s)
    }

    // MARK: - hasPendingCollections

    func testHasPendingCollectionsReflectsQueueState() {
        var resolver = PageContextExtractionResolver()
        XCTAssertFalse(resolver.hasPendingCollections)
        resolver.requested(trigger: .navigation)
        XCTAssertTrue(resolver.hasPendingCollections)
        _ = resolver.resolve(pageContext: nonEmptyContext())
        XCTAssertFalse(resolver.hasPendingCollections)
    }

    // MARK: - Timeout expiry

    func testWhenCollectionExceedsTimeoutThenExpiredAsTimeoutWithNilLatency() {
        var resolver = PageContextExtractionResolver()
        resolver.requested(trigger: .navigation, at: time(0))
        let expired = resolver.expireCollections(olderThan: 5, now: time(6))
        XCTAssertEqual(expired.count, 1)
        XCTAssertEqual(expired.first?.outcome, .failure(.timeout))
        XCTAssertEqual(expired.first?.trigger, .navigation)
        XCTAssertNil(expired.first?.latency)
        XCTAssertFalse(resolver.hasPendingCollections)
    }

    func testWhenCollectionWithinTimeoutThenNotExpired() {
        var resolver = PageContextExtractionResolver()
        resolver.requested(trigger: .navigation, at: time(0))
        XCTAssertTrue(resolver.expireCollections(olderThan: 5, now: time(3)).isEmpty)
        XCTAssertTrue(resolver.hasPendingCollections)
    }

    func testWhenMultipleCollectionsExpireThenReturnedOldestFirst() {
        var resolver = PageContextExtractionResolver()
        resolver.requested(trigger: .navigation, at: time(0))
        resolver.requested(trigger: .userRequest, at: time(1))
        let expired = resolver.expireCollections(olderThan: 5, now: time(7))
        XCTAssertEqual(expired.map(\.trigger), [.navigation, .userRequest])
        XCTAssertFalse(resolver.hasPendingCollections)
    }

    func testWhenOnlyOldCollectionsExpireThenNewerRemainForNextResult() {
        var resolver = PageContextExtractionResolver()
        resolver.requested(trigger: .navigation, at: time(0))
        resolver.requested(trigger: .userRequest, at: time(4))
        // At t=6 only the first (age 6) is past the 5s timeout; the second (age 2) stays pending.
        XCTAssertEqual(resolver.expireCollections(olderThan: 5, now: time(6)).map(\.trigger), [.navigation])
        XCTAssertTrue(resolver.hasPendingCollections)
        XCTAssertEqual(resolver.resolve(pageContext: nonEmptyContext(), now: time(6))?.trigger, .userRequest)
    }

    func testWhenResolvedBeforeTimeoutThenExpiryIsNoOp() {
        var resolver = PageContextExtractionResolver()
        resolver.requested(trigger: .navigation, at: time(0))
        _ = resolver.resolve(pageContext: nonEmptyContext(), now: time(1))
        XCTAssertTrue(resolver.expireCollections(olderThan: 5, now: time(10)).isEmpty)
    }
}
