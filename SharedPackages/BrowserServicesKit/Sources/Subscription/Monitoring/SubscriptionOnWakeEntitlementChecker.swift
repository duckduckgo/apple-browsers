//
//  SubscriptionOnWakeEntitlementChecker.swift
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
import Common
import os.log

#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

/// A cross-platform class that checks subscription entitlements when the system/app becomes active.
///
/// On macOS: responds to system wake events. On iOS: responds to app foreground events.
/// Reports current entitlement status via callback on every activation - parent decides how to handle state changes.
public final class SubscriptionOnWakeEntitlementChecker {

    public typealias StatusHandler = (
        _ feature: Entitlement.ProductName,
        _ hasEntitlement: Bool
    ) -> Void

    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private let features: [Entitlement.ProductName]
    private let wakeNotificationPublisher: AnyPublisher<Void, Never>
    private let onEntitlementStatus: StatusHandler
    private var cancellables = Set<AnyCancellable>()
    
    /// Initializes the wake entitlement checker.
    /// 
    /// - Parameters:
    ///   - subscriptionManager: The subscription manager to use for entitlement checks
    ///   - features: The features/entitlements to check (e.g., [.networkProtection, .dataBrokerProtection])
    ///   - onEntitlementStatus: Callback invoked with current entitlement status on wake
    ///   - wakeNotificationPublisher: Publisher for wake/activation notifications
    public init(subscriptionManager: any SubscriptionAuthV1toV2Bridge,
                features: [Entitlement.ProductName],
                onEntitlementStatus: @escaping StatusHandler,
                wakeNotificationPublisher: AnyPublisher<Void, Never>) {
        self.subscriptionManager = subscriptionManager
        self.features = features
        self.onEntitlementStatus = onEntitlementStatus
        self.wakeNotificationPublisher = wakeNotificationPublisher

        subscribeToSystemWakeNotifications()
    }



    private func subscribeToSystemWakeNotifications() {
        wakeNotificationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Logger.subscription.log("System activation event received, performing entitlements check for \(self?.features.count ?? 0) features")
                guard let self else {
                    return
                }

                Task {
                    await self.checkAllEntitlementsOnWake()
                }
            }
            .store(in: &cancellables)
    }

    private func checkAllEntitlementsOnWake() async {
        for feature in features {
            let hasEntitlement = await subscriptionManager.isFeatureEnabledForUser(feature: feature)
            await reportEntitlementStatus(feature: feature, hasEntitlement: hasEntitlement)
        }
    }

    @MainActor
    private func reportEntitlementStatus(feature: Entitlement.ProductName, hasEntitlement: Bool) async {
        // Report current entitlement status to parent - parent decides how to handle changes
        onEntitlementStatus(feature, hasEntitlement)
    }
}

#if os(macOS)
// MARK: - macOS Convenience Initializers
extension SubscriptionOnWakeEntitlementChecker {
    
    /// Convenience initializer for macOS with default system wake notification publisher.
    ///
    /// - Parameters:
    ///   - subscriptionManager: The subscription manager to use for entitlement checks
    ///   - features: The features/entitlements to check (e.g., [.networkProtection, .dataBrokerProtection])
    ///   - onEntitlementStatus: Callback invoked with current entitlement status on wake
    public convenience init(subscriptionManager: any SubscriptionAuthV1toV2Bridge,
                           features: [Entitlement.ProductName],
                           onEntitlementStatus: @escaping StatusHandler) {
        self.init(subscriptionManager: subscriptionManager,
                  features: features,
                  onEntitlementStatus: onEntitlementStatus,
                  wakeNotificationPublisher: NSWorkspace.shared.notificationCenter
                    .publisher(for: NSWorkspace.didWakeNotification)
                    .map { _ in () }
                    .eraseToAnyPublisher())
    }
    

}
#endif

#if os(iOS)
// MARK: - iOS Convenience Initializers
extension SubscriptionOnWakeEntitlementChecker {
    
    /// Convenience initializer for iOS with default app foreground notification publisher.
    ///
    /// - Parameters:
    ///   - subscriptionManager: The subscription manager to use for entitlement checks
    ///   - features: The features/entitlements to check (e.g., [.networkProtection, .dataBrokerProtection])
    ///   - onEntitlementStatus: Callback invoked with current entitlement status when app enters foreground
    public convenience init(subscriptionManager: any SubscriptionAuthV1toV2Bridge,
                           features: [Entitlement.ProductName],
                           onEntitlementStatus: @escaping StatusHandler) {
        self.init(subscriptionManager: subscriptionManager,
                  features: features,
                  onEntitlementStatus: onEntitlementStatus,
                  wakeNotificationPublisher: NotificationCenter.default
                    .publisher(for: UIApplication.willEnterForegroundNotification)
                    .map { _ in () }
                    .eraseToAnyPublisher())
    }
    

}
#endif
