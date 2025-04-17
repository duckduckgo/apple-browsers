//
//  SubscriptionErrorReporter.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Common
import PixelKit
import os.log

enum SubscriptionError: LocalizedError {
    case purchaseFailed,
         missingEntitlements,
         failedToGetSubscriptionOptions,
         failedToSetSubscription,
         failedToRestorePastPurchase,
         subscriptionNotFound,
         subscriptionExpired,
         hasActiveSubscription,
         cancelledByUser,
         accountCreationFailed,
         activeSubscriptionAlreadyPresent,
         generalError

    var localizedDescription: String {
        switch self {
        case .purchaseFailed:
            return "Purchase process failed. Please try again."
        case .missingEntitlements:
            return "Required entitlements are missing."
        case .failedToGetSubscriptionOptions:
            return "Unable to retrieve subscription options."
        case .failedToSetSubscription:
            return "Failed to set the subscription."
        case .failedToRestorePastPurchase:
            return "Failed to restore your past purchase."
        case .subscriptionNotFound:
            return "No subscription could be found."
        case .subscriptionExpired:
            return "Your subscription has expired."
        case .hasActiveSubscription:
            return "You already have an active subscription."
        case .cancelledByUser:
            return "Action was cancelled by the user."
        case .accountCreationFailed:
            return "Account creation failed. Please try again."
        case .activeSubscriptionAlreadyPresent:
            return "There is already an active subscription present."
        case .generalError:
            return "A general error has occurred."
        }
    }
}

protocol SubscriptionErrorReporter {
    func report(subscriptionActivationError: SubscriptionError)
}

struct DefaultSubscriptionErrorReporter: SubscriptionErrorReporter {

    func report(subscriptionActivationError: SubscriptionError) {

        Logger.subscription.error("Subscription purchase error: \(subscriptionActivationError.localizedDescription, privacy: .public)")

        switch subscriptionActivationError {
        case .purchaseFailed:
            PixelKit.fire(PrivacyProPixel.privacyProPurchaseFailureStoreError, frequency: .legacyDailyAndCount)
        case .missingEntitlements:
            PixelKit.fire(PrivacyProPixel.privacyProPurchaseFailureBackendError, frequency: .legacyDailyAndCount)
        case .failedToGetSubscriptionOptions: break
        case .failedToSetSubscription: break
        case .failedToRestorePastPurchase: break
        case .subscriptionNotFound:
            PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseStoreFailureNotFound, frequency: .legacyDailyAndCount)
        case .subscriptionExpired: break
        case .hasActiveSubscription: break
        case .cancelledByUser: break
        case .accountCreationFailed:
            PixelKit.fire(PrivacyProPixel.privacyProPurchaseFailureAccountNotCreated, frequency: .legacyDailyAndCount)
        case .activeSubscriptionAlreadyPresent: break
        case .generalError: break
        }
    }
}
