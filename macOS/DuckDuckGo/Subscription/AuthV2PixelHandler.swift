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
    private let notificationCenter: NotificationCenter = NotificationCenter.default
    private var cancellables = Set<AnyCancellable>()
    private var previousEntitlements: [Entitlement] = []

    init(source: Source) {
        self.source = source

        notificationCenter.publisher(for: .subscriptionDidChange).sink { param in

            guard let userInfo = param.userInfo as? [AnyHashable: PrivacyProSubscription],
                  let subscription = userInfo[UserDefaultsCacheKey.subscription] else {
                PixelKit.fire(PrivacyProPixel.privacyProSubscriptionMissing(source), frequency: .dailyAndCount)
                return
            }

            if !subscription.isActive {
                PixelKit.fire(PrivacyProPixel.privacyProSubscriptionExpired(source), frequency: .daily)
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
            }

            let state: State
            switch (self.previousEntitlements.isEmpty, entitlements.isEmpty) {
            case (true, false): state = .added
            case (false, true): state = .removed
            default:
                Logger.subscription.fault("Unexpected state")
                return
            }
            PixelKit.fire(PrivacyProPixel.privacyProEntitlementsDidChange(source, state.rawValue), frequency: .dailyAndCount)
            self.previousEntitlements = entitlements
        }.store(in: &cancellables)
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
