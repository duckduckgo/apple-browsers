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
import BrowserServicesKit

@available(macOS 12.0, *)
protocol SubscriptionAppStoreRestorer {
    var uiHandler: SubscriptionUIHandling { get }
    func restoreAppStoreSubscription() async
}

@available(macOS 12.0, *)
struct DefaultSubscriptionAppStoreRestorer: SubscriptionAppStoreRestorer {
    private let subscriptionManager: SubscriptionManager
    private let subscriptionErrorReporter: SubscriptionErrorReporter
    private let appStoreRestoreFlow: AppStoreRestoreFlow
    let uiHandler: SubscriptionUIHandling

    public init(subscriptionManager: SubscriptionManager,
                subscriptionErrorReporter: SubscriptionErrorReporter = DefaultSubscriptionErrorReporter(),
                appStoreRestoreFlow: AppStoreRestoreFlow,
                uiHandler: SubscriptionUIHandling) {
        self.subscriptionManager = subscriptionManager
        self.subscriptionErrorReporter = subscriptionErrorReporter
        self.appStoreRestoreFlow = appStoreRestoreFlow
        self.uiHandler = uiHandler
    }

    func restoreAppStoreSubscription() async {
        await uiHandler.presentProgressViewController(withTitle: UserText.restoringSubscriptionTitle)

        do {
            try await subscriptionManager.storePurchaseManager().syncAppleIDAccount()
            await continueRestore()
        } catch {
            await uiHandler.dismissProgressViewController()

            switch error as? StoreKitError {
            case .some(.userCancelled):
                break
            default:
                let alertResponse = await uiHandler.show(alertType: .appleIDSyncFailed, text: error.localizedDescription)
                if alertResponse == .alertFirstButtonReturn {
                    await uiHandler.presentProgressViewController(withTitle: UserText.restoringSubscriptionTitle)
                    await continueRestore()
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
        case .failure(let error):
            switch error {
            case .missingAccountOrTransactions:
                subscriptionErrorReporter.report(subscriptionActivationError: .restoreFailedDueToNoSubscription)
                await showSubscriptionNotFoundAlert()
            case .subscriptionExpired:
                subscriptionErrorReporter.report(subscriptionActivationError: .restoreFailedDueToExpiredSubscription)
                await showSubscriptionInactiveAlert()
            case .failedToObtainAccessToken, .failedToFetchAccountDetails, .failedToFetchSubscriptionDetails:
                subscriptionErrorReporter.report(subscriptionActivationError: .otherRestoreError)
                await showSomethingWentWrongAlert()
            case .pastTransactionAuthenticationError:
                subscriptionErrorReporter.report(subscriptionActivationError: .otherRestoreError)
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

@available(macOS 12.0, *)
struct DefaultSubscriptionAppStoreRestorerV2: SubscriptionAppStoreRestorer {
    private let subscriptionManager: SubscriptionManagerV2
    private let subscriptionErrorReporter: SubscriptionErrorReporter
    private let appStoreRestoreFlow: AppStoreRestoreFlowV2
    private let featureFlagger: FeatureFlagger

    // Wide Event
    private let wideEvent: WideEventManaging
    private let subscriptionRestoreWideEventData: SubscriptionRestoreWideEventData?
    private var isSubscriptionRestoreWidePixelMeasurementEnabled: Bool {
        featureFlagger.isFeatureOn(.subscriptionRestoreWidePixelMeasurement)
    }

    let uiHandler: SubscriptionUIHandling

    public init(subscriptionManager: SubscriptionManagerV2,
                subscriptionErrorReporter: SubscriptionErrorReporter = DefaultSubscriptionErrorReporter(),
                appStoreRestoreFlow: AppStoreRestoreFlowV2,
                uiHandler: SubscriptionUIHandling,
                subscriptionRestoreWideEventData: SubscriptionRestoreWideEventData? = nil,
                featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger,
                wideEvent: WideEventManaging = Application.appDelegate.wideEvent
    ) {
        self.subscriptionManager = subscriptionManager
        self.subscriptionErrorReporter = subscriptionErrorReporter
        self.appStoreRestoreFlow = appStoreRestoreFlow
        self.uiHandler = uiHandler
        self.subscriptionRestoreWideEventData = subscriptionRestoreWideEventData
        self.featureFlagger = featureFlagger
        self.wideEvent = wideEvent
    }

    func restoreAppStoreSubscription() async {
        await uiHandler.presentProgressViewController(withTitle: UserText.restoringSubscriptionTitle)

        do {
            if isSubscriptionRestoreWidePixelMeasurementEnabled, let data = subscriptionRestoreWideEventData {
                data.appleAccountRestoreDuration = WideEvent.MeasuredInterval.startingNow()
                wideEvent.startFlow(data)
            }
            try await subscriptionManager.storePurchaseManager().syncAppleIDAccount()
            await continueRestore()
        } catch {
            await uiHandler.dismissProgressViewController()

            switch error as? StoreKitError {
            case .some(.userCancelled):
                if isSubscriptionRestoreWidePixelMeasurementEnabled, let data = subscriptionRestoreWideEventData {
                    wideEvent.discardFlow(data)
                }
            default:
                let alertResponse = await uiHandler.show(alertType: .appleIDSyncFailed, text: error.localizedDescription)
                if alertResponse == .alertFirstButtonReturn {
                    await uiHandler.presentProgressViewController(withTitle: UserText.restoringSubscriptionTitle)
                    await continueRestore()
                } else if isSubscriptionRestoreWidePixelMeasurementEnabled, let data = subscriptionRestoreWideEventData {
                    // User clicked cancel on the alert
                    wideEvent.discardFlow(data)
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
            if isSubscriptionRestoreWidePixelMeasurementEnabled, let data = subscriptionRestoreWideEventData {
                data.appleAccountRestoreDuration?.complete()
                wideEvent.completeFlow(data, status: .success, onComplete: { _, _ in })
            }
        case .failure(let error):
            switch error {
            case .missingAccountOrTransactions:
                subscriptionErrorReporter.report(subscriptionActivationError: .restoreFailedDueToNoSubscription)
                markSubscriptionRestoreWideEventAsFailure(with: error)
                await showSubscriptionNotFoundAlert()
            case .subscriptionExpired:
                subscriptionErrorReporter.report(subscriptionActivationError: .restoreFailedDueToExpiredSubscription)
                markSubscriptionRestoreWideEventAsFailure(with: error)
                await showSubscriptionInactiveAlert()
            case .failedToObtainAccessToken, .failedToFetchAccountDetails, .failedToFetchSubscriptionDetails:
                subscriptionErrorReporter.report(subscriptionActivationError: .otherRestoreError)
                markSubscriptionRestoreWideEventAsFailure(with: error)
                await showSomethingWentWrongAlert()
            case .pastTransactionAuthenticationError:
                subscriptionErrorReporter.report(subscriptionActivationError: .otherRestoreError)
                markSubscriptionRestoreWideEventAsFailure(with: error)
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

    // MARK: - Wide Pixel Helper

    private func markSubscriptionRestoreWideEventAsFailure(with error: Error) {
        guard isSubscriptionRestoreWidePixelMeasurementEnabled, let data = subscriptionRestoreWideEventData else { return }
        data.appleAccountRestoreDuration?.complete()
        data.errorData = .init(error: error)
        wideEvent.completeFlow(data, status: .failure, onComplete: { _, _ in })
    }
}
