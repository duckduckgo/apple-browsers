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

// MARK: - Test Doubles

// Tests must hold strong references to these mocks: the rotator stores them
// as weak protocol refs to match the production wiring pattern.

@MainActor
private final class MockTunnelEgressProvider: TunnelEgressProviding {
    var egressInfo: LeakCheckEgressInfo?

    func currentEgressInfo() -> LeakCheckEgressInfo? {
        egressInfo
    }
}

@MainActor
private final class MockTunnelReconfigurer: TunnelReconfiguring {
    var updateCallCount = 0
    var lastUpdateMethod: PacketTunnelProvider.TunnelUpdateMethod?
    var lastReassert: Bool?
    var lastRegenerateKey: Bool?
    var errorToThrow: Error?

    /// Called inside updateTunnelConfiguration before it returns/throws, so tests can mutate
    /// the egress mock to simulate the egress path changing across the rekey boundary.
    var onUpdate: (@MainActor () -> Void)?

    func updateTunnelConfiguration(updateMethod: PacketTunnelProvider.TunnelUpdateMethod,
                                   reassert: Bool,
                                   regenerateKey: Bool) async throws {
        updateCallCount += 1
        lastUpdateMethod = updateMethod
        lastReassert = reassert
        lastRegenerateKey = regenerateKey
        onUpdate?()
        if let errorToThrow {
            throw errorToThrow
        }
    }
}

/// Reference holder for fired events. EventMapping's closure is @Sendable, so we
/// can't directly capture `self` (XCTestCase isn't Sendable). The box is only ever
/// written/read from MainActor via assumeIsolated, so @unchecked is safe.
private final class FiredEventsBox: @unchecked Sendable {
    var events: [PacketTunnelProvider.Event] = []
}

// MARK: - Tests

@MainActor
final class KeyRotatorTests: XCTestCase {

    private var keyStore: NetworkProtectionKeyStoreMock!
    private var settings: VPNSettings!
    private var firedEvents: FiredEventsBox!
    private var events: EventMapping<PacketTunnelProvider.Event>!
    private var tunnelState: MockTunnelStateProvider!
    private var tunnelLifecycle: MockTunnelLifecycleManager!
    private var tunnelEgress: MockTunnelEgressProvider!
    private var tunnelReconfigurer: MockTunnelReconfigurer!
    private var leakCheckScheduledCount: Int!
    private var rotator: KeyRotator!

    override func setUp() {
        super.setUp()

        keyStore = NetworkProtectionKeyStoreMock()
        settings = VPNSettings(defaults: .standard)
        settings.disableRekeying = false

        let box = FiredEventsBox()
        firedEvents = box
        events = EventMapping<PacketTunnelProvider.Event> { event, _, _, _ in
            MainActor.assumeIsolated {
                box.events.append(event)
            }
        }

        tunnelState = MockTunnelStateProvider()
        tunnelLifecycle = MockTunnelLifecycleManager()
        tunnelEgress = MockTunnelEgressProvider()
        tunnelReconfigurer = MockTunnelReconfigurer()
        leakCheckScheduledCount = 0

        rotator = KeyRotator(
            keyStore: keyStore,
            settings: settings,
            events: events,
            tunnelState: tunnelState,
            tunnelLifecycle: tunnelLifecycle,
            tunnelEgress: tunnelEgress,
            tunnelReconfigurer: tunnelReconfigurer,
            scheduleLeakCheckAfterRekey: { [weak self] in
                self?.leakCheckScheduledCount += 1
            }
        )
    }

    override func tearDown() {
        rotator = nil
        leakCheckScheduledCount = nil
        tunnelReconfigurer = nil
        tunnelEgress = nil
        tunnelLifecycle = nil
        tunnelState = nil
        events = nil
        firedEvents = nil
        settings = nil
        keyStore = nil
        super.tearDown()
    }

    // MARK: - shouldScheduleLeakCheck (pure)

    func testShouldScheduleLeakCheck_returnsFalseWhenPostEgressIsNil() {
        let pre = LeakCheckEgressInfo(ipAddress: "1.2.3.4", name: "us-east")
        XCTAssertFalse(KeyRotator.shouldScheduleLeakCheck(preRekeyEgress: pre, postRekeyEgress: nil))
    }

    func testShouldScheduleLeakCheck_returnsFalseWhenPreAndPostAreEqual() {
        let info = LeakCheckEgressInfo(ipAddress: "1.2.3.4", name: "us-east")
        XCTAssertFalse(KeyRotator.shouldScheduleLeakCheck(preRekeyEgress: info, postRekeyEgress: info))
    }

