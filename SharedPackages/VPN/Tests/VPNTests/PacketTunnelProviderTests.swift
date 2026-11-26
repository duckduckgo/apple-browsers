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

    private var startupDefaults: UserDefaults!
    private var startupDefaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        startupDefaultsSuiteName = "PacketTunnelProviderTests.\(UUID().uuidString)"
        startupDefaults = UserDefaults(suiteName: startupDefaultsSuiteName)
    }

    override func tearDown() {
        startupDefaults.removePersistentDomain(forName: startupDefaultsSuiteName)
        startupDefaults = nil
        startupDefaultsSuiteName = nil
        super.tearDown()
    }

    func testStartupIsAllowedByDefaultForEveryStartupMethod() {
        let startupGuard = VPNStartupGuard(defaults: startupDefaults)

        XCTAssertEqual(startupGuard.prepareForStartup(startupMethod: .automaticOnDemand), .allowed)
        XCTAssertEqual(startupGuard.prepareForStartup(startupMethod: .manualByTheSystem), .allowed)
        XCTAssertEqual(startupGuard.prepareForStartup(startupMethod: .manualByMainApp), .allowed)
    }

    func testBlockedStartupPersistsAcrossGuardAndDefaultsInstances() throws {
        VPNStartupGuard(defaults: startupDefaults).blockStartup()
        let restartedDefaults = try XCTUnwrap(UserDefaults(suiteName: startupDefaultsSuiteName))
        let restartedGuard = VPNStartupGuard(defaults: restartedDefaults)

        XCTAssertEqual(restartedGuard.prepareForStartup(startupMethod: .automaticOnDemand), .blocked)
    }

    func testSystemStartupClearsBlockAcrossGuardAndDefaultsInstances() throws {
        let startupGuard = VPNStartupGuard(defaults: startupDefaults)
        startupGuard.blockStartup()

        XCTAssertEqual(startupGuard.prepareForStartup(startupMethod: .manualByTheSystem), .allowed)

        let restartedDefaults = try XCTUnwrap(UserDefaults(suiteName: startupDefaultsSuiteName))
        let restartedGuard = VPNStartupGuard(defaults: restartedDefaults)
        XCTAssertEqual(restartedGuard.prepareForStartup(startupMethod: .automaticOnDemand), .allowed)
    }

    func testMainAppStartupClearsBlockAcrossGuardAndDefaultsInstances() throws {
        let startupGuard = VPNStartupGuard(defaults: startupDefaults)
        startupGuard.blockStartup()

        XCTAssertEqual(startupGuard.prepareForStartup(startupMethod: .manualByMainApp), .allowed)

        let restartedDefaults = try XCTUnwrap(UserDefaults(suiteName: startupDefaultsSuiteName))
        let restartedGuard = VPNStartupGuard(defaults: restartedDefaults)
        XCTAssertEqual(restartedGuard.prepareForStartup(startupMethod: .automaticOnDemand), .allowed)
        XCTAssertEqual(restartedGuard.prepareForStartup(startupMethod: .manualByTheSystem), .allowed)
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

    // MARK: - Auth notifications

    func testWhenTheTunnelStartsWithoutATokenThenTheSignedOutNotificationIsShown() {
        let presenter = RecordingNotificationsPresenter()

        PacketTunnelProvider.AuthNotification.signedOut.present(with: presenter)

        XCTAssertEqual(presenter.shown, [.signedOut])
    }

    func testWhenTheSubscriptionExpiredThenTheEntitlementNotificationIsShown() {
        let presenter = RecordingNotificationsPresenter()

        PacketTunnelProvider.AuthNotification.subscriptionExpired.present(with: presenter)

        XCTAssertEqual(presenter.shown, [.entitlement])
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

    // MARK: - Subscription environment before the token

    private func makeStartupOptions(environment: VPNSettings.SelectedEnvironment) throws -> StartupOptions {
        let snapshot = VPNSettingsSnapshot(registrationKeyValidity: .automatic,
                                           selectedEnvironment: environment,
                                           selectedServer: .automatic,
                                           selectedLocation: .nearest,
                                           dnsSettings: .ddg(blockRiskyDomains: true),
                                           excludeLocalNetworks: false)
        return StartupOptions(options: [NetworkProtectionOptionKey.settings: try JSONEncoder().encode(snapshot)])
    }

    private func makeSettings(environment: VPNSettings.SelectedEnvironment) -> VPNSettings {
        let settings = VPNSettings(defaults: startupDefaults)
        settings.selectedEnvironment = environment
        return settings
    }

    func testWhenTheAppSendsAnotherEnvironmentThenItIsLoaded() throws {
        let settings = makeSettings(environment: .staging)

        let changed = PacketTunnelProvider.loadSubscriptionEnvironment(from: try makeStartupOptions(environment: .production), into: settings)

        XCTAssertTrue(changed)
        XCTAssertEqual(settings.selectedEnvironment, .production)
    }

    func testWhenTheAppSendsTheSameEnvironmentThenNothingChanges() throws {
        let settings = makeSettings(environment: .production)

        let changed = PacketTunnelProvider.loadSubscriptionEnvironment(from: try makeStartupOptions(environment: .production), into: settings)

        XCTAssertFalse(changed)
        XCTAssertEqual(settings.selectedEnvironment, .production)
    }

    func testWhenTheTunnelStartsWithoutSettingsThenTheStoredEnvironmentIsKept() {
        let settings = makeSettings(environment: .staging)

        let changed = PacketTunnelProvider.loadSubscriptionEnvironment(from: StartupOptions(options: [:]), into: settings)

        XCTAssertFalse(changed)
        XCTAssertEqual(settings.selectedEnvironment, .staging)
    }

    func testWhenTheSentSettingsCannotBeDecodedThenTheStoredEnvironmentIsKept() {
        let settings = makeSettings(environment: .staging)
        let options = StartupOptions(options: [NetworkProtectionOptionKey.settings: Data("not json".utf8)])

        let changed = PacketTunnelProvider.loadSubscriptionEnvironment(from: options, into: settings)

        XCTAssertFalse(changed)
        XCTAssertEqual(settings.selectedEnvironment, .staging)
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

private final class RecordingNotificationsPresenter: VPNNotificationsPresenting {
    enum Notification: Equatable {
        case entitlement
        case signedOut
    }

    private(set) var shown: [Notification] = []

    func showConnectedNotification(serverLocation: String?, snoozeEnded: Bool) {}
    func showStrictRoutingReminderNotification() {}
    func showReconnectingNotification() {}
    func showConnectionFailureNotification() {}
    func showSnoozingNotification(duration: TimeInterval) {}
    func showSupersededNotification() {}
    func showTestNotification() {}
    func showEntitlementNotification() { shown.append(.entitlement) }
    func showDebugEventNotification(message: String) {}
    func showSignedOutNotification() { shown.append(.signedOut) }
}
