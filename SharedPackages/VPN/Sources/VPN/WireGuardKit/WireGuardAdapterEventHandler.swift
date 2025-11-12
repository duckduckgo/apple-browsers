//
//  WireGuardAdapterEventHandler.swift
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
import os.log
import Common

/// Protocol for handling WireGuard adapter events.
public protocol WireGuardAdapterEventHandling {
    func handle(_ event: WireGuardAdapterEvent)
}

/// Handles events from the WireGuard adapter and coordinates responses.
public final class WireGuardAdapterEventHandler: WireGuardAdapterEventHandling {
    private let providerEvents: EventMapping<PacketTunnelProvider.Event>
    private let settings: VPNSettings
    private let notificationsPresenter: VPNNotificationsPresenting

    public init(providerEvents: EventMapping<PacketTunnelProvider.Event>,
                settings: VPNSettings,
                notificationsPresenter: VPNNotificationsPresenting) {
        self.providerEvents = providerEvents
        self.settings = settings
        self.notificationsPresenter = notificationsPresenter
    }

    public func handle(_ event: WireGuardAdapterEvent) {
        switch event {
        case .endTemporaryShutdownStateAttemptFailure(let error):
            Logger.networkProtection.error("Adapter failed to exit temporary shutdown: \(error.localizedDescription)")
            providerEvents.fire(.adapterEndTemporaryShutdownStateAttemptFailure(error))
        case .endTemporaryShutdownStateRecoveryFailure(let error):
            Logger.networkProtection.error("Adapter recovery from temporary shutdown failed: \(error.localizedDescription)")
            providerEvents.fire(.adapterEndTemporaryShutdownStateRecoveryFailure(error))
        case .endTemporaryShutdownStateRecoverySuccess:
            Logger.networkProtection.log("Adapter recovery from temporary shutdown succeeded")
            providerEvents.fire(.adapterEndTemporaryShutdownStateRecoverySuccess)
        }

        if settings.showDebugVPNEventNotifications {
            let notificationText: String

            switch event {
            case .endTemporaryShutdownStateAttemptFailure(let error):
                notificationText = "VPN failed to end temporary shutdown: \(error.localizedDescription)"
            case .endTemporaryShutdownStateRecoveryFailure(let error):
                notificationText = "VPN failed to recover from extended temporary shutdown: \(error.localizedDescription)"
            case .endTemporaryShutdownStateRecoverySuccess:
                notificationText = "VPN recovered after extended temporary shutdown"
            }

            notificationsPresenter.showDebugEventNotification(message: notificationText)
        }
    }
}
