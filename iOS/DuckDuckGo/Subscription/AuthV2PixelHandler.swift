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
        static let entitlementsStateKey = "entitlementsState"
    }

    private let source: Source
    private var sourceParam: [String: String] {
        [Defaults.sourceKey: source.description]
    }
    private let notificationCenter: NotificationCenter = NotificationCenter.default
    private var cancellables = Set<AnyCancellable>()
    private var previousEntitlements: [Entitlement] = []

    init(source: Source) {
        self.source = source

        notificationCenter.publisher(for: .subscriptionDidChange).sink { notification in

            guard let userInfo = notification.userInfo as? [AnyHashable: PrivacyProSubscription],
                  let subscription = userInfo[UserDefaultsCacheKey.subscription] else {
                DailyPixel.fireDailyAndCount(pixel: .privacyProSubscriptionMissing, withAdditionalParameters: self.sourceParam)
                return
            }

            if !subscription.isActive {
                DailyPixel.fireDaily(.privacyProSubscriptionExpired, withAdditionalParameters: self.sourceParam)
            }
        }.store(in: &cancellables)

        notificationCenter.publisher(for: .entitlementsDidChange).sink { notification in

            guard (notification.object as? SubscriptionManagerV2) != nil else {
                // Sending pixel only for user entitlements, ignoring the Subscription entitlements coming from DefaultSubscriptionEndpointServiceV2
                return
            }

            let userInfo = notification.userInfo as? [AnyHashable: [Entitlement]]
            let entitlements = userInfo?[UserDefaultsCacheKey.subscriptionEntitlements] ?? []

            enum State: String {
                case added
                case removed
                case changed
            }

            let state: State
            switch (self.previousEntitlements.isEmpty, entitlements.isEmpty) {
                case (true, false): state = .added
                case (false, true): state = .removed
            case (false, false) where self.previousEntitlements.count != entitlements.count:
                state = .changed
            default:
                Logger.subscription.fault("Unexpected state")
                return
            }

            let params = [Defaults.entitlementsStateKey: state.rawValue].merging(self.sourceParam) { (_, new) in new } as? [String: String]
            DailyPixel.fireDailyAndCount(pixel: .privacyProEntitlementsDidChange, withAdditionalParameters: params ?? [:])
            self.previousEntitlements = entitlements
        }.store(in: &cancellables)
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
