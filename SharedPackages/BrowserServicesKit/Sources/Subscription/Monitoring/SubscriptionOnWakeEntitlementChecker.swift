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

import AppKit
import Combine
import Foundation
import Common
import os.log

/// A reusable class that checks subscription entitlements when the system wakes from sleep.
/// This can be used across different targets that need to verify subscription entitlements after wake events.
/// Reports current entitlement status via callback on every wake - parent decides how to handle state changes.
public final class SubscriptionOnWakeEntitlementChecker {
    
    public typealias StatusHandler = (
        _ feature: Entitlement.ProductName,
        _ hasEntitlement: Bool
    ) -> Void

    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private let features: [Entitlement.ProductName]
    private let wakeNotificationPublisher: AnyPublisher<Notification, Never>
    private let onEntitlementStatus: StatusHandler
    private var cancellables = Set<AnyCancellable>()
    
    /// Initializes the wake entitlement checker.
    /// 
    /// - Parameters:
    ///   - subscriptionManager: The subscription manager to use for entitlement checks
    ///   - features: The features/entitlements to check (e.g., [.networkProtection, .dataBrokerProtection])
    ///   - onEntitlementStatus: Callback invoked with current entitlement status on wake
    ///   - wakeNotificationPublisher: Publisher for wake notifications (defaults to system wake notifications)
    public init(subscriptionManager: any SubscriptionAuthV1toV2Bridge,
                features: [Entitlement.ProductName],
                onEntitlementStatus: @escaping StatusHandler,
                wakeNotificationPublisher: AnyPublisher<Notification, Never> = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).eraseToAnyPublisher()) {
        self.subscriptionManager = subscriptionManager
        self.features = features
        self.onEntitlementStatus = onEntitlementStatus
        self.wakeNotificationPublisher = wakeNotificationPublisher
        
        subscribeToSystemWakeNotifications()
    }

    /// Convenience initializer for single feature.
    public convenience init(subscriptionManager: any SubscriptionAuthV1toV2Bridge,
                           feature: Entitlement.ProductName,
                           onEntitlementStatus: @escaping StatusHandler,
                           wakeNotificationPublisher: AnyPublisher<Notification, Never> = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).eraseToAnyPublisher()) {
        self.init(subscriptionManager: subscriptionManager,
                  features: [feature],
                  onEntitlementStatus: onEntitlementStatus,
                  wakeNotificationPublisher: wakeNotificationPublisher)
    }

    private func subscribeToSystemWakeNotifications() {
        wakeNotificationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                Logger.subscription.log("System did wake notification received, performing entitlements check for \(self?.features.count ?? 0) features")
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
