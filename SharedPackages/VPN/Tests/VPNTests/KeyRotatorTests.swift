//
//  KeyRotatorTests.swift
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

import Common
import Foundation
import XCTest
@testable import VPN

/// Reference holder for fired events. EventMapping's closure is @Sendable, so we
/// can't directly capture `self` (XCTestCase isn't Sendable). The box is only ever
/// written/read from MainActor via assumeIsolated, so @unchecked is safe.
private final class FiredEventsBox: @unchecked Sendable {
    var events: [PacketTunnelProvider.Event] = []
}

/// Records rotateKey invocations and lets a test inject an error to throw.
@MainActor
private final class RotateKeyRecorder {
    var callCount = 0
    var errorToThrow: Error?

    func call() async throws {
        callCount += 1
        if let errorToThrow {
            throw errorToThrow
        }
    }
}

// MARK: - Tests

@MainActor
final class KeyRotatorTests: XCTestCase {

    private var keyStore: NetworkProtectionKeyStoreMock!
    private var settings: VPNSettings!
    private var firedEvents: FiredEventsBox!
    private var events: EventMapping<PacketTunnelProvider.Event>!
    private var rotateKeyRecorder: RotateKeyRecorder!
    private var rotator: KeyRotator!

    override func setUp() {
        super.setUp()

        keyStore = NetworkProtectionKeyStoreMock()
        settings = VPNSettings(defaults: .standard)
        settings.disableRekeying = false

        let box = FiredEventsBox()
        firedEvents = box
        // Events are fired from @MainActor contexts in KeyRotator, so capture
        // synchronously via assumeIsolated — tests can assert on firedEvents
        // immediately after each call without waiting.
        events = EventMapping<PacketTunnelProvider.Event> { event, _, _, _ in
            MainActor.assumeIsolated {
                box.events.append(event)
            }
        }

        let recorder = RotateKeyRecorder()
        rotateKeyRecorder = recorder

        rotator = KeyRotator(
            keyStore: keyStore,
            settings: settings,
            events: events,
            rotateKey: { @MainActor in
                try await recorder.call()
            }
        )
    }

    override func tearDown() {
        rotator = nil
        rotateKeyRecorder = nil
        events = nil
        firedEvents = nil
        settings = nil
        keyStore = nil
        super.tearDown()
    }

    // MARK: - rekey() short-circuit

    func testRekey_whenRekeyingDisabled_firesNoEventsAndReturns() async throws {
        settings.disableRekeying = true

        try await rotator.rekey()

        XCTAssertEqual(firedEvents.events.count, 0)
        XCTAssertEqual(rotateKeyRecorder.callCount, 0)
    }

    // MARK: - rekey() success

    func testRekey_success_callsPerformRekey() async throws {
        try await rotator.rekey()

        XCTAssertEqual(rotateKeyRecorder.callCount, 1)
        assertEventSequence([.rekeyBegin, .rekeySuccess])
    }

    // MARK: - rekey() failure

    func testRekey_error_firesFailureAndRethrows() async {
        struct SomeError: Error {}
        rotateKeyRecorder.errorToThrow = SomeError()

        do {
            try await rotator.rekey()
            XCTFail("Expected error to be rethrown")
        } catch is SomeError {
            // expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        assertEventSequence([.rekeyBegin, .rekeyFailure])
    }

    // MARK: - resetRegistrationKey

    func testResetRegistrationKey_clearsKeyStorePair() {
        keyStore.keyPair = KeyPair(privateKey: PrivateKey(), expirationDate: Date())
        XCTAssertNotNil(keyStore.keyPair)

        rotator.resetRegistrationKey()

        XCTAssertNil(keyStore.keyPair)
    }

    // MARK: - Helpers

    /// Pattern match against the order of events fired during rekey. Use ExpectedEvent
    /// rather than raw Event values because RekeyAttemptStep wraps an Error in .failure,
    /// which has no Equatable conformance.
    private enum ExpectedEvent {
        case rekeyBegin
        case rekeySuccess
        case rekeyFailure
    }

    private func assertEventSequence(_ expected: [ExpectedEvent],
                                     file: StaticString = #filePath,
                                     line: UInt = #line) {
        let fired = firedEvents.events
        XCTAssertEqual(fired.count, expected.count,
                       "fired events: \(fired.map(String.init(describing:)))",
                       file: file, line: line)
        for (index, (firedEvent, want)) in zip(fired, expected).enumerated() {
            let matches: Bool
            switch (firedEvent, want) {
            case (.rekeyAttempt(.begin), .rekeyBegin),
                 (.rekeyAttempt(.success), .rekeySuccess),
                 (.rekeyAttempt(.failure), .rekeyFailure):
                matches = true
            default:
                matches = false
            }
            XCTAssertTrue(matches, "Event mismatch at index \(index): got \(firedEvent), expected \(want)", file: file, line: line)
        }
    }
}
