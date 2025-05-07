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
        // async, so for now we'll be content to allow this to be false and spawn a task to
        // update it.
        subject = CurrentValueSubject<Bool, Never>(false)

        Task { [tunnelSessionProvider] in
            guard let activeSession = await tunnelSessionProvider.activeSession() else {
                return
            }

            updateSubject(with: activeSession)
        }

        startObservingChanges()
    }

    // MARK: - VPN-Enabled Status Calculations

    private static func isVPNEnabled(status: NEVPNStatus, isOnDemandEnabled: Bool) -> Bool {
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

    private func startObservingChanges() {
        let statusPublisher = notificationCenter.publisher(for: .NEVPNStatusDidChange)
            .compactMap { notification -> NEVPNConnection? in
                notification.object as? NEVPNConnection
            }
            .map { connection -> NEVPNStatus in
                connection.status
            }
            .removeDuplicates()

        let configPublisher = notificationCenter.publisher(for: .NEVPNConfigurationChange)
            .compactMap { notification in
                notification.object as? NEVPNManager
            }
            .flatMap { [extensionResolver] manager -> AnyPublisher<(NEVPNManager, String), Never> in
                Future { promise in
                    Task {
                        let bundleID = await extensionResolver.activeExtensionBundleID
                        promise(.success((manager, bundleID)))
                    }
                }
                .eraseToAnyPublisher()
            }
            .filter { manager, activeExtensionBundleID in
                guard let tunnelProviderProtocol = (manager.protocolConfiguration as? NETunnelProviderProtocol) else {
                    return false
                }

                return tunnelProviderProtocol.providerBundleIdentifier == activeExtensionBundleID
            }
            .map { manager, _ in
                manager.isOnDemandEnabled
            }
            .removeDuplicates()

        Publishers.CombineLatest(statusPublisher, configPublisher)
            .map { (status, isOnDemandEnabled) -> Bool in
                Self.isVPNEnabled(status: status, isOnDemandEnabled: isOnDemandEnabled)
            }
            .sink { [subject] isVPNEnabled in
                subject.send(isVPNEnabled)
            }
            .store(in: &cancellables)

        notificationCenter.publisher(for: .VPNSnoozeRefreshed)
            .sink { [weak self] notification in
                self?.handleRefreshNotification(notification)
        }.store(in: &cancellables)

        platformNotificationCenter.publisher(for: platformDidWakeNotification)
            .sink { [weak self] notification in
                self?.handleRefreshNotification(notification)
        }.store(in: &cancellables)
    }

    // MARK: - Handling Notifications

    private func handleRefreshNotification(_ notification: Notification) {
        Task {
            guard let session = await tunnelSessionProvider.activeSession() else {
                return
            }

            updateSubject(with: session)
        }
    }

    private func handleChange(in session: NETunnelProviderSession) {
        updateSubject(with: session)
    }

    // MARK: - Update Subject

    private var updateSubjectTask: Task<Void, Error>?

    private func updateSubject(with session: NETunnelProviderSession) {
        updateSubjectTask?.cancel()

        updateSubjectTask = Task { @MainActor in
            let isVPNEnabled = Self.isVPNEnabled(status: session.status, isOnDemandEnabled: session.manager.isOnDemandEnabled)

            try Task.checkCancellation()

            if isVPNEnabled != subject.value {
                subject.send(isVPNEnabled)
            }
        }
    }
}
