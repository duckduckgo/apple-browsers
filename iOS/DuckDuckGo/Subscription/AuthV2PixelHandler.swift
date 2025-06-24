//
//  AuthV2PixelHandler.swift
//  DuckDuckGo
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
import Core
import Common
import Networking
import Combine
import os.log

/// Handles the pixels fired by SubscriptionManagerV2, listens to subscriptionDidChange and entitlementsDidChange notifications and fires the related pixels for debugging purposes
public class AuthV2PixelHandler: SubscriptionPixelHandler {

    public enum Source {
        case mainApp
        case systemExtension
        
        var description: String {
            switch self {
            case .mainApp:
                return "MainApp"
            case .systemExtension:
                return "SysExt"
            }
        }
    }

    struct Defaults {
        static let errorKey = "error"
        static let policyCacheKey = "policycache"
        static let sourceKey = "source"
    }

    private let source: Source
    private var sourceParam: [String: String] {
        [Defaults.sourceKey: source.description]
    }
    private let notificationCenter: NotificationCenter
    private var cancellables = Set<AnyCancellable>()

    public init(source: Source, notificationCenter: NotificationCenter = .default) {
        self.source = source
        self.notificationCenter = notificationCenter

        notificationCenter.publisher(for: .subscriptionDidChange).sink { [weak self] notification in

            guard let self else { return }

            guard let userInfo = notification.userInfo as? [AnyHashable: PrivacyProSubscription],
                  let subscription = userInfo[UserDefaultsCacheKey.subscription] else {
                DailyPixel.fireDailyAndCount(pixel: .privacyProSubscriptionMissing, withAdditionalParameters: self.sourceParam)
                return
            }

            if !subscription.isActive {
                DailyPixel.fireDaily(.privacyProSubscriptionExpired, withAdditionalParameters: self.sourceParam)
            }
        }.store(in: &cancellables)

        // Intercepting and sending a pixel every time a set of entitlements change. We are only interested in changes between full > empty. Any other combination is not possible
        notificationCenter.publisher(for: .entitlementsDidChange).sink {  [weak self] notification in

            guard let self else { return }

            guard (notification.object as? SubscriptionManagerV2) != nil else {
                // Sending pixel only for user entitlements, ignoring the Subscription entitlements coming from DefaultSubscriptionEndpointServiceV2
                return
            }

            let userInfo = notification.userInfo as? [AnyHashable: [Entitlement]] ?? [:]
            let entitlements = Set(userInfo[UserDefaultsCacheKey.subscriptionEntitlements] ?? [])
            let previousEntitlements = Set(userInfo[UserDefaultsCacheKey.subscriptionPreviousEntitlements] ?? [])

            Self.sendPixelForEntitlementChange(newEntitlement: entitlements, previousEntitlements: previousEntitlements, sourceParam: self.sourceParam)
        }.store(in: &cancellables)
    }

    static func sendPixelForEntitlementChange(newEntitlement: Set<Entitlement>,
                                              previousEntitlements: Set<Entitlement>,
                                              sourceParam: [String: String]) {
        let addedEntitlements = newEntitlement.subtracting(previousEntitlements)
        let removedEntitlements = previousEntitlements.subtracting(newEntitlement)
        
        if !addedEntitlements.isEmpty {
            DailyPixel.fireDailyAndCount(pixel: .privacyProEntitlementsAdded, withAdditionalParameters: sourceParam)
        }
        
        if !removedEntitlements.isEmpty {
            DailyPixel.fireDailyAndCount(pixel: .privacyProEntitlementsRemoved, withAdditionalParameters: sourceParam)
        }
        
        if addedEntitlements.isEmpty && removedEntitlements.isEmpty {
            Logger.subscription.debug("No changes in entitlements in notification, ignoring...")
        }
    }

    public func handle(pixelType: SubscriptionPixelType) {
        switch pixelType {
        case .invalidRefreshToken:
            DailyPixel.fireDailyAndCount(pixel: .privacyProInvalidRefreshTokenDetected, withAdditionalParameters: sourceParam)
        case .subscriptionIsActive:
            DailyPixel.fire(pixel: .privacyProSubscriptionActive)
        case .migrationFailed(let error):
            DailyPixel.fireDailyAndCount(pixel: .privacyProAuthV2MigrationFailed, withAdditionalParameters: [Defaults.errorKey: error.localizedDescription].merging(sourceParam) { $1 })
        case .migrationSucceeded:
            DailyPixel.fireDailyAndCount(pixel: .privacyProAuthV2MigrationSucceeded, withAdditionalParameters: sourceParam)
        case .getTokensError(let policy, let error):
            DailyPixel.fireDailyAndCount(pixel: .privacyProAuthV2GetTokensError, withAdditionalParameters: [Defaults.errorKey: error.localizedDescription,
                                                                                                            Defaults.policyCacheKey: policy.description].merging(sourceParam) { $1 })
        case .invalidRefreshTokenSignedOut:
            DailyPixel.fireDailyAndCount(pixel: .privacyProInvalidRefreshTokenSignedOut, withAdditionalParameters: sourceParam)
        case .invalidRefreshTokenRecovered:
            DailyPixel.fireDailyAndCount(pixel: .privacyProInvalidRefreshTokenRecovered, withAdditionalParameters: sourceParam)
        }
    }

}
