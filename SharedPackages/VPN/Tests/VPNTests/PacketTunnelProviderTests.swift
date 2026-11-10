//
//  PacketTunnelProviderTests.swift
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
import NetworkExtension
import XCTest
@_spi(Testing) import PixelKit
@testable import VPN

final class PacketTunnelProviderTests: XCTestCase {

    typealias TunnelError = PacketTunnelProvider.TunnelError

    private var reconnectDefaults: UserDefaults!
    private var reconnectDefaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        reconnectDefaultsSuiteName = "PacketTunnelProviderTests.\(UUID().uuidString)"
        reconnectDefaults = UserDefaults(suiteName: reconnectDefaultsSuiteName)
    }

    override func tearDown() {
        reconnectDefaults.removePersistentDomain(forName: reconnectDefaultsSuiteName)
        reconnectDefaults = nil
        reconnectDefaultsSuiteName = nil
        super.tearDown()
    }

    func testReconnectIsAllowedByDefaultForEveryStartupMethod() {
        let reconnectGuard = ReconnectGuard(defaults: reconnectDefaults)

        XCTAssertNoThrow(try reconnectGuard.runStartValidation(startupMethod: .automaticOnDemand))
        XCTAssertNoThrow(try reconnectGuard.runStartValidation(startupMethod: .manualByTheSystem))
        XCTAssertNoThrow(try reconnectGuard.runStartValidation(startupMethod: .manualByMainApp))
    }

    func testBlockedReconnectPersistsAcrossGuardAndDefaultsInstances() throws {
        ReconnectGuard(defaults: reconnectDefaults).blockAutomaticReconnect()
        let restartedDefaults = try XCTUnwrap(UserDefaults(suiteName: reconnectDefaultsSuiteName))
        let restartedGuard = ReconnectGuard(defaults: restartedDefaults)

        XCTAssertThrowsError(try restartedGuard.runStartValidation(startupMethod: .automaticOnDemand)) { error in
            XCTAssertEqual((error as? TunnelError)?.code, .reconnectBlocked)
        }
    }

    func testBlockedReconnectRejectsSystemStartsWithoutMainAppOptions() {
        let reconnectGuard = ReconnectGuard(defaults: reconnectDefaults)
        reconnectGuard.blockAutomaticReconnect()
        let options = StartupOptions(options: [:])

        XCTAssertThrowsError(try reconnectGuard.runStartValidation(startupMethod: options.startupMethod)) { error in
            XCTAssertEqual((error as? TunnelError)?.code, .reconnectBlocked)
        }
        XCTAssertThrowsError(try reconnectGuard.runStartValidation(startupMethod: .automaticOnDemand))
    }

    func testManualAppValidationImmediatelyAllowsSubsequentAutomaticReconnect() {
        let reconnectGuard = ReconnectGuard(defaults: reconnectDefaults)
        reconnectGuard.blockAutomaticReconnect()

        XCTAssertNoThrow(try reconnectGuard.runStartValidation(startupMethod: .manualByMainApp))
        let subsequentGuard = ReconnectGuard(defaults: reconnectDefaults)
        XCTAssertNoThrow(try subsequentGuard.runStartValidation(startupMethod: .automaticOnDemand))
        XCTAssertNoThrow(try subsequentGuard.runStartValidation(startupMethod: .manualByTheSystem))
    }

    func testOtherStartSourcesCannotClearTheReconnectGuard() {
        let reconnectGuard = ReconnectGuard(defaults: reconnectDefaults)
        reconnectGuard.blockAutomaticReconnect()

        XCTAssertThrowsError(try reconnectGuard.runStartValidation(startupMethod: .manualByTheSystem))
        XCTAssertThrowsError(try reconnectGuard.runStartValidation(startupMethod: .automaticOnDemand))
    }

    func testReconnectBlockedErrorHasItsOwnCodeForProcessBoundaries() {
        let error = TunnelError.reconnectBlocked as NSError

        XCTAssertEqual(error.domain, TunnelError.errorDomain)
        XCTAssertEqual(TunnelError.Code(rawValue: error.code), .reconnectBlocked)
        XCTAssertEqual(error.localizedDescription, TunnelError.reconnectBlocked.errorDescription)
    }

    func testPostWakeCounterReportsOnlyTheThirdFailure() {
        let date = Date()
        var counter = PacketTunnelProvider.PostWakeConnectivityFailures(wakeDate: date)
        XCTAssertFalse(counter.record(isConnected: false, localIsConnected: true, startedAt: date))
        XCTAssertFalse(counter.record(isConnected: false, localIsConnected: true, startedAt: date))
        XCTAssertTrue(counter.record(isConnected: false, localIsConnected: true, startedAt: date))
        XCTAssertFalse(counter.record(isConnected: false, localIsConnected: true, startedAt: date))
    }

    func testPostWakeCounterIgnoresChecksWhereBothConnectionsFail() {
        let date = Date()
        var counter = PacketTunnelProvider.PostWakeConnectivityFailures(wakeDate: date)
        for _ in 0..<3 {
            XCTAssertFalse(counter.record(isConnected: false, localIsConnected: false, startedAt: date))
        }
        XCTAssertFalse(counter.record(isConnected: false, localIsConnected: true, startedAt: date))
        XCTAssertFalse(counter.record(isConnected: false, localIsConnected: true, startedAt: date))
        for _ in 0..<3 {
            XCTAssertFalse(counter.record(isConnected: false, localIsConnected: false, startedAt: date))
        }
        XCTAssertTrue(counter.record(isConnected: false, localIsConnected: true, startedAt: date))
    }

    func testPostWakeCounterStopsOnSuccess() {
        let date = Date()
        var counter = PacketTunnelProvider.PostWakeConnectivityFailures(wakeDate: date)
        XCTAssertFalse(counter.record(isConnected: false, localIsConnected: true, startedAt: date))
        XCTAssertFalse(counter.record(isConnected: false, localIsConnected: true, startedAt: date))
        XCTAssertFalse(counter.record(isConnected: true, localIsConnected: true, startedAt: date))
        for _ in 0..<3 { XCTAssertFalse(counter.record(isConnected: false, localIsConnected: true, startedAt: date)) }
    }

    func testPostWakeCounterStopsOnVPNSuccessEvenWhenLocalConnectionFails() {
        let date = Date()
        var counter = PacketTunnelProvider.PostWakeConnectivityFailures(wakeDate: date)
        XCTAssertFalse(counter.record(isConnected: false, localIsConnected: true, startedAt: date))
        XCTAssertFalse(counter.record(isConnected: false, localIsConnected: true, startedAt: date))
        XCTAssertFalse(counter.record(isConnected: true, localIsConnected: false, startedAt: date))
        for _ in 0..<3 { XCTAssertFalse(counter.record(isConnected: false, localIsConnected: true, startedAt: date)) }
    }

    func testChecksStartedBeforeWakeDoNotAffectTheCounter() {
        let date = Date()
        var counter = PacketTunnelProvider.PostWakeConnectivityFailures(wakeDate: date)
        let earlier = date.addingTimeInterval(-1)
        XCTAssertFalse(counter.record(isConnected: true, localIsConnected: true, startedAt: earlier))
        for _ in 0..<3 { XCTAssertFalse(counter.record(isConnected: false, localIsConnected: true, startedAt: earlier)) }
        XCTAssertFalse(counter.record(isConnected: false, localIsConnected: true, startedAt: date))
        XCTAssertFalse(counter.record(isConnected: false, localIsConnected: true, startedAt: date))
        XCTAssertTrue(counter.record(isConnected: false, localIsConnected: true, startedAt: date))
    }

    func testFreshWakeCounterStartsAtZero() {
        let date = Date()
        var counter = PacketTunnelProvider.PostWakeConnectivityFailures(wakeDate: date)
        XCTAssertFalse(counter.record(isConnected: false, localIsConnected: true, startedAt: date))
        counter = PacketTunnelProvider.PostWakeConnectivityFailures(wakeDate: date.addingTimeInterval(60))
        let later = date.addingTimeInterval(61)
        XCTAssertFalse(counter.record(isConnected: false, localIsConnected: true, startedAt: later))
        XCTAssertFalse(counter.record(isConnected: false, localIsConnected: true, startedAt: later))
        XCTAssertTrue(counter.record(isConnected: false, localIsConnected: true, startedAt: later))
    }

    func testPostWakePixelUsesPersistentRetry() {
        let recorder = RetryRecordingPixelFiring()
        VPNWakeConnectivityPixel.fireFailure(using: recorder)
        XCTAssertEqual(recorder.mock.actualFireCalls, [ExpectedFireCall(pixel: VPNWakeConnectivityPixel.failure, frequency: .dailyAndCount)])
        XCTAssertTrue(recorder.retryOnFailure)
    }

    /// Tests that `TunnelError` has the expected underlying error information.
    ///
    func testThatTunnelErrorHasTheExpectedUnderlyingErrorInformation() {
        let underlyingError = NSError(domain: "test", code: 1)

        XCTAssertEqual(TunnelError.startingTunnelWithoutAuthToken(internalError: underlyingError).errorUserInfo[NSUnderlyingErrorKey] as? NSError, underlyingError)
        XCTAssertEqual(TunnelError.simulateTunnelFailureError.errorUserInfo[NSUnderlyingErrorKey] as? NSError, nil)
        XCTAssertEqual(TunnelError.vpnAccessRevoked(underlyingError).errorUserInfo[NSUnderlyingErrorKey] as? NSError, underlyingError)

        XCTAssertEqual(TunnelError.couldNotGenerateTunnelConfiguration(internalError: underlyingError).errorUserInfo[NSUnderlyingErrorKey] as? NSError, underlyingError)
    }

    func testWhenInterfaceNameHasUtunPrefixThenItIsConsideredTunnelInterface() {
        XCTAssertTrue(NEPacketTunnelProvider.isTunnelInterfaceName("utun0"))
        XCTAssertTrue(NEPacketTunnelProvider.isTunnelInterfaceName("utun42"))
    }

    func testWhenInterfaceNameDoesNotHaveUtunPrefixThenItIsNotConsideredTunnelInterface() {
        XCTAssertFalse(NEPacketTunnelProvider.isTunnelInterfaceName("en0"))
        XCTAssertFalse(NEPacketTunnelProvider.isTunnelInterfaceName("lo0"))
        XCTAssertFalse(NEPacketTunnelProvider.isTunnelInterfaceName("ipsec0"))
    }

    func testConnectionAttemptSourcePreservesFailureRecoveryOnlyForFailureRecoveryReassertUpdate() {
        XCTAssertTrue(PacketTunnelProvider.ConnectionAttemptSource.failureRecovery.preservesFailureRecoveryDuringReassertUpdate)

        let supersedingSources: [PacketTunnelProvider.ConnectionAttemptSource] = [
            .start,
            .rekey,
            .serverChange,
            .locationChange,
            .adapterRestart,
            .serverMigration
        ]
        XCTAssertTrue(supersedingSources.allSatisfy { !$0.preservesFailureRecoveryDuringReassertUpdate })
    }
}

private final class RetryRecordingPixelFiring: PixelKitFiring {
    let mock = PixelKitMock()
    private(set) var retryOnFailure = false

    func fire(event: PixelKit.Event, frequency: PixelKit.Frequency, options: PixelKit.Options, onComplete: @escaping PixelKit.CompletionBlock) {
        retryOnFailure = options.retryOnFailure
        mock.fire(event: event, frequency: frequency, options: options, onComplete: onComplete)
    }
}
