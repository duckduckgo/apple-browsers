//
//  SubscriptionEventReporter.swift
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
import Subscription
import os.log

enum SubscriptionError: LocalizedError {
    case purchaseFailed(Error),
         purchasePendingTransaction,
         missingEntitlements,
         failedToGetSubscriptionOptions,
         failedToSetSubscription,
         cancelledByUser,
         accountCreationFailed(Error),
         activeSubscriptionAlreadyPresent,
         otherPurchaseError,
         restoreFailedDueToNoSubscription,
         restoreFailedDueToExpiredSubscription,
         otherRestoreError

    var localizedDescription: String {
        switch self {
        case .purchaseFailed:
            return "Purchase process failed. Please try again."
        case .purchasePendingTransaction:
            return "Purchase is pending approval."
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

protocol SubscriptionEventReporter {
    func report(subscriptionActivationError: SubscriptionError)
    func report(subscriptionTierOptionEvent: PixelKitEvent)
}

struct DefaultSubscriptionEventReporter: SubscriptionEventReporter {

    func report(subscriptionActivationError: SubscriptionError) {

        Logger.subscription.error("Subscription purchase error: \(subscriptionActivationError.localizedDescription, privacy: .public)")

        switch subscriptionActivationError {
        case .purchaseFailed(let error):
            PixelKit.fire(SubscriptionPixel.subscriptionPurchaseFailureStoreError(error), frequency: .legacyDailyAndCount)
        case .purchasePendingTransaction:
            PixelKit.fire(SubscriptionPixel.subscriptionPurchaseFailureStoreError(AppStorePurchaseFlowError.transactionPendingAuthentication), frequency: .legacyDailyAndCount)
        case .missingEntitlements:
            PixelKit.fire(SubscriptionPixel.subscriptionPurchaseFailureBackendError, frequency: .legacyDailyAndCount)
        case .failedToGetSubscriptionOptions:
            break
        case .failedToSetSubscription:
            break
        case .cancelledByUser:
            break
        case .accountCreationFailed(let error):
            PixelKit.fire(SubscriptionPixel.subscriptionPurchaseFailureAccountNotCreated(error), frequency: .legacyDailyAndCount)
        case .activeSubscriptionAlreadyPresent:
            break
        case .otherPurchaseError:
            PixelKit.fire(SubscriptionPixel.subscriptionPurchaseFailureOther, frequency: .legacyDailyAndCount)
        case .restoreFailedDueToNoSubscription,
             .restoreFailedDueToExpiredSubscription:
            PixelKit.fire(SubscriptionPixel.subscriptionRestorePurchaseStoreFailureNotFound, frequency: .legacyDailyAndCount)
        case .otherRestoreError:
            PixelKit.fire(SubscriptionPixel.subscriptionRestorePurchaseStoreFailureOther, frequency: .legacyDailyAndCount)
        }
    }

    func report(subscriptionTierOptionEvent: PixelKitEvent) {
        PixelKit.fire(subscriptionTierOptionEvent)
    }
}
