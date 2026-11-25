//
//  VPNStartupNotificationStoreTests.swift
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

#if os(macOS)
import NetworkExtension
import XCTest
@testable import VPN

final class VPNStartupNotificationStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "VPNStartupNotificationStoreTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    @MainActor
    func testMenuLaunchAcknowledgesOnlyAfterNotificationCenterAccepts() async throws {
        let profile = UUID().uuidString
        let store = VPNStartupNotificationStore(defaults: defaults)
        store.recordIfNeeded(profileIdentifier: profile)
        let incident = try XCTUnwrap(store.pending(profileIdentifier: profile))
        await incident.presentIfNeeded(in: defaults) { _ in false }
        do {
            try await incident.presentIfNeeded(in: defaults) { _ in throw URLError(.timedOut) }
            XCTFail("Expected the submission error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        }

        var accepted: [UUID] = []
        func submit(_ identifier: UUID) -> Bool {
            accepted.append(identifier)
            return true
        }
        await incident.presentIfNeeded(in: defaults, submit: submit)
        let nextLaunch = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        await incident.presentIfNeeded(in: nextLaunch, submit: submit)
        XCTAssertEqual(accepted, [incident.identifier])

        store.reset(profileIdentifier: profile)
        store.recordIfNeeded(profileIdentifier: profile)
        let nextFailure = try XCTUnwrap(store.pending(profileIdentifier: profile))
        await nextFailure.presentIfNeeded(in: nextLaunch, submit: submit)
        XCTAssertEqual(accepted, [incident.identifier, nextFailure.identifier])
    }

    @MainActor
    func testOldProfileReadsOnlyItsOwnMarkedErrorAndCoalescesRetries() async throws {
        let provider = "test.packet-tunnel"
        let failure = PacketTunnelProvider.TunnelError.reconnectBlocked
        let incident = VPNStartupNotificationIncident(profileIdentifier: provider, legacyProviderIdentifier: provider)
        let error = incident.attached(to: failure)
        let encoded = try NSKeyedArchiver.archivedData(withRootObject: error, requiringSecureCoding: true)
        let restored = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: NSError.self, from: encoded))
        XCTAssertEqual(VPNStartupNotificationIncident.fromDisconnectError(restored, provider: provider), incident)
        XCTAssertNil(VPNStartupNotificationIncident.fromDisconnectError(restored, provider: "other.packet-tunnel"))
        XCTAssertNil(VPNStartupNotificationIncident.fromDisconnectError(failure, provider: provider))
        XCTAssertNil(VPNStartupNotificationIncident.fromDisconnectError(incident.attached(to: URLError(.timedOut)), provider: provider))

        var submissions = 0
        await incident.presentIfNeeded(in: defaults) { _ in
            submissions += 1
            return true
        }
        let retry = VPNStartupNotificationIncident(profileIdentifier: provider, legacyProviderIdentifier: provider)
        await retry.presentIfNeeded(in: defaults) { _ in
            submissions += 1
            return true
        }
        let migrated = VPNStartupNotificationIncident(profileIdentifier: UUID().uuidString, legacyProviderIdentifier: provider)
        await migrated.presentIfNeeded(in: defaults) { _ in
            submissions += 1
            return true
        }
        XCTAssertEqual(submissions, 1)
    }

    func testIncidentSurvivesProviderStoreRecreationAndDoesNotRepeat() throws {
        VPNStartupNotificationStore(defaults: defaults).recordIfNeeded(profileIdentifier: "owner")
        let first = try XCTUnwrap(VPNStartupNotificationStore(defaults: defaults).pending(profileIdentifier: "owner"))
        let restoredDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let restoredStore = VPNStartupNotificationStore(defaults: restoredDefaults)
        XCTAssertEqual(restoredStore.pending(profileIdentifier: "owner"), first)
        restoredStore.recordIfNeeded(profileIdentifier: "owner")
        XCTAssertEqual(restoredStore.pending(profileIdentifier: "owner"), first)
        XCTAssertEqual(VPNStartupNotificationIncident(rawValue: first.rawValue), first)
    }

    func testOtherProfileCannotReadIncident() {
        let store = VPNStartupNotificationStore(defaults: defaults)
        store.recordIfNeeded(profileIdentifier: "owner")
        XCTAssertNil(store.pending(profileIdentifier: "other"))
    }

    func testMigrationRequiresOneMatchingConfiguration() throws {
        func manager(provider: String, identifier: String? = nil) -> NETunnelProviderManager {
            let manager = NETunnelProviderManager()
            let configuration = NETunnelProviderProtocol()
            configuration.providerBundleIdentifier = provider
            configuration.serverAddress = "127.0.0.1"
            if let identifier {
                configuration.providerConfiguration = [VPNStartupNotificationIncident.profileIdentifierKey: identifier]
            }
            manager.protocolConfiguration = configuration
            return manager
        }
        let old = manager(provider: "test.tunnel")
        let current = try XCTUnwrap(old.protocolConfiguration as? NETunnelProviderProtocol)
        let proxy = manager(provider: "test.proxy")
        XCTAssertTrue(current.notificationProfile(in: [proxy, old], identifier: nil) === old)
        XCTAssertNil(current.notificationProfile(in: [old, manager(provider: "test.tunnel")], identifier: nil))
        let identifier = UUID().uuidString
        let tagged = manager(provider: "test.tunnel", identifier: identifier)
        XCTAssertTrue(current.notificationProfile(in: [old, tagged], identifier: identifier) === tagged)
        XCTAssertNil(current.notificationProfile(in: [old, proxy], identifier: identifier))
    }

    func testIntentionalSignOutDoesNotCreateOrReplayIncident() {
        let store = VPNStartupNotificationStore(defaults: defaults)
        defaults.suppressEntitlementMessaging = true
        store.recordIfNeeded(profileIdentifier: "owner")
        XCTAssertNil(store.pending(profileIdentifier: "owner"))
        defaults.suppressEntitlementMessaging = false
        store.recordIfNeeded(profileIdentifier: "owner")
        defaults.suppressEntitlementMessaging = true
        XCTAssertNil(store.pending(profileIdentifier: "owner"))
        defaults.suppressEntitlementMessaging = false
        XCTAssertNil(store.pending(profileIdentifier: "owner"))
    }

    func testConsumedSubscriptionExpiryNotificationDoesNotPreventStartupIncident() {
        defaults.showEntitlementNotification = false
        let store = VPNStartupNotificationStore(defaults: defaults)
        store.recordIfNeeded(profileIdentifier: "owner")
        XCTAssertNotNil(store.pending(profileIdentifier: "owner"))
        store.recordIfNeeded(profileIdentifier: "other")
        XCTAssertNotNil(store.pending(profileIdentifier: "other"))
        XCTAssertFalse(defaults.showEntitlementNotification)
    }

    func testStartupIncidentDoesNotConsumeSubscriptionExpiryNotification() {
        defaults.enableEntitlementMessaging()
        VPNStartupNotificationStore(defaults: defaults).recordIfNeeded(profileIdentifier: "owner")
        XCTAssertTrue(defaults.showEntitlementNotification)
    }

    func testSuccessfulConnectionResetsOnlyItsProfileAndAllowsNewIncident() throws {
        let store = VPNStartupNotificationStore(defaults: defaults)
        store.recordIfNeeded(profileIdentifier: "owner")
        store.recordIfNeeded(profileIdentifier: "other")
        let first = try XCTUnwrap(store.pending(profileIdentifier: "owner"))
        let other = try XCTUnwrap(store.pending(profileIdentifier: "other"))
        store.reset(profileIdentifier: "owner")
        XCTAssertNil(store.pending(profileIdentifier: "owner"))
        XCTAssertEqual(store.pending(profileIdentifier: "other"), other)
        store.recordIfNeeded(profileIdentifier: "owner")
        XCTAssertNotEqual(store.pending(profileIdentifier: "owner")?.identifier, first.identifier)
    }

    func testResetHidesOldIncidentAndAllowsNewIncident() throws {
        let store = VPNStartupNotificationStore(defaults: defaults)
        store.recordIfNeeded(profileIdentifier: "owner")
        let old = try XCTUnwrap(store.pending(profileIdentifier: "owner"))
        defaults.resetEntitlementMessaging()
        XCTAssertNil(store.pending(profileIdentifier: "owner"))
        store.recordIfNeeded(profileIdentifier: "owner")
        XCTAssertNotEqual(store.pending(profileIdentifier: "owner")?.identifier, old.identifier)
    }

    func testResetThenSubscriptionExpiryDoesNotReplayOldStartupIncident() {
        let store = VPNStartupNotificationStore(defaults: defaults)
        store.recordIfNeeded(profileIdentifier: "owner")
        defaults.resetEntitlementMessaging()
        defaults.enableEntitlementMessaging()
        defaults.showEntitlementNotification = false
        XCTAssertNil(store.pending(profileIdentifier: "owner"))
    }
}
#endif
