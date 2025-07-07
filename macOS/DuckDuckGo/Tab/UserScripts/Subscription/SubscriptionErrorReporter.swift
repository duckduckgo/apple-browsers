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
         cancelledByUser,
         accountCreationFailed,
         activeSubscriptionAlreadyPresent,
         otherPurchaseError,
         restoreFailedDueToNoSubscription,
         restoreFailedDueToExpiredSubscription,
         otherRestoreError

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
        case .cancelledByUser:
            return "Action was cancelled by the user."
        case .accountCreationFailed:
            return "Account creation failed. Please try again."
        case .activeSubscriptionAlreadyPresent:
            return "There is already an active subscription present."
        case .otherPurchaseError:
            return "A general purchase error has occurred."
        case .restoreFailedDueToNoSubscription:
            return "No subscription could be found."
        case .restoreFailedDueToExpiredSubscription:
            return "Your subscription has expired."
        case .otherRestoreError:
            return "A general restore error has occurred."
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
        case .failedToGetSubscriptionOptions:
            break
        case .failedToSetSubscription:
            break
        case .cancelledByUser:
            break
        case .accountCreationFailed:
            PixelKit.fire(PrivacyProPixel.privacyProPurchaseFailureAccountNotCreated, frequency: .legacyDailyAndCount)
        case .activeSubscriptionAlreadyPresent:
            break
        case .otherPurchaseError:
            PixelKit.fire(PrivacyProPixel.privacyProPurchaseFailureOther, frequency: .legacyDailyAndCount)
        case .restoreFailedDueToNoSubscription,
             .restoreFailedDueToExpiredSubscription:
            PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseStoreFailureNotFound, frequency: .legacyDailyAndCount)
        case .otherRestoreError:
            PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseStoreFailureOther, frequency: .legacyDailyAndCount)
        }
    }
}
