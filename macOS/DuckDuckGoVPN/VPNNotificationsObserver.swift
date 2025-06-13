//
//  VPNNotificationsObserver.swift
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

import AppLauncher
import AppKit
import Combine
import Foundation
import VPNNotifications
import os.log

final class VPNNotificationsObserver {

    private let notificationsPresenter = {
        let parentBundlePath = "../../../../"
        let mainAppURL: URL

        if #available(macOS 13, *) {
            mainAppURL = URL(filePath: parentBundlePath, relativeTo: Bundle.main.bundleURL)
        } else {
            mainAppURL = URL(fileURLWithPath: parentBundlePath, relativeTo: Bundle.main.bundleURL)
        }

        return VPNNotificationsPresenter(appLauncher: AppLauncher(appBundleURL: mainAppURL))
    }()

    private let distributedNotificationCenter = DistributedNotificationCenter.default()

    // MARK: - Notifications: Observation Tokens

    private var cancellables = Set<AnyCancellable>()

    func startObservingVPNStatusChanges() {
        Logger.networkProtection.log("Register with sysex")

        distributedNotificationCenter.publisher(for: .showIssuesStartedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showReconnectingNotification()
            }.store(in: &cancellables)

        distributedNotificationCenter.publisher(for: .showConnectedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let serverLocation = notification.object as? String
                self?.showConnectedNotification(serverLocation: serverLocation)
            }.store(in: &cancellables)

        distributedNotificationCenter.publisher(for: .showIssuesNotResolvedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showConnectionFailureNotification()
            }.store(in: &cancellables)

        distributedNotificationCenter.publisher(for: .showVPNSupersededNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showSupersededNotification()
            }.store(in: &cancellables)

        distributedNotificationCenter.publisher(for: .showTestNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showTestNotification()
            }.store(in: &cancellables)

        distributedNotificationCenter.publisher(for: .serverSelected).sink { [weak self] _ in
            Logger.networkProtection.log("Got notification: listener started")
            self?.notificationsPresenter.requestAuthorization()
        }.store(in: &cancellables)

        distributedNotificationCenter.publisher(for: .showExpiredEntitlementNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showEntitlementNotification()
            }.store(in: &cancellables)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Showing Notifications

    func showConnectedNotification(serverLocation: String?) {
        Logger.networkProtection.info("Presenting reconnected notification")
        notificationsPresenter.showConnectedNotification(serverLocation: serverLocation, snoozeEnded: false)
    }

    func showReconnectingNotification() {
        Logger.networkProtection.info("Presenting reconnecting notification")
        notificationsPresenter.showReconnectingNotification()
    }

    func showConnectionFailureNotification() {
        Logger.networkProtection.info("Presenting failure notification")
        notificationsPresenter.showConnectionFailureNotification()
    }

    func showSupersededNotification() {
        Logger.networkProtection.info("Presenting Superseded notification")
        notificationsPresenter.showSupersededNotification()
    }

    func showEntitlementNotification() {
        Logger.networkProtection.info("Presenting Entitlements notification")

        notificationsPresenter.showEntitlementNotification()
    }

    func showTestNotification() {
        Logger.networkProtection.info("Presenting test notification")
        notificationsPresenter.showTestNotification()
    }

}
