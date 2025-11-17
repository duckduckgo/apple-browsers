//
//  VPNEnabledObserverThroughSession.swift
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

import Combine
import Foundation
import NetworkExtension
import NotificationCenter
import Common
import os.log

public class VPNEnabledObserverThroughSession: VPNEnabledObserver {

    public var isVPNEnabled: Bool {
        subject.value
    }

    public lazy var publisher: AnyPublisher<Bool, Never> = subject.eraseToAnyPublisher()
    private let subject: CurrentValueSubject<Bool, Never>

    private let tunnelSessionProvider: TunnelSessionProvider
    private let extensionResolver: VPNExtensionResolving

    // MARK: - Notifications

    private let notificationCenter: NotificationCenter
    private let platformSnoozeTimingStore: NetworkProtectionSnoozeTimingStore
    private let platformNotificationCenter: NotificationCenter
    private let platformDidWakeNotification: Notification.Name
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init(tunnelSessionProvider: TunnelSessionProvider,
                extensionResolver: VPNExtensionResolving,
                notificationCenter: NotificationCenter = .default,
                platformSnoozeTimingStore: NetworkProtectionSnoozeTimingStore,
                platformNotificationCenter: NotificationCenter,
                platformDidWakeNotification: Notification.Name) {

        self.extensionResolver = extensionResolver
        self.notificationCenter = notificationCenter
        self.platformSnoozeTimingStore = platformSnoozeTimingStore
        self.platformNotificationCenter = platformNotificationCenter
        self.platformDidWakeNotification = platformDidWakeNotification
        self.tunnelSessionProvider = tunnelSessionProvider

        // Unfortunately we can't set the initial value from real data without making the init
        // async, so for now we'll be content to allow this to be false. The initial update
        // will happen in startObservingChanges().
        subject = CurrentValueSubject<Bool, Never>(false)

        startObservingChanges()
    }

    // MARK: - VPN-Enabled Status Calculations

    internal static func isVPNEnabled(status: NEVPNStatus, isOnDemandEnabled: Bool) -> Bool {
        // If the VPN has not been configured it's certainly not on, and won't have on-demand
        // enabled.  We need to capture this here though because `isOnDemandEnabled` keeps
        // returning true the last known value when the VPN configuration has been deleted.
        guard status != .invalid else {
            return false
        }

        let isVPNConnectedOrConnecting = status == .connected
            || status == .connecting
            || status == .reasserting
        return isOnDemandEnabled || isVPNConnectedOrConnecting
    }

    // MARK: - Observing VPN status and configuration

    private func subscribeToRefreshNotifications() {
        notificationCenter.publisher(for: .VPNSnoozeRefreshed)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleNotification()
                }
            }.store(in: &cancellables)

        platformNotificationCenter.publisher(for: platformDidWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleNotification()
                }
            }.store(in: &cancellables)
    }

    private func startObservingChanges() {
        // Subscribe to status changes
        notificationCenter.publisher(for: .NEVPNStatusDidChange)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleNotification()
                }
            }
            .store(in: &cancellables)

        // Subscribe to config changes
        notificationCenter.publisher(for: .NEVPNConfigurationChange)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleNotification()
                }
            }
            .store(in: &cancellables)

        // Subscribe to refresh notifications
        subscribeToRefreshNotifications()

        // Fetch initial state
        Task { @MainActor in
            await handleNotification()
        }
    }

    // MARK: - Serial Notification Handler

    @MainActor
    private func handleNotification() async {
        guard let session = await tunnelSessionProvider.activeSession() else {
            if subject.value != false {
                subject.send(false)
            }
            return
        }

        let isEnabled = Self.isVPNEnabled(
            status: session.status,
            isOnDemandEnabled: session.manager.isOnDemandEnabled
        )

        if isEnabled != subject.value {
            subject.send(isEnabled)
        }
    }
}
