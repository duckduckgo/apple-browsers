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
    let pixelKit: PixelKit?

    public func handle(pixel: Subscription.SubscriptionPixelType) {
        switch pixel {
        case .invalidRefreshToken:
            pixelKit?.fire(SubscriptionPixel.subscriptionInvalidRefreshTokenDetected(source), frequency: .dailyAndCount)
        case .subscriptionIsActive:
            pixelKit?.fire(SubscriptionPixel.subscriptionActive(AuthVersion.v2), frequency: .legacyDaily)
        case .getTokensError(let policy, let error):
            pixelKit?.fire(SubscriptionPixel.subscriptionAuthV2GetTokensError(policy, source, error), frequency: .dailyAndCount)
        case .invalidRefreshTokenSignedOut:
            pixelKit?.fire(SubscriptionPixel.subscriptionInvalidRefreshTokenSignedOut, frequency: .dailyAndCount)
        case .invalidRefreshTokenRecovered:
            pixelKit?.fire(SubscriptionPixel.subscriptionInvalidRefreshTokenRecovered, frequency: .dailyAndCount)
        case .purchaseSuccessAfterPendingTransaction:
            pixelKit?.fire(SubscriptionPixel.subscriptionPurchaseSuccessAfterPendingTransaction(source), frequency: .dailyAndCount)
        case .pendingTransactionApproved:
            pixelKit?.fire(SubscriptionPixel.subscriptionPendingTransactionApproved(source), frequency: .dailyAndCount)
        }
    }

    public func handle(pixel: Subscription.KeychainManager.Pixel) {
        switch pixel {
        case .deallocatedWithBacklog:
            pixelKit?.fire(SubscriptionPixel.subscriptionKeychainManagerDeallocatedWithBacklog(source), frequency: .dailyAndCount)
        case .dataAddedToTheBacklog:
            pixelKit?.fire(SubscriptionPixel.subscriptionKeychainManagerDataAddedToTheBacklog(source), frequency: .dailyAndCount)
        case .dataWroteFromBacklog:
            pixelKit?.fire(SubscriptionPixel.subscriptionKeychainManagerDataWroteFromBacklog(source), frequency: .dailyAndCount)
        case .failedToWriteDataFromBacklog:
            pixelKit?.fire(SubscriptionPixel.subscriptionKeychainManagerFailedToWriteDataFromBacklog(source), frequency: .dailyAndCount)
        }
    }
}
