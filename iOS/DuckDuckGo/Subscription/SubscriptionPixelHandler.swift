//
//  SubscriptionPixelHandler.swift
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

public struct SubscriptionPixelHandler: SubscriptionPixelHandling {

    public enum Source: String {
        case mainApp = "MainApp"
        case systemExtension = "SysExt"
    }

    let source: Source

    public struct Defaults {
        static let policyCacheKey = "policycache"
        static let sourceKey = "source"
    }

    public func handle(pixel: Subscription.SubscriptionPixelType) {
        let sourceParam = [Defaults.sourceKey: source.rawValue]
        switch pixel {
        case .invalidRefreshToken:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionInvalidRefreshTokenDetected,
                                         withAdditionalParameters: sourceParam)
        case .subscriptionIsActive:
            DailyPixel.fire(pixel: .subscriptionActive,
                            withAdditionalParameters: [AuthVersion.key: AuthVersion.v2.rawValue])
        case .migrationFailed(let error):
            DailyPixel.fireDailyAndCount(pixel: .subscriptionAuthV2MigrationFailed2,
                                         error: error,
                                         withAdditionalParameters: sourceParam)
        case .migrationSucceeded:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionAuthV2MigrationSucceeded,
                                         withAdditionalParameters: sourceParam)
        case .getTokensError(let policy, let error):
            DailyPixel.fireDailyAndCount(pixel: .subscriptionAuthV2GetTokensError2,
                                         error: error,
                                         withAdditionalParameters: [Defaults.policyCacheKey: policy.description].merging(sourceParam) { $1 })
        case .invalidRefreshTokenSignedOut:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionInvalidRefreshTokenSignedOut,
                                         withAdditionalParameters: sourceParam)
        case .invalidRefreshTokenRecovered:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionInvalidRefreshTokenRecovered,
                                         withAdditionalParameters: sourceParam)
        }
    }

    public func handle(pixel: Subscription.KeychainManager.Pixel) {
        let sourceParam = [Defaults.sourceKey: source.rawValue]
        switch pixel {
        case .deallocatedWithBacklog:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionKeychainManagerDeallocatedWithBacklog,
                                         withAdditionalParameters: sourceParam)
        case .dataAddedToTheBacklog:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionKeychainManagerDataAddedToTheBacklog,
                                         withAdditionalParameters: sourceParam)
        case .dataWroteFromBacklog:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionKeychainManagerDataWroteFromBacklog,
                                         withAdditionalParameters: sourceParam)
        case .failedToWriteDataFromBacklog:
            DailyPixel.fireDailyAndCount(pixel: .subscriptionKeychainManagerFailedToWriteDataFromBacklog,
                                         withAdditionalParameters: sourceParam)
        }
    }
}
