//
//  VPNConnectionError.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import VPN

/// Represents VPN connection errors with user-friendly localized messages.
///
/// This type can be initialized from an NSError (using domain and error code) or from
/// an error message string (as a fallback). The NSError-based initialization is preferred
/// as it's more robust against message string changes.
///
enum VPNConnectionError: Equatable {
    case authenticationFailed
    case connectionFailed
    case subscriptionExpired
    case unknown

    private typealias TunnelErrorCode = PacketTunnelProvider.TunnelError.Code

    // MARK: - Initialization

    /// Initialize from an NSError, mapping the domain and error code to the appropriate case.
    ///
    /// This handles both direct `TunnelError` instances and `SanitizedError` wrappers that
    /// preserve the original error info in `userInfo`.
    ///
    /// - Parameter error: The NSError from `fetchLastDisconnectError` or similar.
    /// - Returns: A `VPNConnectionError` case, or `nil` if the error should not be displayed
    ///            (e.g., user-initiated cancellation).
    ///
    init?(nsError error: NSError) {
        // First, try to get domain and code directly from the error
        var domain = error.domain
        var code = error.code

        // Check if this is a SanitizedError wrapper - if so, extract the original domain/code from userInfo
        if let originalDomain = error.userInfo["OriginalErrorDomain"] as? String,
           let originalCode = error.userInfo["OriginalErrorCode"] as? Int {
            domain = originalDomain
            code = originalCode
        }

        // Check if this is a TunnelError
        guard domain == PacketTunnelProvider.TunnelError.errorDomain else {
            self = .unknown
            return
        }

        guard let errorCode = TunnelErrorCode(rawValue: code) else {
            self = .unknown
            return
        }

        switch errorCode {
        case .startingTunnelWithoutAuthToken:
            self = .authenticationFailed
        case .couldNotGenerateTunnelConfiguration:
            self = .connectionFailed
        case .vpnAccessRevoked, .vpnAccessRevokedDetectedByMonitorCheck:
            self = .subscriptionExpired
        case .simulateTunnelFailureError, .settingsMissing, .tokenReset:
            self = .unknown
        case .simulateSubscriptionExpiration, .appRequestedCancellation:
            // Don't show error UI for simulated expiration or user-initiated disconnection
            return nil
        }
    }

    /// Initialize from an error message string (fallback when NSError is not available).
    ///
    /// This uses pattern matching on known error message strings from TunnelError.errorDescription.
    /// This approach is less robust than NSError-based initialization, so prefer using `init(nsError:)`
    /// when possible.
    ///
    /// - Parameter errorMessage: The error message string.
    /// - Returns: A `VPNConnectionError` case, or `nil` if the error should not be displayed.
    ///
    init?(errorMessage: String) {
        switch errorMessage {
        case let msg where msg.contains("Missing auth token"):
            self = .authenticationFailed
        case let msg where msg.contains("Failed to generate a tunnel configuration"):
            self = .connectionFailed
        case "VPN disconnected due to expired subscription":
            self = .subscriptionExpired
        default:
            self = .unknown
        }
    }

    // MARK: - Localized Message

    /// Returns the user-friendly localized error message.
    var localizedMessage: String {
        switch self {
        case .authenticationFailed:
            return UserText.vpnErrorAuthenticationFailed
        case .connectionFailed:
            return UserText.vpnErrorConnectionFailed
        case .subscriptionExpired:
            return UserText.vpnErrorSubscriptionExpired
        case .unknown:
            return UserText.vpnErrorUnknown
        }
    }
}
