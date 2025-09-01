//
//  SubscriptionPixelHandler.swift
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

public struct SubscriptionPixelHandler: SubscriptionPixelHandling {

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

    public func handle(pixel: Subscription.SubscriptionPixelType) {
        switch pixel {
        case .invalidRefreshToken:
            PixelKit.fire(PrivacyProPixel.privacyProInvalidRefreshTokenDetected(source), frequency: .dailyAndCount)
        case .subscriptionIsActive:
            PixelKit.fire(PrivacyProPixel.privacyProSubscriptionActive(AuthVersion.v2), frequency: .legacyDaily)
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

    public func handle(pixel: Subscription.KeychainManager.Pixel) {
        switch pixel {
        case .deallocatedWithBacklog:
            PixelKit.fire(PrivacyProPixel.privacyProKeychainManagerDeallocatedWithBacklog(source), frequency: .dailyAndCount)
        case .dataAddedToTheBacklog:
            PixelKit.fire(PrivacyProPixel.privacyProKeychainManagerDataAddedToTheBacklog(source), frequency: .dailyAndCount)
        case .dataWroteFromBacklog:
            PixelKit.fire(PrivacyProPixel.privacyProKeychainManagerDataWroteFromBacklog(source), frequency: .dailyAndCount)
        case .failedToWriteDataFromBacklog:
            PixelKit.fire(PrivacyProPixel.privacyProKeychainManagerFailedToWriteDataFromBacklog(source), frequency: .dailyAndCount)
        }
    }
}
