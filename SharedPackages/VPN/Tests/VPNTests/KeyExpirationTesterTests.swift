//
//  KeyExpirationTesterTests.swift
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

import Foundation
import XCTest
@testable import VPN

@MainActor
private final class RekeyRecorder {
    var callCount = 0
    var shouldThrow = true

    /// When `true`, `call()` suspends until `resume()` is invoked, letting a test interleave other
    /// work (e.g. `stop()`) while a rekey is in flight. `onPaused` fires once the suspension begins.
    var shouldPause = false
    var onPaused: (() -> Void)?
    private var pauseContinuation: CheckedContinuation<Void, Never>?

    func call() async throws {
        callCount += 1

        if shouldPause {
            await withCheckedContinuation { continuation in
                pauseContinuation = continuation
                onPaused?()
            }
        }

        if shouldThrow {
            throw RekeyError.failure
        }
    }

    func resume() {
        pauseContinuation?.resume()
        pauseContinuation = nil
    }
}

private enum RekeyError: Error {
    case failure
}

private final class TestDateProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var internalDate: Date

    init(date: Date) {
        self.internalDate = date
    }

    var date: Date {
        lock.lock()
        defer { lock.unlock() }
        return internalDate
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        internalDate = internalDate.addingTimeInterval(interval)
    }
}

@MainActor
final class KeyExpirationTesterTests: XCTestCase {

    private var keyStore: NetworkProtectionKeyStoreMock!
    private var settings: VPNSettings!
    private var rekeyRecorder: RekeyRecorder!
    private var dateProvider: TestDateProvider!

    override func setUp() {
        super.setUp()

        keyStore = NetworkProtectionKeyStoreMock()
        settings = VPNSettings(defaults: .standard)
        rekeyRecorder = RekeyRecorder()
        dateProvider = TestDateProvider(date: Date(timeIntervalSince1970: 0))
        keyStore.currentExpirationDate = dateProvider.date.addingTimeInterval(-1)
    }

    override func tearDown() {
        rekeyRecorder = nil
        settings = nil
        keyStore = nil
        dateProvider = nil
        super.tearDown()
    }

    func testRekeyIfExpired_whenPreviousFailureIsInBackoff_skipsImmediateRetry() async {
        let tester = makeTester()

        await tester.rekeyIfExpired()
        await tester.rekeyIfExpired()

        XCTAssertEqual(rekeyRecorder.callCount, 1)
    }

    func testRekeyIfExpired_whenRekeyKeepsFailing_backsOffUpToFiveMinutes() async {
        let tester = makeTester()

        await tester.rekeyIfExpired()
        XCTAssertEqual(rekeyRecorder.callCount, 1)

        dateProvider.advance(by: .seconds(14))
        await tester.rekeyIfExpired()
        XCTAssertEqual(rekeyRecorder.callCount, 1)

        dateProvider.advance(by: .seconds(1))
        await tester.rekeyIfExpired()
        XCTAssertEqual(rekeyRecorder.callCount, 2)

        dateProvider.advance(by: .seconds(29))
        await tester.rekeyIfExpired()
        XCTAssertEqual(rekeyRecorder.callCount, 2)

        dateProvider.advance(by: .seconds(1))
        await tester.rekeyIfExpired()
        XCTAssertEqual(rekeyRecorder.callCount, 3)

        dateProvider.advance(by: .seconds(59))
        await tester.rekeyIfExpired()
        XCTAssertEqual(rekeyRecorder.callCount, 3)

        dateProvider.advance(by: .seconds(1))
        await tester.rekeyIfExpired()
        XCTAssertEqual(rekeyRecorder.callCount, 4)

        dateProvider.advance(by: .seconds(119))
        await tester.rekeyIfExpired()
        XCTAssertEqual(rekeyRecorder.callCount, 4)

        dateProvider.advance(by: .seconds(1))
        await tester.rekeyIfExpired()
        XCTAssertEqual(rekeyRecorder.callCount, 5)

        dateProvider.advance(by: .seconds(299))
        await tester.rekeyIfExpired()
        XCTAssertEqual(rekeyRecorder.callCount, 5)

        dateProvider.advance(by: .seconds(1))
        await tester.rekeyIfExpired()
        XCTAssertEqual(rekeyRecorder.callCount, 6)

        dateProvider.advance(by: .seconds(299))
        await tester.rekeyIfExpired()
        XCTAssertEqual(rekeyRecorder.callCount, 6)

        dateProvider.advance(by: .seconds(1))
        await tester.rekeyIfExpired()
        XCTAssertEqual(rekeyRecorder.callCount, 7)
    }

    func testStop_resetsFailureBackoff() async {
        let tester = makeTester()

        await tester.rekeyIfExpired()
        XCTAssertEqual(rekeyRecorder.callCount, 1)

        await tester.stop()
        await tester.rekeyIfExpired()

        XCTAssertEqual(rekeyRecorder.callCount, 2)
    }

    func testStop_whenRekeyFailsAfterStopping_doesNotRestoreFailureBackoff() async {
        let tester = makeTester()

        // Pause inside `rekey()` so we can stop the tester while a rekey is still in flight.
        rekeyRecorder.shouldPause = true
        let paused = expectation(description: "rekey paused mid-flight")
        rekeyRecorder.onPaused = { paused.fulfill() }

        let inFlightRekey = Task { await tester.rekeyIfExpired() }
        await fulfillment(of: [paused], timeout: 1.0)
        XCTAssertEqual(rekeyRecorder.callCount, 1)

        // Stop clears the failure backoff while the rekey is suspended at `await rekey()`.
        await tester.stop()

        // Let the in-flight rekey resume and throw. Its failure must not restore the backoff
        // that `stop()` just cleared.
        rekeyRecorder.resume()
        await inFlightRekey.value

        // With no stale backoff date, an immediate rekey should run rather than be delayed.
        rekeyRecorder.shouldPause = false
        await tester.rekeyIfExpired()

        XCTAssertEqual(rekeyRecorder.callCount, 2)
    }

    func testRekeyIfExpired_usesCurrentDateProviderToDetermineExpiration() async {
        keyStore.currentExpirationDate = dateProvider.date.addingTimeInterval(.seconds(1))
        let tester = makeTester()

        await tester.rekeyIfExpired()
        XCTAssertEqual(rekeyRecorder.callCount, 0)

        dateProvider.advance(by: .seconds(2))
        await tester.rekeyIfExpired()
        XCTAssertEqual(rekeyRecorder.callCount, 1)
    }

    private func makeTester(canRekey: Bool = true) -> KeyExpirationTester {
        KeyExpirationTester(
            keyStore: keyStore,
            settings: settings,
            currentDate: { [dateProvider] in
                dateProvider?.date ?? Date()
            },
            canRekey: {
                canRekey
            },
            rekey: { [rekeyRecorder] in
                try await rekeyRecorder?.call()
            }
        )
    }
}
