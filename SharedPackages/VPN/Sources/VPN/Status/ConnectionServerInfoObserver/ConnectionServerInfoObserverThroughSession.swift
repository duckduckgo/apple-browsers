//
//  ConnectionServerInfoObserverThroughSession.swift
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
public class ConnectionServerInfoObserverThroughSession: ConnectionServerInfoObserver {
    public lazy var publisher = subject.eraseToAnyPublisher()
    public var recentValue: NetworkProtectionStatusServerInfo {
        subject.value
    }

    private let subject = CurrentValueSubject<NetworkProtectionStatusServerInfo, Never>(.unknown)

    private let tunnelSessionProvider: TunnelSessionProvider

    // MARK: - Notifications

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
            guard let session = await tunnelSessionProvider.activeSession() else {
                return
            }

            await updateServerInfo(session: session)
        }
    }

    private func handleStatusChangeNotification(_ notification: Notification) {
        guard let session = ConnectionSessionUtilities.session(from: notification) else {
            return
        }

        Task {
            await updateServerInfo(session: session)
        }
    }

    // MARK: - Obtaining the NetP VPN status

    private func updateServerInfo(session: NETunnelProviderSession) async {
        guard session.status == .connected else {
            subject.send(NetworkProtectionStatusServerInfo.unknown)
            return
        }

        let serverAddress = await self.serverAddress(from: session)
        let serverLocation = await self.serverLocation(from: session)

        let newServerInfo = NetworkProtectionStatusServerInfo(serverLocation: serverLocation, serverAddress: serverAddress)

        subject.send(newServerInfo)
    }

    private func serverAddress(from session: NETunnelProviderSession) async -> String? {
        await withCheckedContinuation { continuation in
            do {
                try session.sendProviderMessage(.getServerAddress) { (serverAddress: ExtensionMessageString?) in
                    continuation.resume(returning: serverAddress?.value)
                }
            } catch {
                // Cannot communicate with session, this is acceptable in case the session is down
                continuation.resume(returning: nil)
            }
        }
    }

    private func serverLocation(from session: NETunnelProviderSession) async -> NetworkProtectionServerInfo.ServerAttributes? {
        await withCheckedContinuation { continuation in
            do {
                try session.sendProviderMessage(.getServerLocation) { (serverLocation: ExtensionMessageString?) in
                    guard let locationData = serverLocation?.rawValue else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let decoder = JSONDecoder()
                    let decoded = try? decoder.decode(NetworkProtectionServerInfo.ServerAttributes.self, from: locationData)
                    continuation.resume(returning: decoded)
                }
            } catch {
                // Cannot communicate with session, this is acceptable in case the session is down
                continuation.resume(returning: nil)
            }
        }
    }
}