    func testShouldScheduleLeakCheck_returnsTrueWhenEgressChanged() {
        let pre = LeakCheckEgressInfo(ipAddress: "1.2.3.4", name: "us-east")
        let post = LeakCheckEgressInfo(ipAddress: "5.6.7.8", name: "eu-west")
        XCTAssertTrue(KeyRotator.shouldScheduleLeakCheck(preRekeyEgress: pre, postRekeyEgress: post))
    }

    // MARK: - rekey() short-circuit

    func testRekey_whenRekeyingDisabled_firesOnlyUserBecameActiveAndReturns() async throws {
        settings.disableRekeying = true

        try await rotator.rekey()

        XCTAssertEqual(firedEvents.events.count, 1)
        guard case .userBecameActive = firedEvents.events[0] else {
            XCTFail("Expected .userBecameActive, got \(firedEvents.events[0])")
            return
        }
        XCTAssertEqual(tunnelReconfigurer.updateCallCount, 0)
        XCTAssertEqual(leakCheckScheduledCount, 0)
    }

    // MARK: - rekey() success

    func testRekey_success_doesNotScheduleLeakCheckWhenEgressUnchanged() async throws {
        let info = LeakCheckEgressInfo(ipAddress: "1.2.3.4", name: "us-east")
        tunnelEgress.egressInfo = info

        try await rotator.rekey()

        XCTAssertEqual(tunnelReconfigurer.updateCallCount, 1)
        XCTAssertEqual(tunnelReconfigurer.lastReassert, false)
        XCTAssertEqual(tunnelReconfigurer.lastRegenerateKey, true)
        XCTAssertEqual(leakCheckScheduledCount, 0)
        assertEventSequence([.userBecameActive, .rekeyBegin, .rekeySuccess])
    }

    func testRekey_success_schedulesLeakCheckWhenEgressChanged() async throws {
        tunnelEgress.egressInfo = LeakCheckEgressInfo(ipAddress: "1.2.3.4", name: "us-east")
        tunnelReconfigurer.onUpdate = { [weak self] in
            self?.tunnelEgress.egressInfo = LeakCheckEgressInfo(ipAddress: "5.6.7.8", name: "eu-west")
        }

        try await rotator.rekey()

        XCTAssertEqual(tunnelReconfigurer.updateCallCount, 1)
        XCTAssertEqual(leakCheckScheduledCount, 1)
        assertEventSequence([.userBecameActive, .rekeyBegin, .rekeySuccess])
    }

    // MARK: - rekey() failure

    func testRekey_genericError_firesFailureAndRethrows_doesNotHandleAccessRevoked() async {
        struct SomeError: Error {}
        tunnelReconfigurer.errorToThrow = SomeError()

        do {
            try await rotator.rekey()
            XCTFail("Expected error to be rethrown")
        } catch is SomeError {
            // expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertFalse(tunnelLifecycle.handleAccessRevokedCalled)
        XCTAssertEqual(leakCheckScheduledCount, 0)
        assertEventSequence([.userBecameActive, .rekeyBegin, .rekeyFailure])
    }

    func testRekey_vpnAccessRevoked_firesFailureCallsHandleAccessRevokedAndRethrows() async {
        struct Underlying: Error {}
        let revoked = PacketTunnelProvider.TunnelError.vpnAccessRevoked(Underlying())
        tunnelReconfigurer.errorToThrow = revoked

        do {
            try await rotator.rekey()
            XCTFail("Expected error to be rethrown")
        } catch PacketTunnelProvider.TunnelError.vpnAccessRevoked {
            // expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertTrue(tunnelLifecycle.handleAccessRevokedCalled)
        if let captured = tunnelLifecycle.handleAccessRevokedError,
           case PacketTunnelProvider.TunnelError.vpnAccessRevoked = captured {
            // expected — the same error is forwarded
        } else {
            XCTFail("Expected handleAccessRevoked called with vpnAccessRevoked, got \(String(describing: tunnelLifecycle.handleAccessRevokedError))")
        }
        XCTAssertEqual(leakCheckScheduledCount, 0)
        assertEventSequence([.userBecameActive, .rekeyBegin, .rekeyFailure])
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
        case userBecameActive
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
            case (.userBecameActive, .userBecameActive),
                 (.rekeyAttempt(.begin), .rekeyBegin),
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
