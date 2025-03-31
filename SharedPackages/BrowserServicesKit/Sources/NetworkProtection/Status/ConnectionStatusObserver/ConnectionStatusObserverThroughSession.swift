//
//  ConnectionStatusObserverThroughSession.swift
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

import Combine
import Foundation
import NetworkExtension
import NotificationCenter
import Common
import os.log

/// This status observer can only be used from the App that owns the tunnel, as other Apps won't have access to the
/// NEVPNStatusDidChange notifications or tunnel session.
///
public class ConnectionStatusObserverThroughSession: ConnectionStatusObserver {
    public lazy var publisher: AnyPublisher<ConnectionStatus, Never> = subject.eraseToAnyPublisher()
    public var recentValue: ConnectionStatus {
        subject.value
    }

    private let subject = CurrentValueSubject<ConnectionStatus, Never>(.disconnected)

    private let tunnelSessionProvider: TunnelSessionProvider

    // MARK: - Notifications
    private let notificationCenter: NotificationCenter
    private let platformSnoozeTimingStore: NetworkProtectionSnoozeTimingStore
    private let platformNotificationCenter: NotificationCenter
    private let platformDidWakeNotification: Notification.Name
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init(tunnelSessionProvider: TunnelSessionProvider,
                notificationCenter: NotificationCenter = .default,
                platformSnoozeTimingStore: NetworkProtectionSnoozeTimingStore,
                platformNotificationCenter: NotificationCenter,
                platformDidWakeNotification: Notification.Name) {

        self.notificationCenter = notificationCenter
        self.platformSnoozeTimingStore = platformSnoozeTimingStore
        self.platformNotificationCenter = platformNotificationCenter
        self.platformDidWakeNotification = platformDidWakeNotification
        self.tunnelSessionProvider = tunnelSessionProvider

        start()
    }

    private func start() {
        startObservers()
        Task {
            await loadInitialStatus()
        }
    }

    private func startObservers() {
        notificationCenter.publisher(for: .NEVPNStatusDidChange).sink { [weak self] notification in
            self?.handleStatusChangeNotification(notification)
        }.store(in: &cancellables)

        notificationCenter.publisher(for: .VPNSnoozeRefreshed).sink { [weak self] notification in
            self?.handleStatusRefreshNotification(notification)
        }.store(in: &cancellables)

        platformNotificationCenter.publisher(for: platformDidWakeNotification).sink { [weak self] notification in
            self?.handleStatusRefreshNotification(notification)
        }.store(in: &cancellables)
    }

    private func loadInitialStatus() async {
        guard let session = await tunnelSessionProvider.activeSession() else {
            return
        }

        handleStatusChange(in: session)
    }

    // MARK: - Handling Notifications

    private func handleStatusRefreshNotification(_ notification: Notification) {
        Task {
            guard let session = await tunnelSessionProvider.activeSession() else {
                return
            }

            handleStatusChange(in: session)
        }
    }

    private func handleStatusChangeNotification(_ notification: Notification) {
        guard let session = ConnectionSessionUtilities.session(from: notification) else {
            return
        }

        handleStatusChange(in: session)
    }

    private func handleStatusChange(in session: NETunnelProviderSession) {
        let status = self.connectionStatus(from: session)
        logStatusChanged(status: status)
        subject.send(status)
    }

    // MARK: - Obtaining the NetP VPN status

    private func connectedDate(from session: NETunnelProviderSession) -> Date {
        // In theory when the connection has been established, the date should be set.  But in a worst-case
        // scenario where for some reason the date is missing, we're going to just use Date() as the connection
        // has just started and it's a decent approximation.
        session.connectedDate ?? Date()
    }

    private func connectionStatus(from session: NETunnelProviderSession) -> ConnectionStatus {
        let internalStatus = session.status
        let status: ConnectionStatus

        switch internalStatus {
        case .connected:
            if platformSnoozeTimingStore.activeTiming != nil {
                status = .snoozing
            } else {
                let connectedDate = connectedDate(from: session)
                status = .connected(connectedDate: connectedDate)
            }
        case .connecting:
            status = .connecting
        case .reasserting:
            status = .reasserting
        case .disconnected, .invalid:
            status = .disconnected
        case .disconnecting:
            status = .disconnecting
        @unknown default:
            status = .disconnected
        }

        return status
    }

    // MARK: - Logging

    private func logStatusChanged(status: ConnectionStatus) {
        let unmanagedObject = Unmanaged.passUnretained(self)
        let address = unmanagedObject.toOpaque()
        Logger.networkProtectionMemory.debug("\(String(describing: self), privacy: .public)<\(String(describing: address), privacy: .public)>: connection status is now \(String(describing: status), privacy: .public)")
    }
}
