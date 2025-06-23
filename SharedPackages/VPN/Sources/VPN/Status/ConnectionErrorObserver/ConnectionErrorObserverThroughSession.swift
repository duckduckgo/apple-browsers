//
//  ConnectionErrorObserverThroughSession.swift
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
import Common
import os.log

/// This status observer can only be used from the App that owns the tunnel, as other Apps won't have access to the
/// NEVPNStatusDidChange notifications or tunnel session.
///
public class ConnectionErrorObserverThroughSession: ConnectionErrorObserver {
    public lazy var publisher: AnyPublisher<String?, Never> = subject.eraseToAnyPublisher()
    public var recentValue: String? {
        subject.value
    }
    private let subject = CurrentValueSubject<String?, Never>(nil)

    // MARK: - Notifications

    private let tunnelSessionProvider: TunnelSessionProvider
    private let notificationCenter: NotificationCenter
    private let platformNotificationCenter: NotificationCenter
    private let platformDidWakeNotification: Notification.Name
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init(tunnelSessionProvider: TunnelSessionProvider,
                notificationCenter: NotificationCenter = .default,
                platformNotificationCenter: NotificationCenter,
                platformDidWakeNotification: Notification.Name) {

        self.notificationCenter = notificationCenter
        self.platformNotificationCenter = platformNotificationCenter
        self.platformDidWakeNotification = platformDidWakeNotification
        self.tunnelSessionProvider = tunnelSessionProvider
        start()
    }

    func start() {
        notificationCenter.publisher(for: .NEVPNStatusDidChange).sink { [weak self] notification in
            self?.handleStatusChangeNotification(notification)
        }.store(in: &cancellables)

        platformNotificationCenter.publisher(for: platformDidWakeNotification).sink { [weak self] notification in
            self?.handleDidWake(notification)
        }.store(in: &cancellables)
    }

    // MARK: - Handling Notifications

    private func handleDidWake(_ notification: Notification) {
        Task {
            do {
                guard let session = await tunnelSessionProvider.activeSession() else {
                    return
                }

                try updateTunnelErrorMessage(session: session)
            } catch {
                Logger.networkProtection.error("Failed to handle wake \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func handleStatusChangeNotification(_ notification: Notification) {
        do {
            guard let session = ConnectionSessionUtilities.session(from: notification),
                session.status == .disconnected else {

                return
            }

            try updateTunnelErrorMessage(session: session)
        } catch {
            Logger.networkProtection.error("Failed to handle status change \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Obtaining the NetP VPN status

    private func updateTunnelErrorMessage(session: NETunnelProviderSession) throws {
        try session.sendProviderMessage(.getLastErrorMessage) { [weak self] (errorMessage: ExtensionMessageString?) in
            guard errorMessage?.value != self?.subject.value else { return }
            self?.subject.send(errorMessage?.value)
        }
    }
}
