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

/// Observes VPN-related distributed notifications and presents user notifications accordingly.
///
/// This class serves as a bridge between the VPN system extension and the user interface,
/// listening for various VPN status changes and presenting appropriate notifications to the user.
/// It handles connection status updates, failures, entitlement issues, and other VPN-related events.
///
/// - Note: This observer uses `DistributedNotificationCenter` to receive notifications from
///   the VPN system extension and delegates the actual notification presentation to `VPNNotificationsPresenter`.
final class VPNNotificationsObserver {

    /// Presents VPN notifications to the user.
    ///
    /// This presenter is initialized with an `AppLauncher` configured to launch the main DuckDuckGo app.
    /// The presenter handles the actual display of user notifications and manages notification permissions.
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

    /// Distributed notification center used to receive notifications from the VPN system extension.
    private let distributedNotificationCenter = DistributedNotificationCenter.default()

    // MARK: - Notifications: Observation Tokens

    /// Set of Combine cancellables for managing notification observation subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Starts observing VPN status changes via distributed notifications.
    ///
    /// This method sets up subscribers for various VPN-related distributed notifications:
    /// - Connection issues started (triggers reconnecting notification)
    /// - Connection established (triggers connected notification with server location)
    /// - Connection issues not resolved (triggers connection failure notification)
    /// - VPN superseded by another VPN (triggers superseded notification)
    /// - Test notifications for debugging
    /// - Server selection events (triggers notification authorization request)
    /// - Expired entitlement notifications
    ///
    /// All notification handlers are dispatched to the main queue to ensure UI updates
    /// occur on the main thread.
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

    // MARK: - Showing Notifications

    /// Displays a notification indicating the VPN has successfully connected.
    ///
    /// - Parameter serverLocation: Optional server location string to include in the notification.
    ///   If provided, the notification will show which server the VPN connected to.
    func showConnectedNotification(serverLocation: String?) {
        Logger.networkProtection.info("Presenting reconnected notification")
        notificationsPresenter.showConnectedNotification(serverLocation: serverLocation, snoozeEnded: false)
    }

    /// Displays a notification indicating the VPN is attempting to reconnect.
    ///
    /// This notification is typically shown when the VPN encounters connectivity issues
    /// and is trying to re-establish the connection.
    func showReconnectingNotification() {
        Logger.networkProtection.info("Presenting reconnecting notification")
        notificationsPresenter.showReconnectingNotification()
    }

    /// Displays a notification indicating the VPN connection has failed.
    ///
    /// This notification is shown when the VPN is unable to establish or maintain
    /// a connection after multiple attempts.
    func showConnectionFailureNotification() {
        Logger.networkProtection.info("Presenting failure notification")
        notificationsPresenter.showConnectionFailureNotification()
    }

    /// Displays a notification indicating the VPN has been superseded by another VPN.
    ///
    /// This notification is shown when another VPN configuration takes precedence
    /// over the DuckDuckGo VPN, typically due to system-level VPN conflicts.
    func showSupersededNotification() {
        Logger.networkProtection.info("Presenting Superseded notification")
        notificationsPresenter.showSupersededNotification()
    }

    /// Displays a notification indicating VPN entitlements have expired.
    ///
    /// This notification alerts the user that their VPN subscription or entitlement
    /// has expired and they need to renew to continue using the VPN service.
    func showEntitlementNotification() {
        Logger.networkProtection.info("Presenting Entitlements notification")

        notificationsPresenter.showEntitlementNotification()
    }

    /// Displays a test notification for debugging purposes.
    ///
    /// This method is used during development and testing to verify that the
    /// notification system is working correctly.
    func showTestNotification() {
        Logger.networkProtection.info("Presenting test notification")
        notificationsPresenter.showTestNotification()
    }

}
