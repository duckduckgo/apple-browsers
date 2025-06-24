//
//  AuthV2PixelHandler.swift
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
import Subscription
import PixelKit
import os.log
import Common
import Combine

/// Handles the pixels fired by SubscriptionManagerV2, listens to subscriptionDidChange and entitlementsDidChange notifications and fires the related pixels for debugging purposes
public class AuthV2PixelHandler: SubscriptionPixelHandler {

    public enum Source {
        case mainApp
        case systemExtension
        case vpnApp
        case dbp

        var description: String {
            switch self {
            case .mainApp:
                return "MainApp"
            case .systemExtension:
                return "SysExt"
            case .vpnApp:
                return "VPNApp"
            case .dbp:
                return "DBP"
            }
        }
    }

    let source: Source
    private let notificationCenter: NotificationCenter
    private var cancellables = Set<AnyCancellable>()

    public init(source: Source, notificationCenter: NotificationCenter = .default) {
        self.source = source
        self.notificationCenter = notificationCenter

        notificationCenter.publisher(for: .subscriptionDidChange).sink { [weak self] param in

            guard let self else { return }

            guard let userInfo = param.userInfo as? [AnyHashable: PrivacyProSubscription],
                  let subscription = userInfo[UserDefaultsCacheKey.subscription] else {
                PixelKit.fire(PrivacyProPixel.privacyProSubscriptionMissing(self.source), frequency: .dailyAndCount)
                return
            }

            if !subscription.isActive {
                PixelKit.fire(PrivacyProPixel.privacyProSubscriptionExpired(source), frequency: .daily)
            }
        }.store(in: &cancellables)

        // Intercepting and sending a pixel every time a set of entitlements change. We are only interested in changes between full > empty. Any other combination is not possible
        notificationCenter.publisher(for: .entitlementsDidChange).sink { [weak self] notification in

            guard let self else { return }

            guard (notification.object as? SubscriptionManagerV2) != nil else {
                // Sending pixel only for user entitlements, ignoring the Subscription entitlements coming from DefaultSubscriptionEndpointServiceV2
                return
            }

            let userInfo = notification.userInfo as? [AnyHashable: [Entitlement]] ?? [:]
            let entitlements = Set(userInfo[UserDefaultsCacheKey.subscriptionEntitlements] ?? [])
            let previousEntitlements = Set(userInfo[UserDefaultsCacheKey.subscriptionPreviousEntitlements] ?? [])

            Self.sendPixelForEntitlementChange(newEntitlement: entitlements, previousEntitlements: previousEntitlements, source: self.source, pixelKit: PixelKit.shared)

        }.store(in: &cancellables)
    }

    static func sendPixelForEntitlementChange(newEntitlement: Set<Entitlement>,
                                              previousEntitlements: Set<Entitlement>,
                                              source: Source,
                                              pixelKit: PixelFiring?) {
        let addedEntitlements = newEntitlement.subtracting(previousEntitlements)
        let removedEntitlements = previousEntitlements.subtracting(newEntitlement)

        if !addedEntitlements.isEmpty {
            pixelKit?.fire(PrivacyProPixel.privacyProEntitlementsAdded(source), frequency: .dailyAndCount)
        }

        if !removedEntitlements.isEmpty {
            pixelKit?.fire(PrivacyProPixel.privacyProEntitlementsRemoved(source), frequency: .dailyAndCount)
        }

        if addedEntitlements.isEmpty && removedEntitlements.isEmpty {
            Logger.subscription.debug("No changes in entitlements in notification, ignoring...")
        }
    }

    public func handle(pixelType: SubscriptionPixelType) {
        switch pixelType {
        case .invalidRefreshToken:
            PixelKit.fire(PrivacyProPixel.privacyProInvalidRefreshTokenDetected(source), frequency: .dailyAndCount)
        case .subscriptionIsActive:
            PixelKit.fire(PrivacyProPixel.privacyProSubscriptionActive, frequency: .legacyDaily)
        case .migrationFailed(let error):
            PixelKit.fire(PrivacyProPixel.privacyProAuthV2MigrationFailed(source, error), frequency: .dailyAndCount)
        case .migrationSucceeded:
            PixelKit.fire(PrivacyProPixel.privacyProAuthV2MigrationSucceeded(source), frequency: .dailyAndCount)
        case .getTokensError(let policy, let error):
            PixelKit.fire(PrivacyProPixel.privacyProAuthV2GetTokensError(policy, source, error), frequency: .dailyAndCount)
        case .invalidRefreshTokenSignedOut:
            PixelKit.fire(PrivacyProPixel.privacyProInvalidRefreshTokenSignedOut, frequency: .dailyAndCount)
        case .invalidRefreshTokenRecovered:
            PixelKit.fire(PrivacyProPixel.privacyProInvalidRefreshTokenRecovered, frequency: .dailyAndCount)
        }
    }
}
