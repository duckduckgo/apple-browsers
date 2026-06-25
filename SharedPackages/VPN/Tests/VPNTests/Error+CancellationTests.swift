//
//  Error+CancellationTests.swift
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
@testable import VPN

final class ErrorCancellationTests: XCTestCase {

    func testBareCancellationErrorIsCancellation() {
        let error: Error = CancellationError()
        XCTAssertTrue(error.isCancellation)
    }

    func testUnrelatedErrorsAreNotCancellation() {
        XCTAssertFalse(URLError(.timedOut).isCancellation)
        XCTAssertFalse(NSError(domain: "Test", code: 1).isCancellation)
    }

    /// Only Swift `CancellationError` counts. Framework-specific cancellations from other domains are
    /// not what reaches this path and are deliberately not matched.
    func testOtherDomainCancellationsAreNotCancellation() {
        XCTAssertFalse(URLError(.cancelled).isCancellation)
        XCTAssertFalse(CocoaError(.userCancelled).isCancellation)
    }

    func testCancellationWrappedInUnderlyingErrorIsCancellation() {
        let wrapped = NSError(domain: "Test", code: 1, userInfo: [NSUnderlyingErrorKey: CancellationError()])
        XCTAssertTrue(wrapped.isCancellation)
    }

    /// Mirrors `StartError.startTunnelFailure(CancellationError())`: a `CustomNSError` that exposes the
    /// cancellation only through `errorUserInfo[NSUnderlyingErrorKey]`. This is the exact production path
    /// that previously fired the start-failure pixel.
    func testCustomNSErrorWrappingCancellationIsCancellation() {
        struct WrappingError: Error, CustomNSError {
            let underlying: Error
            var errorUserInfo: [String: Any] { [NSUnderlyingErrorKey: underlying] }
        }

        let error: Error = WrappingError(underlying: CancellationError())
        XCTAssertTrue(error.isCancellation)
    }

    func testCustomNSErrorWrappingNonCancellationIsNotCancellation() {
        struct WrappingError: Error, CustomNSError {
            let underlying: Error
            var errorUserInfo: [String: Any] { [NSUnderlyingErrorKey: underlying] }
        }

        let error: Error = WrappingError(underlying: URLError(.timedOut))
        XCTAssertFalse(error.isCancellation)
    }

    func testDeeplyNestedCancellationIsCancellation() {
        let inner = NSError(domain: "A", code: 1, userInfo: [NSUnderlyingErrorKey: CancellationError()])
        let outer = NSError(domain: "B", code: 2, userInfo: [NSUnderlyingErrorKey: inner])
        XCTAssertTrue(outer.isCancellation)
    }

    func testDeeplyNestedNonCancellationIsNotCancellation() {
        let inner = NSError(domain: "A", code: 1, userInfo: [NSUnderlyingErrorKey: URLError(.timedOut)])
        let outer = NSError(domain: "B", code: 2, userInfo: [NSUnderlyingErrorKey: inner])
        XCTAssertFalse(outer.isCancellation)
    }
}
