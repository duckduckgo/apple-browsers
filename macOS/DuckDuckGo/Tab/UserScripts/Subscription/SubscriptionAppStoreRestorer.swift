//
//  SubscriptionAppStoreRestorer.swift
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

import AppKit
import Subscription
import SubscriptionUI
import enum StoreKit.StoreKitError
import PixelKit
import PrivacyConfig

@available(macOS 12.0, *)
protocol SubscriptionAppStoreRestorer {
    var uiHandler: SubscriptionUIHandling { get }
    func restoreAppStoreSubscription() async
}

@available(macOS 12.0, *)
struct DefaultSubscriptionAppStoreRestorerV2: SubscriptionAppStoreRestorer {
    private let subscriptionManager: SubscriptionManager
    private let subscriptionErrorReporter: SubscriptionEventReporter
    private let appStoreRestoreFlow: AppStoreRestoreFlow
    private let featureFlagger: FeatureFlagger

    // Wide Event
    private let instrumentation: SubscriptionInstrumentation
    private let restoreOrigin: String

    let uiHandler: SubscriptionUIHandling

    public init(subscriptionManager: SubscriptionManager,
                subscriptionErrorReporter: SubscriptionEventReporter = DefaultSubscriptionEventReporter(),
                appStoreRestoreFlow: AppStoreRestoreFlow,
                uiHandler: SubscriptionUIHandling,
                restoreOrigin: String,
                instrumentation: SubscriptionInstrumentation = Application.appDelegate.subscriptionInstrumentation,
                featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger
    ) {
        self.subscriptionManager = subscriptionManager
        self.subscriptionErrorReporter = subscriptionErrorReporter
        self.appStoreRestoreFlow = appStoreRestoreFlow
        self.uiHandler = uiHandler
        self.restoreOrigin = restoreOrigin
        self.instrumentation = instrumentation
        self.featureFlagger = featureFlagger
    }

    func restoreAppStoreSubscription() async {
        await uiHandler.presentProgressViewController(withTitle: UserText.restoringSubscriptionTitle)

        do {
            instrumentation.restoreStoreStarted(origin: restoreOrigin)
            try await subscriptionManager.storePurchaseManager().syncAppleIDAccount()
            await continueRestore()
        } catch {
            await uiHandler.dismissProgressViewController()

            switch error as? StoreKitError {
            case .some(.userCancelled):
                instrumentation.restoreStoreCancelled()
            default:
                let alertResponse = await uiHandler.show(alertType: .appleIDSyncFailed, text: error.localizedDescription)
                if alertResponse == .alertFirstButtonReturn {
                    await uiHandler.presentProgressViewController(withTitle: UserText.restoringSubscriptionTitle)
                    await continueRestore()
                } else {
                    // User clicked cancel on the alert
                    instrumentation.restoreStoreCancelled()
                }
            }
        }
    }

    private func continueRestore() async {
        let result = await appStoreRestoreFlow.restoreAccountFromPastPurchase()
        await uiHandler.dismissProgressViewController()
        switch result {
        case .success:
            PixelKit.fire(SubscriptionPixel.subscriptionRestorePurchaseStoreSuccess, frequency: .legacyDailyAndCount)
            instrumentation.restoreStoreSucceeded()
        case .failure(let error):
            switch error {
            case .missingAccountOrTransactions:
                subscriptionErrorReporter.report(subscriptionActivationError: .restoreFailedDueToNoSubscription)
                instrumentation.restoreStoreFailed(error: error)
                await showSubscriptionNotFoundAlert()
            case .subscriptionExpired:
                subscriptionErrorReporter.report(subscriptionActivationError: .restoreFailedDueToExpiredSubscription)
                instrumentation.restoreStoreFailed(error: error)
                await showSubscriptionInactiveAlert()
            case .failedToObtainAccessToken, .failedToFetchAccountDetails, .failedToFetchSubscriptionDetails:
                subscriptionErrorReporter.report(subscriptionActivationError: .otherRestoreError)
                instrumentation.restoreStoreFailed(error: error)
                await showSomethingWentWrongAlert()
            case .pastTransactionAuthenticationError:
                subscriptionErrorReporter.report(subscriptionActivationError: .otherRestoreError)
                instrumentation.restoreStoreFailed(error: error)
                await showSubscriptionNotFoundAlert()
            }
        }
    }

    // MARK: - UI interactions

    private func showSomethingWentWrongAlert() async {
        await uiHandler.show(alertType: .somethingWentWrong)
    }

    private func showSubscriptionNotFoundAlert() async {
        switch await uiHandler.show(alertType: .subscriptionNotFound) {
        case .alertFirstButtonReturn:
            let url = subscriptionManager.url(for: .purchase)
            await uiHandler.showTab(with: .subscription(url))
            PixelKit.fire(SubscriptionPixel.subscriptionOfferScreenImpression)
        default: return
        }
    }

    private func showSubscriptionInactiveAlert() async {
        switch await uiHandler.show(alertType: .subscriptionInactive) {
        case .alertFirstButtonReturn:
            let url = subscriptionManager.url(for: .purchase)
            await uiHandler.showTab(with: .subscription(url))
            PixelKit.fire(SubscriptionPixel.subscriptionOfferScreenImpression)
        default: return
        }
    }

}
