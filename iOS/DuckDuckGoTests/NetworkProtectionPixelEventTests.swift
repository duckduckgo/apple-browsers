//
//  NetworkProtectionPixelEventTests.swift
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
import PixelKit
@testable import Core

/// Wire-name parity oracle for the iOS VPN tunnel pixel migration.
///
/// For every pixel the tunnel fires, this asserts that the native `NetworkProtectionPixelEvent`
/// definition emits exactly the same wire name the legacy `Pixel.Event` emits today. It compares the
/// two enums at runtime — no hand-typed expected strings — so the native definitions cannot drift
/// from the shipping names, and the follow-up that migrates the call sites can rely on this parity.
final class NetworkProtectionPixelEventTests: XCTestCase {

    func testNativeNamesMatchLegacyWireNames() {
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionActiveUser, Pixel.Event.networkProtectionActiveUser)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionAdapterEndTemporaryShutdownStateAttemptFailure, Pixel.Event.networkProtectionAdapterEndTemporaryShutdownStateAttemptFailure)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionAdapterEndTemporaryShutdownStateRecoveryFailure, Pixel.Event.networkProtectionAdapterEndTemporaryShutdownStateRecoveryFailure)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionAdapterEndTemporaryShutdownStateRecoverySuccess, Pixel.Event.networkProtectionAdapterEndTemporaryShutdownStateRecoverySuccess)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionClientFailedToEncodeRegisterKeyRequest, Pixel.Event.networkProtectionClientFailedToEncodeRegisterKeyRequest)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionClientFailedToFetchRegisteredServers, Pixel.Event.networkProtectionClientFailedToFetchRegisteredServers)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionClientFailedToFetchServerList, Pixel.Event.networkProtectionClientFailedToFetchServerList)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionClientFailedToFetchServerStatus, Pixel.Event.networkProtectionClientFailedToFetchServerStatus)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionClientFailedToParseRegisteredServersResponse, Pixel.Event.networkProtectionClientFailedToParseRegisteredServersResponse)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionClientFailedToParseServerListResponse, Pixel.Event.networkProtectionClientFailedToParseServerListResponse)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionClientFailedToParseServerStatusResponse, Pixel.Event.networkProtectionClientFailedToParseServerStatusResponse)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionClientInvalidAuthToken, Pixel.Event.networkProtectionClientInvalidAuthToken)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionConnectionFailureLoopDetected, Pixel.Event.networkProtectionConnectionFailureLoopDetected)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionConnectionTesterExtendedFailureDetected, Pixel.Event.networkProtectionConnectionTesterExtendedFailureDetected)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionConnectionTesterExtendedFailureRecovered, Pixel.Event.networkProtectionConnectionTesterExtendedFailureRecovered(failureCount: 0))
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionConnectionTesterFailureDetected, Pixel.Event.networkProtectionConnectionTesterFailureDetected)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionConnectionTesterFailureRecovered, Pixel.Event.networkProtectionConnectionTesterFailureRecovered(failureCount: 0))
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionDisconnected, Pixel.Event.networkProtectionDisconnected)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionEnableAttemptConnecting, Pixel.Event.networkProtectionEnableAttemptConnecting)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionEnableAttemptFailure, Pixel.Event.networkProtectionEnableAttemptFailure)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionEnableAttemptSuccess, Pixel.Event.networkProtectionEnableAttemptSuccess)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionFailureRecoveryCompletedHealthy, Pixel.Event.networkProtectionFailureRecoveryCompletedHealthy)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionFailureRecoveryCompletedUnhealthy, Pixel.Event.networkProtectionFailureRecoveryCompletedUnhealthy)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionFailureRecoveryFailed, Pixel.Event.networkProtectionFailureRecoveryFailed)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionFailureRecoveryStarted, Pixel.Event.networkProtectionFailureRecoveryStarted)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionKeychainDeleteError, Pixel.Event.networkProtectionKeychainDeleteError)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionKeychainErrorFailedToCastKeychainValueToData, Pixel.Event.networkProtectionKeychainErrorFailedToCastKeychainValueToData)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionKeychainReadError, Pixel.Event.networkProtectionKeychainReadError)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionKeychainUpdateError, Pixel.Event.networkProtectionKeychainUpdateError)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionKeychainWriteError, Pixel.Event.networkProtectionKeychainWriteError)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionLatency(quality: "excellent"), Pixel.Event.networkProtectionLatency(quality: "excellent"))
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionLatencyError, Pixel.Event.networkProtectionLatencyError)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionMemoryCritical, Pixel.Event.networkProtectionMemoryCritical)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionMemoryWarning, Pixel.Event.networkProtectionMemoryWarning)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionNoAccessTokenFoundError, Pixel.Event.networkProtectionNoAccessTokenFoundError)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionPixelStorageSetupFailure, Pixel.Event.networkProtectionPixelStorageSetupFailure)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionRekeyAttempt, Pixel.Event.networkProtectionRekeyAttempt)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionRekeyCompleted, Pixel.Event.networkProtectionRekeyCompleted)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionRekeyFailure, Pixel.Event.networkProtectionRekeyFailure)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionServerMigrationAttempt, Pixel.Event.networkProtectionServerMigrationAttempt)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionServerMigrationAttemptFailure, Pixel.Event.networkProtectionServerMigrationAttemptFailure)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionServerMigrationAttemptSuccess, Pixel.Event.networkProtectionServerMigrationAttemptSuccess)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionTunnelConfigurationCouldNotGetInterfaceAddressRange, Pixel.Event.networkProtectionTunnelConfigurationCouldNotGetInterfaceAddressRange)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionTunnelConfigurationCouldNotGetPeerHostName, Pixel.Event.networkProtectionTunnelConfigurationCouldNotGetPeerHostName)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionTunnelConfigurationCouldNotGetPeerPublicKey, Pixel.Event.networkProtectionTunnelConfigurationCouldNotGetPeerPublicKey)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionTunnelConfigurationCouldNotSelectClosestServer, Pixel.Event.networkProtectionTunnelConfigurationCouldNotSelectClosestServer)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionTunnelConfigurationNoServerRegistrationInfo, Pixel.Event.networkProtectionTunnelConfigurationNoServerRegistrationInfo)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionTunnelFailureDetected, Pixel.Event.networkProtectionTunnelFailureDetected)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionTunnelFailureRecovered, Pixel.Event.networkProtectionTunnelFailureRecovered)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionTunnelStartAttempt, Pixel.Event.networkProtectionTunnelStartAttempt)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionTunnelStartAttemptOnDemandWithoutAccessToken, Pixel.Event.networkProtectionTunnelStartAttemptOnDemandWithoutAccessToken)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionTunnelStartFailure, Pixel.Event.networkProtectionTunnelStartFailure)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionTunnelStartSuccess, Pixel.Event.networkProtectionTunnelStartSuccess)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionTunnelStopAttempt, Pixel.Event.networkProtectionTunnelStopAttempt)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionTunnelStopFailure, Pixel.Event.networkProtectionTunnelStopFailure)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionTunnelStopSuccess, Pixel.Event.networkProtectionTunnelStopSuccess)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionTunnelUpdateAttempt, Pixel.Event.networkProtectionTunnelUpdateAttempt)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionTunnelUpdateFailure, Pixel.Event.networkProtectionTunnelUpdateFailure)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionTunnelUpdateSuccess, Pixel.Event.networkProtectionTunnelUpdateSuccess)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionTunnelWakeFailure, Pixel.Event.networkProtectionTunnelWakeFailure)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionUnhandledError, Pixel.Event.networkProtectionUnhandledError)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionUnmanagedSubscriptionError, Pixel.Event.networkProtectionUnmanagedSubscriptionError)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionVPNAccessRevoked, Pixel.Event.networkProtectionVPNAccessRevoked)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionWireguardErrorCannotLocateTunnelFileDescriptor, Pixel.Event.networkProtectionWireguardErrorCannotLocateTunnelFileDescriptor)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionWireguardErrorCannotSetNetworkSettings, Pixel.Event.networkProtectionWireguardErrorCannotSetNetworkSettings)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionWireguardErrorCannotSetWireguardConfig, Pixel.Event.networkProtectionWireguardErrorCannotSetWireguardConfig)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionWireguardErrorCannotStartWireguardBackend, Pixel.Event.networkProtectionWireguardErrorCannotStartWireguardBackend)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionWireguardErrorFailedDNSResolution, Pixel.Event.networkProtectionWireguardErrorFailedDNSResolution)
        assertNameParity(NetworkProtectionPixelEvent.networkProtectionWireguardErrorInvalidState, Pixel.Event.networkProtectionWireguardErrorInvalidState)
        assertNameParity(NetworkProtectionPixelEvent.subscriptionKeychainAccessError, Pixel.Event.subscriptionKeychainAccessError)
    }

    // MARK: - Reusable helper

    /// Asserts a native `PixelKitEvent` emits the same wire name as a legacy `Pixel.Event`.
    ///
    /// Generic on purpose: any legacy→PixelKit pixel migration can reuse this to lock name parity.
    /// A good candidate to promote to `SharedTestUtils` once a second migration needs it.
    private func assertNameParity(_ native: PixelKitEvent,
                                  _ legacy: Pixel.Event,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) {
        XCTAssertEqual(native.name, legacy.name,
                       "Wire-name parity broken: native '\(native.name)' vs legacy '\(legacy.name)'",
                       file: file, line: line)
    }
}
