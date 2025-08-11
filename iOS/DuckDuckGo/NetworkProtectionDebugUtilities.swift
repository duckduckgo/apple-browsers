//
//  NetworkProtectionDebugUtilities.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import VPN
import NetworkExtension

/// Utility code to help implement our debug menu options for Network Protection.
///
final class NetworkProtectionDebugUtilities {

    // MARK: - Registation Key

    func expireRegistrationKeyNow() async {
        guard let activeSession = await AppDependencyProvider.shared.networkProtectionTunnelController.activeSession() else {
            return
        }

        try? await activeSession.sendProviderMessage(.expireRegistrationKey)
    }

    // MARK: - Notifications

    func sendTestNotificationRequest() async throws {
        guard let activeSession = await AppDependencyProvider.shared.networkProtectionTunnelController.activeSession() else {
            return
        }

        try? await activeSession.sendProviderMessage(.triggerTestNotification)
    }

    // MARK: - Simulate Subscription Expiration

    func simulateSubscriptionExpirationInTunnel() async {
        guard let activeSession = await AppDependencyProvider.shared.networkProtectionTunnelController.activeSession() else {
            return
        }

        try? await activeSession.sendProviderRequest(.command(.simulateSubscriptionExpirationInTunnel))
    }

    // MARK: - Failure Simulation

    func triggerSimulation(_ option: NetworkProtectionSimulationOption) async {
        guard let activeSession = await AppDependencyProvider.shared.networkProtectionTunnelController.activeSession() else {
            return
        }

        guard let message = option.extensionMessage else {
            return
        }
        try? await activeSession.sendProviderMessage(message)
    }

    // MARK: - Snooze

    func startSnooze(duration: TimeInterval) async {
        guard let activeSession = await AppDependencyProvider.shared.networkProtectionTunnelController.activeSession() else {
            return
        }

        try? await activeSession.sendProviderMessage(.startSnooze(duration))
    }
    
    func createLogSnapshot() async throws {
        guard let activeSession = await AppDependencyProvider.shared.networkProtectionTunnelController.activeSession() else {
            throw NSError(domain: "NetworkProtectionDebugUtilities", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active VPN session"])
        }

        let responseData: ExtensionMessageString? = try await activeSession.sendProviderRequest(.command(.createLogSnapshot))

        guard let responseString = responseData?.value else {
            throw NSError(domain: "NetworkProtectionDebugUtilities", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response from VPN extension"])
        }
        
        if responseString.hasPrefix("Error: ") {
            let errorMessage = String(responseString.dropFirst("Error: ".count))
            throw NSError(domain: "NetworkProtectionDebugUtilities", code: 3, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
    }
}

private extension NetworkProtectionSimulationOption {
    var extensionMessage: ExtensionMessage? {
        switch self {
        case .crashFatalError:
            return .simulateTunnelFatalError
        case .crashMemory:
            return .simulateTunnelMemoryOveruse
        case .tunnelFailure:
            return .simulateTunnelFailure
        case .controllerFailure:
            return nil
        case .connectionInterruption:
            return .simulateConnectionInterruption
        }
    }
}
