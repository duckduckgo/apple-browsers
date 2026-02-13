//
//  SubscriptionPagesUseSubscriptionFeature.swift
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
import BrowserServicesKit
import Common
import WebKit
import UserScript
import Subscription
import SubscriptionUI
import PixelKit
import os.log
import Freemium
import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import Networking

// https://app.asana.com/0/0/1209325145462549
struct SubscriptionValuesV2: Decodable {
    let accessToken: String
    let refreshToken: String
}

public struct AccessTokenValue: Encodable {
    let accessToken: String
}

// https://app.asana.com/0/1205842942115003/1209254337758531/f
public struct GetFeatureValue: Encodable {
    let useUnifiedFeedback: Bool = true
    let useSubscriptionsAuthV2: Bool = true
    let usePaidDuckAi: Bool
    let useAlternateStripePaymentFlow: Bool
    let useGetSubscriptionTierOptions: Bool = true
}

/// Use Subscription sub-feature
final class SubscriptionPagesUseSubscriptionFeature: Subfeature {

    private enum OriginDomains {
        static let duckduckgo = "duckduckgo.com"
    }

    weak var broker: UserScriptMessageBroker?

    let featureName = "useSubscription"
    lazy var messageOriginPolicy: MessageOriginPolicy = .only(rules: [
        HostnameMatchingRule.makeExactRule(for: subscriptionManager.url(for: .baseURL)) ?? .exact(hostname: OriginDomains.duckduckgo)
    ])

    let subscriptionManager: SubscriptionManager
    var subscriptionPlatform: SubscriptionEnvironment.PurchasePlatform { subscriptionManager.currentEnvironment.purchasePlatform }
    let stripePurchaseFlow: any StripePurchaseFlow
    let subscriptionEventReporter: SubscriptionEventReporter
    let subscriptionSuccessPixelHandler: SubscriptionAttributionPixelHandling
    let uiHandler: SubscriptionUIHandling
    let subscriptionFeatureAvailability: SubscriptionFeatureAvailability
    private var freemiumDBPUserStateManager: FreemiumDBPUserStateManager
    private let notificationCenter: NotificationCenter
    /// The `DataBrokerProtectionFreemiumPixelHandler` instance used to fire pixels
    private let dataBrokerProtectionFreemiumPixelHandler: EventMapping<DataBrokerProtectionFreemiumPixels>

    private let aiChatURL: URL

    // Wide Event
    private let wideEvent: WideEventManaging
    private var purchaseWideEventData: SubscriptionPurchaseWideEventData?
    private var restoreEmailOfferPageWideEventData: SubscriptionRestoreWideEventData?
    private var restoreEmailAppSettingsWideEventData: SubscriptionRestoreWideEventData?
    private var planChangeWideEventData: SubscriptionPlanChangeWideEventData?

    private let pendingTransactionHandler: PendingTransactionHandling
    private let flowPerformer: any SubscriptionFlowsExecuting

    public init(subscriptionManager: SubscriptionManager,
                subscriptionSuccessPixelHandler: SubscriptionAttributionPixelHandling = SubscriptionAttributionPixelHandler(),
                stripePurchaseFlow: StripePurchaseFlow,
                uiHandler: SubscriptionUIHandling,
                subscriptionFeatureAvailability: SubscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(),
                freemiumDBPUserStateManager: FreemiumDBPUserStateManager = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp),
                notificationCenter: NotificationCenter = .default,
                dataBrokerProtectionFreemiumPixelHandler: EventMapping<DataBrokerProtectionFreemiumPixels> = DataBrokerProtectionFreemiumPixelHandler(),
                aiChatURL: URL,
                wideEvent: WideEventManaging,
                subscriptionEventReporter: SubscriptionEventReporter = DefaultSubscriptionEventReporter(),
                pendingTransactionHandler: PendingTransactionHandling,
                flowPerformer: any SubscriptionFlowsExecuting) {
        self.subscriptionManager = subscriptionManager
        self.stripePurchaseFlow = stripePurchaseFlow
        self.subscriptionSuccessPixelHandler = subscriptionSuccessPixelHandler
        self.uiHandler = uiHandler
        self.aiChatURL = aiChatURL
        self.subscriptionFeatureAvailability = subscriptionFeatureAvailability
        self.freemiumDBPUserStateManager = freemiumDBPUserStateManager
        self.notificationCenter = notificationCenter
        self.dataBrokerProtectionFreemiumPixelHandler = dataBrokerProtectionFreemiumPixelHandler
        self.wideEvent = wideEvent
        self.subscriptionEventReporter = subscriptionEventReporter
        self.pendingTransactionHandler = pendingTransactionHandler
        self.flowPerformer = flowPerformer
    }

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    struct Handlers {
        static let setAuthTokens = "setAuthTokens"
        static let getAuthAccessToken = "getAuthAccessToken"
        static let getFeatureConfig = "getFeatureConfig"
        static let backToSettings = "backToSettings"
        static let getSubscriptionTierOptions = "getSubscriptionTierOptions"
        static let subscriptionSelected = "subscriptionSelected"
        static let subscriptionChangeSelected = "subscriptionChangeSelected"
        static let activateSubscription = "activateSubscription"
        static let featureSelected = "featureSelected"
        static let completeStripePayment = "completeStripePayment"
        // Pixels related events
        static let subscriptionsMonthlyPriceClicked = "subscriptionsMonthlyPriceClicked"
        static let subscriptionsYearlyPriceClicked = "subscriptionsYearlyPriceClicked"
        static let subscriptionsUnknownPriceClicked = "subscriptionsUnknownPriceClicked"
        static let subscriptionsAddEmailSuccess = "subscriptionsAddEmailSuccess"
        static let subscriptionsWelcomeAddEmailClicked = "subscriptionsWelcomeAddEmailClicked"
        static let subscriptionsWelcomeFaqClicked = "subscriptionsWelcomeFaqClicked"
        static let getAccessToken = "getAccessToken"
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        Logger.subscription.debug("WebView handler: \(methodName)")

        switch methodName {
        case Handlers.setAuthTokens: return setAuthTokens
        case Handlers.getAuthAccessToken: return getAuthAccessToken
        case Handlers.getFeatureConfig: return getFeatureConfig
        case Handlers.backToSettings: return backToSettings
        case Handlers.getSubscriptionTierOptions: return getSubscriptionTierOptions
        case Handlers.subscriptionSelected: return subscriptionSelected
        case Handlers.subscriptionChangeSelected: return subscriptionChangeSelected
        case Handlers.activateSubscription: return activateSubscription
        case Handlers.featureSelected: return featureSelected
        case Handlers.completeStripePayment: return completeStripePayment
            // Pixel related events
        case Handlers.subscriptionsMonthlyPriceClicked: return subscriptionsMonthlyPriceClicked
        case Handlers.subscriptionsYearlyPriceClicked: return subscriptionsYearlyPriceClicked
        case Handlers.subscriptionsUnknownPriceClicked: return subscriptionsUnknownPriceClicked
        case Handlers.subscriptionsAddEmailSuccess: return subscriptionsAddEmailSuccess
        case Handlers.subscriptionsWelcomeAddEmailClicked: return subscriptionsWelcomeAddEmailClicked
        case Handlers.subscriptionsWelcomeFaqClicked: return subscriptionsWelcomeFaqClicked
        case Handlers.getAccessToken: return getAccessToken
        default:
            Logger.subscription.error("Unknown web message: \(methodName, privacy: .public)")
            return nil
        }
    }

    // MARK: - Subscription + Auth

    func setAuthTokens(params: Any, original: WKScriptMessage) async throws -> Encodable? {

        PixelKit.fire(SubscriptionPixel.subscriptionRestorePurchaseEmailSuccess, frequency: .legacyDailyAndCount)

        retrieveRestoreEmailAppSettingsWideEventDataIfNeeded()
        let restoreDataList: [SubscriptionRestoreWideEventData] = [
            self.restoreEmailAppSettingsWideEventData,
            self.restoreEmailOfferPageWideEventData].compactMap { $0 }

        guard let subscriptionValues: SubscriptionValuesV2 = CodableHelper.decode(from: params) else {
            Logger.subscription.fault("SubscriptionPagesUserScript: expected JSON representation of SubscriptionValues")
            markEmailAddressRestoreAsFailure(data: restoreDataList)
            assertionFailure("SubscriptionPagesUserScript: expected JSON representation of SubscriptionValues")
            return nil
        }

        // Clear subscription Cache
        subscriptionManager.clearSubscriptionCache()

        guard !subscriptionValues.accessToken.isEmpty, !subscriptionValues.refreshToken.isEmpty else {
            Logger.subscription.fault("Empty access token or refresh token provided")
            markEmailAddressRestoreAsFailure(data: restoreDataList)
            return nil
        }

        do {
            try await subscriptionManager.adopt(accessToken: subscriptionValues.accessToken, refreshToken: subscriptionValues.refreshToken)
            try await subscriptionManager.getSubscription(cachePolicy: .remoteFirst)
            markEmailAddressRestoreAsSuccess(data: restoreDataList)
            Logger.subscription.log("Subscription retrieved")
        } catch {
            markEmailAddressRestoreAsFailure(data: restoreDataList, with: error)
            Logger.subscription.error("Failed to adopt V2 tokens: \(error, privacy: .public)")
        }
        return nil
    }

    func getAuthAccessToken(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        let tokenContainer = try? await subscriptionManager.getTokenContainer(policy: .localValid)
        return AccessTokenValue(accessToken: tokenContainer?.accessToken ?? "")
    }

    func getFeatureConfig(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        return GetFeatureValue(usePaidDuckAi: subscriptionFeatureAvailability.isPaidAIChatEnabled,
                               useAlternateStripePaymentFlow: subscriptionFeatureAvailability.isSupportsAlternateStripePaymentFlowEnabled
        )
    }

    // MARK: -

    func backToSettings(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        _ = try? await subscriptionManager.getTokenContainer(policy: .localForceRefresh)
        DispatchQueue.main.async { [weak self] in
            self?.notificationCenter.post(name: .subscriptionPageCloseAndOpenPreferences, object: self)
        }
        return nil
    }

    func getSubscriptionTierOptions(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        subscriptionEventReporter.report(subscriptionTierOptionEvent: SubscriptionPixel.subscriptionTierOptionsRequested)

        let result = await subscriptionManager.subscriptionTierOptions(
            includeProTier: subscriptionFeatureAvailability.isProTierPurchaseEnabled
        )

        switch result {
        case .success(let subscriptionTierOptions):
            // TEMPORARY: Check if Pro tier was unexpectedly returned
            let hasProTier = subscriptionTierOptions.products.contains { $0.tier == .pro }
            if hasProTier && !subscriptionFeatureAvailability.isProTierPurchaseEnabled {
                subscriptionEventReporter.report(subscriptionTierOptionEvent: SubscriptionPixel.subscriptionTierOptionsUnexpectedProTier)
            }

            subscriptionEventReporter.report(subscriptionTierOptionEvent: SubscriptionPixel.subscriptionTierOptionsSuccess)

            guard subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed else { return subscriptionTierOptions.withoutPurchaseOptions() }
            return subscriptionTierOptions

        case .failure(let error):
            Logger.subscription.error("Failed to get tier options: \(String(describing: error), privacy: .public)")

            subscriptionEventReporter.report(subscriptionTierOptionEvent: SubscriptionPixel.subscriptionTierOptionsFailure(error: error))

            return SubscriptionTierOptions.empty
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func subscriptionSelected(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        PixelKit.fire(SubscriptionPixel.subscriptionPurchaseAttempt, frequency: .legacyDailyAndCount)
        struct SubscriptionSelection: Decodable {
            let id: String
        }

        let message = original

        let origin = await setPixelOrigin(from: message)

        if subscriptionManager.currentEnvironment.purchasePlatform == .appStore {
            if #available(macOS 12.0, *) {
                // 1: Parse subscription selection from message object
                guard let subscriptionSelection: SubscriptionSelection = CodableHelper.decode(from: params) else {
                    assertionFailure("SubscriptionPagesUserScript: expected JSON representation of SubscriptionSelection")
                    subscriptionEventReporter.report(subscriptionActivationError: .otherPurchaseError)
                    await uiHandler.dismissProgressViewController()
                    return nil
                }

                Logger.subscription.log("[Purchase] Starting purchase for: \(subscriptionSelection.id, privacy: .public)")

                // 2: Show purchase progress UI to user
                await uiHandler.presentProgressViewController(withTitle: UserText.purchasingSubscriptionTitle)

                // 3: Check for active subscriptions
                if await subscriptionManager.storePurchaseManager().hasActiveSubscription() {
                    // Sandbox note: Looks like our BE is not receiving updates when a subscription transitions from grace period to expired, so during testing we can end up with a subscription in grace period and we will not be able to purchase a new one, only restore it because Transaction.currentEntitlements will not return the subscription to restore.
                    PixelKit.fire(SubscriptionPixel.subscriptionRestoreAfterPurchaseAttempt)
                    Logger.subscription.log("[Purchase] Found active subscription during purchase")
                    subscriptionEventReporter.report(subscriptionActivationError: .activeSubscriptionAlreadyPresent)
                    await showSubscriptionFoundAlert(originalMessage: message)
                    await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "canceled"))
                    return nil
                }

                // 4: Configure wide event and start the flow
                let freeTrialEligible = subscriptionManager.storePurchaseManager().isUserEligibleForFreeTrial()
                let data = SubscriptionPurchaseWideEventData(purchasePlatform: .appStore,
                                                             subscriptionIdentifier: subscriptionSelection.id,
                                                             freeTrialEligible: freeTrialEligible,
                                                             contextData: WideEventContextData(name: origin ?? ""))
                self.purchaseWideEventData = data
                wideEvent.startFlow(data)

                // 5: No existing subscription was found, so proceed with the remaining purchase flow
                let purchaseTransactionJWS: String
                let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(subscriptionManager: subscriptionManager,
                                                                       storePurchaseManager: subscriptionManager.storePurchaseManager())
                let appStorePurchaseFlow = DefaultAppStorePurchaseFlow(subscriptionManager: subscriptionManager,
                                                                         storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                         appStoreRestoreFlow: appStoreRestoreFlow,
                                                                         wideEvent: wideEvent)
                // 6: Execute App Store purchase (account creation + StoreKit transaction) and handle the result
                Logger.subscription.log("[Purchase] Purchasing")
                let purchaseResult = await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelection.id, includeProTier: subscriptionFeatureAvailability.isProTierPurchaseEnabled)

                switch purchaseResult {
                case .success(let result):
                    purchaseTransactionJWS = result.transactionJWS

                    // Account creation is only one piece of the purchase function's job, so we extract the creation
                    // duration from the result rather than time the execution of the entire call.
                    if let accountCreationDuration = result.accountCreationDuration {
                        data.createAccountDuration = accountCreationDuration
                    }
                case .failure(let error):
                    reportPurchaseFlowError(error)

                    if error != .cancelledByUser {
                        await showSomethingWentWrongAlert()
                    } else {
                        await uiHandler.dismissProgressViewController()
                    }

                    await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "canceled"))

                    // Complete the wide event flow if the purchase step fails:
                    if error == .cancelledByUser {
                        wideEvent.completeFlow(data, status: .cancelled, onComplete: { _, _ in })
                    } else if error == .activeSubscriptionAlreadyPresent {
                        // If we found a subscription, then this is not a purchase flow - discard the purchase pixel.
                        if let data = self.purchaseWideEventData {
                            wideEvent.discardFlow(data)
                            self.purchaseWideEventData = nil
                        }
                    } else {
                        switch error {
                        case .accountCreationFailed(let creationError):
                            data.markAsFailed(at: .accountCreate, error: creationError)
                        case .purchaseFailed(let purchaseError):
                            data.markAsFailed(at: .accountPayment, error: purchaseError)
                        case .internalError(let internalError):
                            data.markAsFailed(at: .accountCreate, error: internalError ?? error)
                        default:
                            data.markAsFailed(at: .accountPayment, error: error)
                        }

                        wideEvent.completeFlow(data, status: .failure, onComplete: { _, _ in })
                    }

                    return nil
                }

                // 7: Update UI to indicate that the purchase is completing
                await uiHandler.updateProgressViewController(title: UserText.completingPurchaseTitle)

                // 8: Attempt to complete the purchase, measuring the duration
                var accountActivationDuration = WideEvent.MeasuredInterval.startingNow()
                data.activateAccountDuration = accountActivationDuration
                wideEvent.updateFlow(data)

                let completePurchaseResult = await appStorePurchaseFlow.completeSubscriptionPurchase(with: purchaseTransactionJWS, additionalParams: nil)

                func completeWideEventFlow(with error: Error) {
                    guard let purchaseWideEventData = self.purchaseWideEventData else { return }
                    accountActivationDuration.complete()
                    purchaseWideEventData.activateAccountDuration = accountActivationDuration
                    purchaseWideEventData.markAsFailed(at: .accountActivation, error: error)
                    wideEvent.updateFlow(purchaseWideEventData)
                    wideEvent.completeFlow(purchaseWideEventData, status: .failure, onComplete: { _, _ in })
                }

                // 9: Handle purchase completion result
                switch completePurchaseResult {
                case .success(let purchaseUpdate):
                    Logger.subscription.log("[Purchase] Purchase completed")
                    PixelKit.fire(SubscriptionPixel.subscriptionPurchaseSuccess, frequency: .legacyDailyAndCount)
                    sendFreemiumSubscriptionPixelIfFreemiumActivated()
                    saveSubscriptionUpgradeTimestampIfFreemiumActivated()
                    PixelKit.fire(SubscriptionPixel.subscriptionActivated, frequency: .uniqueByName)
                    subscriptionSuccessPixelHandler.fireSuccessfulSubscriptionAttributionPixel()
                    sendSubscriptionUpgradeFromFreemiumNotificationIfFreemiumActivated()
                    notificationCenter.post(name: .subscriptionDidChange, object: self)
                    await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: purchaseUpdate)

                    accountActivationDuration.complete()
                    data.activateAccountDuration = accountActivationDuration
                    wideEvent.updateFlow(data)
                    wideEvent.completeFlow(data, status: .success, onComplete: { _, _ in })
                case .failure(let error):
                    reportPurchaseFlowError(error)

                    switch error {
                    case .cancelledByUser:
                        if let purchaseWideEventData {
                            wideEvent.completeFlow(purchaseWideEventData, status: .cancelled, onComplete: { _, _ in })
                        }
                    case .missingEntitlements:
                        // This case deliberately avoids sending a failure wide event in case activation succeeds later
                        DispatchQueue.main.async { [weak self] in
                            self?.notificationCenter.post(name: .subscriptionPageCloseAndOpenPreferences, object: self)
                        }
                        await uiHandler.dismissProgressViewController()
                        return nil
                    case .internalError(let internalError):
                        completeWideEventFlow(with: internalError ?? error)
                    default:
                        completeWideEventFlow(with: error)
                    }

                    await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "completed"))
                }
            }
        } else if subscriptionPlatform == .stripe {
            let emailAccessToken = try? EmailManager().getToken()
            let contextName = await originFrom(originalMessage: message) ?? ""

            let data = SubscriptionPurchaseWideEventData(purchasePlatform: .stripe,
                                                         subscriptionIdentifier: nil, // Not available for Stripe
                                                         freeTrialEligible: true, // Always true for Stripe
                                                         contextData: WideEventContextData(name: contextName))

            wideEvent.startFlow(data)
            self.purchaseWideEventData = data

            let result = await stripePurchaseFlow.prepareSubscriptionPurchase(emailAccessToken: emailAccessToken)
            switch result {
            case .success(let success):
                if let purchaseWideEventData = self.purchaseWideEventData {
                    if let accountCreationDuration = success.accountCreationDuration {
                        purchaseWideEventData.createAccountDuration = accountCreationDuration
                    }

                    wideEvent.updateFlow(purchaseWideEventData)
                }

                await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: success.purchaseUpdate)
            case .failure(let error):
                await showSomethingWentWrongAlert()
                switch error {
                case .noProductsFound, .tieredProductsApiCallFailed, .tieredProductsEmptyProductsFromAPI, .tieredProductsEmptyAfterFiltering, .tieredProductsTierCreationFailed:
                    subscriptionEventReporter.report(subscriptionActivationError: .failedToGetSubscriptionOptions)
                case .accountCreationFailed(let creationError):
                    subscriptionEventReporter.report(subscriptionActivationError: .accountCreationFailed(creationError))
                }

                await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "canceled"))

                if let purchaseWideEventData = self.purchaseWideEventData {
                    purchaseWideEventData.markAsFailed(at: .accountCreate, error: error)
                    wideEvent.updateFlow(purchaseWideEventData)
                    wideEvent.completeFlow(purchaseWideEventData, status: .failure, onComplete: { _, _ in })
                }
            }
        }

        await uiHandler.dismissProgressViewController()
        return nil
    }

    // MARK: - Tier Change

    func subscriptionChangeSelected(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        struct SubscriptionChangeSelection: Decodable {
            let id: String
            let change: String?  // "upgrade" or "downgrade"
        }

        let message = original
        await setPixelOrigin(from: message)
        let origin = await originFrom(originalMessage: message)

        // Debug: Log raw params received from frontend
        Logger.subscription.debug("[TierChange] Raw params received: \(String(describing: params), privacy: .public)")

        // Parse subscription change selection from message object
        guard let subscriptionSelection: SubscriptionChangeSelection = CodableHelper.decode(from: params) else {
            assertionFailure("SubscriptionPagesUserScript: expected JSON representation of SubscriptionChangeSelection")
            subscriptionEventReporter.report(subscriptionActivationError: .otherPurchaseError)
            await uiHandler.dismissProgressViewController()
            return nil
        }

        Logger.subscription.log("[TierChange] Parsed - id: \(subscriptionSelection.id, privacy: .public), change: \(subscriptionSelection.change ?? "nil", privacy: .public)")
        let currentSubscription = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst)
        let effectivePlatform: DuckDuckGoSubscription.Platform = currentSubscription?.platform ?? (subscriptionPlatform == .stripe ? .stripe : .apple)

        switch effectivePlatform {
        case .apple:
            let purchaseUpdate = await flowPerformer.performTierChange(
                to: subscriptionSelection.id,
                changeType: subscriptionSelection.change,
                contextName: origin ?? ""
            )
            if let purchaseUpdate {
                await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: purchaseUpdate)
            } else {
                return nil
            }
        case .stripe:
            // For Stripe tier changes, we always send the auth token so the backend can modify the existing subscription
            Logger.subscription.log("[TierChange] Stripe - id: \(subscriptionSelection.id, privacy: .public), change: \(subscriptionSelection.change ?? "nil", privacy: .public)")

            // Get current subscription info for wide event tracking
            let fromPlan = currentSubscription?.productId ?? ""

            // Determine change type from frontend
            let changeType = SubscriptionPlanChangeWideEventData.ChangeType.parse(string: subscriptionSelection.change)

            // Initialize wide event data for Stripe
            let wideData = SubscriptionPlanChangeWideEventData(
                purchasePlatform: .stripe,
                changeType: changeType,
                fromPlan: fromPlan,
                toPlan: subscriptionSelection.id,
                contextData: WideEventContextData(name: origin ?? "")
            )
            self.planChangeWideEventData = wideData
            wideEvent.startFlow(wideData)

            // Get the access token - for tier changes, the user must be authenticated
            // since they're modifying an existing subscription
            let accessToken: String
            do {
                let tokenContainer = try await subscriptionManager.getTokenContainer(policy: .localValid)
                accessToken = tokenContainer.accessToken
                Logger.subscription.log("[TierChange] Retrieved access token for Stripe tier change")
            } catch {
                Logger.subscription.error("[TierChange] Failed to get token for Stripe tier change: \(error, privacy: .public)")
                subscriptionEventReporter.report(subscriptionActivationError: .otherPurchaseError)
                await showSomethingWentWrongAlert()
                await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "canceled"))

                wideData.markAsFailed(at: SubscriptionPlanChangeWideEventData.FailingStep.payment, error: error)
                wideEvent.completeFlow(wideData, status: .failure, onComplete: { _, _ in })
                self.planChangeWideEventData = nil
                return nil
            }

            // Start confirmation timing (will be completed in completeStripePayment)
            wideData.confirmationDuration = WideEvent.MeasuredInterval.startingNow()
            wideEvent.updateFlow(wideData)

            // Return redirect with token so frontend handles Stripe checkout
            // Note: For Stripe, the wide event will be completed when completeStripePayment is called
            await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate.redirect(withToken: accessToken))
        default:
            assertionFailure("SubscriptionPagesUserScript: expected Apple or Stipe platform on SubscriptionChangeSelection")
            subscriptionEventReporter.report(subscriptionActivationError: .otherPurchaseError)
            await uiHandler.dismissProgressViewController()
            return nil
        }
        await uiHandler.dismissProgressViewController()
        return nil
    }

    // MARK: functions used in SubscriptionAccessActionHandlers

    func activateSubscription(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        PixelKit.fire(SubscriptionPixel.subscriptionRestorePurchaseOfferPageEntry)
        Task { @MainActor in
            uiHandler.presentSubscriptionAccessViewController(handler: self, message: original)
        }
        return nil
    }

    func featureSelected(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        struct FeatureSelection: Codable {
            let productFeature: SubscriptionEntitlement
        }

        guard let featureSelection: FeatureSelection = CodableHelper.decode(from: params) else {
            assertionFailure("SubscriptionPagesUserScript: expected JSON representation of FeatureSelection")
            return nil
        }

        switch featureSelection.productFeature {
        case .networkProtection:
            PixelKit.fire(SubscriptionPixel.subscriptionWelcomeVPN, frequency: .uniqueByName)
            notificationCenter.post(name: .ToggleNetworkProtectionInMainWindow, object: self, userInfo: nil)
        case .dataBrokerProtection:
            PixelKit.fire(SubscriptionPixel.subscriptionWelcomePersonalInformationRemoval, frequency: .uniqueByName)
            notificationCenter.post(name: .openPersonalInformationRemoval, object: self, userInfo: nil)
            await uiHandler.showTab(with: .dataBrokerProtection)
        case .identityTheftRestoration, .identityTheftRestorationGlobal:
            PixelKit.fire(SubscriptionPixel.subscriptionWelcomeIdentityRestoration, frequency: .uniqueByName)
            let url = subscriptionManager.url(for: .identityTheftRestoration)
            await uiHandler.showTab(with: .identityTheftRestoration(url))
        case .paidAIChat:
            PixelKit.fire(SubscriptionPixel.subscriptionWelcomeAIChat, frequency: .uniqueByName)
            await uiHandler.showTab(with: .aiChat(aiChatURL))
        case .unknown:
            break
        }

        return nil
    }

    func completeStripePayment(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        // Parse optional change parameter for tier changes
        struct StripePaymentCompletion: Decodable {
            let change: String?  // "upgrade" or "downgrade" for tier changes, nil for new purchases
        }

        let completion: StripePaymentCompletion? = CodableHelper.decode(from: params)
        let changeType = completion?.change

        var accountActivationDuration = WideEvent.MeasuredInterval.startingNow()
        purchaseWideEventData?.activateAccountDuration = accountActivationDuration

        let completingTitle = planChangeWideEventData != nil ? UserText.completePlanChangeTitle : UserText.completingPurchaseTitle
        await uiHandler.presentProgressViewController(withTitle: completingTitle)
        await stripePurchaseFlow.completeSubscriptionPurchase()
        await uiHandler.dismissProgressViewController()

        // Fire appropriate pixel based on whether this is a new purchase or tier change
        if let changeType {
            Logger.subscription.log("[TierChange] Stripe \(changeType, privacy: .public) completed successfully")
        } else {
            PixelKit.fire(SubscriptionPixel.subscriptionPurchaseStripeSuccess, frequency: .legacyDailyAndCount)
            subscriptionSuccessPixelHandler.fireSuccessfulSubscriptionAttributionPixel()
        }

        sendFreemiumSubscriptionPixelIfFreemiumActivated()
        saveSubscriptionUpgradeTimestampIfFreemiumActivated()
        sendSubscriptionUpgradeFromFreemiumNotificationIfFreemiumActivated()
        notificationCenter.post(name: .subscriptionDidChange, object: self)

        // Complete the appropriate wide event based on whether this is a new purchase or tier change.
        // planChangeWideEventData is set when subscriptionChangeSelected runs the Stripe tier change path.
        let planChangeData = self.planChangeWideEventData
        if let data = planChangeData {
            // Tier change - complete plan change wide event
            data.confirmationDuration?.complete()
            wideEvent.updateFlow(data)
            wideEvent.completeFlow(data, status: .success, onComplete: { _, _ in })
            self.planChangeWideEventData = nil
        } else if let data = self.purchaseWideEventData {
            // New purchase - complete purchase wide event
            accountActivationDuration.complete()
            data.activateAccountDuration = accountActivationDuration
            wideEvent.updateFlow(data)
            wideEvent.completeFlow(data, status: .success, onComplete: { _, _ in })
            self.purchaseWideEventData = nil
        }

        return [String: String]() // cannot be nil, the web app expect something back before redirecting the user to the final page
    }

    // MARK: Pixel related actions

    func subscriptionsMonthlyPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        PixelKit.fire(SubscriptionPixel.subscriptionOfferMonthlyPriceClick)
        return nil
    }

    func subscriptionsYearlyPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        PixelKit.fire(SubscriptionPixel.subscriptionOfferYearlyPriceClick)
        return nil
    }

    func subscriptionsUnknownPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        // Not used
        return nil
    }

    func subscriptionsAddEmailSuccess(params: Any, original: WKScriptMessage) async -> Encodable? {
        PixelKit.fire(SubscriptionPixel.subscriptionAddEmailSuccess, frequency: .uniqueByName)
        return nil
    }

    func subscriptionsWelcomeAddEmailClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        PixelKit.fire(SubscriptionPixel.subscriptionWelcomeAddDevice, frequency: .uniqueByName)
        return nil
    }

    func subscriptionsWelcomeFaqClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        PixelKit.fire(SubscriptionPixel.subscriptionWelcomeFAQClick, frequency: .uniqueByName)
        return nil
    }

    func getAccessToken(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        do {
            let accessToken = try await subscriptionManager.getTokenContainer(policy: .localValid).accessToken
            return ["token": accessToken]
        } catch {
            Logger.subscription.debug("No access token available: \(error)")
            return [String: String]()
        }
    }

    // MARK: Push actions

    enum SubscribeActionName: String {
        case onPurchaseUpdate
    }

    @MainActor
    func pushPurchaseUpdate(originalMessage: WKScriptMessage, purchaseUpdate: PurchaseUpdate) {
        guard let webView = originalMessage.webView else {
            return
        }
        pushAction(method: .onPurchaseUpdate, webView: webView, params: purchaseUpdate)
    }

    func pushAction(method: SubscribeActionName, webView: WKWebView, params: Encodable) {
        guard let broker else {
            assertionFailure("Cannot continue without broker instance")
            return
        }

        broker.push(method: method.rawValue, params: params, for: self, into: webView)
    }

    @MainActor
    private func originFrom(originalMessage: WKScriptMessage) -> String? {
        let url = originalMessage.webView?.url
        return url?.getParameter(named: AttributionParameter.origin)
    }

    // MARK: - UI interactions

    func showSomethingWentWrongAlert() async {
        switch await uiHandler.dismissProgressViewAndShow(alertType: .somethingWentWrong, text: nil) {
        case .alertFirstButtonReturn:
            let url = subscriptionManager.url(for: .purchase)
            await uiHandler.showTab(with: .subscription(url))
            PixelKit.fire(SubscriptionPixel.subscriptionOfferScreenImpression)
        default: return
        }
    }

    func showSubscriptionFoundAlert(originalMessage: WKScriptMessage) async {

        let restorePrePurcahseBackgroundWideEventData = SubscriptionRestoreWideEventData(
            restorePlatform: .purchaseBackgroundTask,
            contextData: WideEventContextData(name: SubscriptionRestoreFunnelOrigin.prePurchaseCheck.rawValue)
        )

        switch await uiHandler.dismissProgressViewAndShow(alertType: .subscriptionFound, text: nil) {
        case .alertFirstButtonReturn:
            if #available(macOS 12.0, *) {
                restorePrePurcahseBackgroundWideEventData.appleAccountRestoreDuration = WideEvent.MeasuredInterval.startingNow()
                wideEvent.startFlow(restorePrePurcahseBackgroundWideEventData)
                let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(subscriptionManager: subscriptionManager,
                                                                       storePurchaseManager: subscriptionManager.storePurchaseManager())
                let result = await appStoreRestoreFlow.restoreAccountFromPastPurchase()
                switch result {
                case .success:
                    PixelKit.fire(SubscriptionPixel.subscriptionRestorePurchaseStoreSuccess, frequency: .legacyDailyAndCount)
                    restorePrePurcahseBackgroundWideEventData.appleAccountRestoreDuration?.complete()
                    wideEvent.completeFlow(restorePrePurcahseBackgroundWideEventData, status: .success(reason: nil), onComplete: { _, _ in })
                case .failure(let error):
                    Logger.subscription.error("Failed to restore account from past purchase: \(error, privacy: .public)")
                    restorePrePurcahseBackgroundWideEventData.appleAccountRestoreDuration?.complete()
                    restorePrePurcahseBackgroundWideEventData.errorData = .init(error: error)
                    wideEvent.completeFlow(restorePrePurcahseBackgroundWideEventData, status: .failure, onComplete: { _, _ in })
                }
                Task { @MainActor in
                    originalMessage.webView?.reload()
                }
            }
        default: return
        }
    }

    // MARK: - Purchase Flow Helpers

    /// Creates an App Store purchase flow with the required dependencies.
    @available(macOS 12.0, *)
    private func makeAppStorePurchaseFlow() -> DefaultAppStorePurchaseFlow {
        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(
            subscriptionManager: subscriptionManager,
            storePurchaseManager: subscriptionManager.storePurchaseManager(),
            pendingTransactionHandler: pendingTransactionHandler
        )
        return DefaultAppStorePurchaseFlow(
            subscriptionManager: subscriptionManager,
            storePurchaseManager: subscriptionManager.storePurchaseManager(),
            appStoreRestoreFlow: appStoreRestoreFlow,
            wideEvent: wideEvent,
            pendingTransactionHandler: pendingTransactionHandler
        )
    }

    /// Reports a purchase flow error to the subscription event reporter.
    /// This maps `AppStorePurchaseFlowError` to the appropriate `SubscriptionActivationError` for analytics.
    private func reportPurchaseFlowError(_ error: AppStorePurchaseFlowError) {
        switch error {
        case .noProductsFound:
            subscriptionEventReporter.report(subscriptionActivationError: .failedToGetSubscriptionOptions)
        case .activeSubscriptionAlreadyPresent:
            subscriptionEventReporter.report(subscriptionActivationError: .activeSubscriptionAlreadyPresent)
        case .authenticatingWithTransactionFailed:
            subscriptionEventReporter.report(subscriptionActivationError: .otherPurchaseError)
        case .accountCreationFailed(let creationError):
            subscriptionEventReporter.report(subscriptionActivationError: .accountCreationFailed(creationError))
        case .purchaseFailed(let purchaseError):
            subscriptionEventReporter.report(subscriptionActivationError: .purchaseFailed(purchaseError))
        case .transactionPendingAuthentication:
            pendingTransactionHandler.markPurchasePending()
            subscriptionEventReporter.report(subscriptionActivationError: .purchasePendingTransaction)
        case .cancelledByUser:
            subscriptionEventReporter.report(subscriptionActivationError: .cancelledByUser)
        case .missingEntitlements:
            subscriptionEventReporter.report(subscriptionActivationError: .missingEntitlements)
        case .internalError:
            assertionFailure("Internal error")
        }
    }

    // MARK: - Attribution
    /// Sets the appropriate origin for the subscription success tracking pixel.
    ///
    /// - Note: This method is asynchronous when extracting the origin from the webview URL.
    @discardableResult private func setPixelOrigin(from message: WKScriptMessage) async -> String? {
        // Extract the origin from the webview URL to use for attribution pixel.
        let origin = await originFrom(originalMessage: message)
        subscriptionSuccessPixelHandler.origin = origin
        return origin
    }
}

/// For handling subscription access actions when presented as modal VC on purchase page via "I Have a Subscription" link
extension SubscriptionPagesUseSubscriptionFeature: SubscriptionAccessActionHandling {

    func subscriptionAccessActionRestorePurchases(message: WKScriptMessage) {
        if #available(macOS 12.0, *) {
            Task { @MainActor in
                let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(subscriptionManager: subscriptionManager,
                                                                       storePurchaseManager: subscriptionManager.storePurchaseManager())
                let subscriptionRestoreAppleOfferPageWideEventData = SubscriptionRestoreWideEventData(
                    restorePlatform: .appleAccount,
                    contextData: WideEventContextData(name: SubscriptionRestoreFunnelOrigin.purchaseOffer.rawValue)
                )
                let subscriptionAppStoreRestorer = DefaultSubscriptionAppStoreRestorerV2(subscriptionManager: self.subscriptionManager,
                                                                                         appStoreRestoreFlow: appStoreRestoreFlow,
                                                                                         uiHandler: self.uiHandler,
                                                                                         subscriptionRestoreWideEventData: subscriptionRestoreAppleOfferPageWideEventData)
                await subscriptionAppStoreRestorer.restoreAppStoreSubscription()
                message.webView?.reload()
            }
        }
    }

    func subscriptionAccessActionOpenURLHandler(url: URL) {
        Task {
            setupRestoreEmailOfferPageWideEventDataIfNeeded()
            await self.uiHandler.showTab(with: .subscription(url))
        }
    }
}

private extension SubscriptionPagesUseSubscriptionFeature {

    /**
     Sends a subscription upgrade notification if the freemium state is activated.

     This function checks if the freemium state has been activated by verifying the
     `didActivate` property in `freemiumDBPUserStateManager`. If the freemium activation
     is detected, it posts a `subscriptionUpgradeFromFreemium` notification via
     `notificationCenter`.

     - Important: The notification will only be posted if `didActivate` is `true`.
     */
    func sendSubscriptionUpgradeFromFreemiumNotificationIfFreemiumActivated() {
        if freemiumDBPUserStateManager.didActivate {
            notificationCenter.post(name: .subscriptionUpgradeFromFreemium, object: nil)
        }
    }

    /// Sends a freemium subscription pixel event if the freemium feature has been activated.
    ///
    /// This function checks whether the user has activated the freemium feature by querying the `freemiumDBPUserStateManager`.
    /// If the feature is activated (`didActivate` returns `true`), it fires a unique subscription-related pixel event using `PixelKit`.
    func sendFreemiumSubscriptionPixelIfFreemiumActivated() {
        if freemiumDBPUserStateManager.didActivate {
            dataBrokerProtectionFreemiumPixelHandler.fire(DataBrokerProtectionFreemiumPixels.subscription)
        }
    }

    /// Saves the current timestamp for a subscription upgrade if the freemium feature has been activated.
    ///
    /// This function checks whether the user has activated the freemium feature and if the subscription upgrade timestamp
    /// has not already been set. If the user has activated the freemium feature and no upgrade timestamp exists, it assigns
    /// the current date and time to `freemiumDBPUserStateManager.upgradeToSubscriptionTimestamp`.
    func saveSubscriptionUpgradeTimestampIfFreemiumActivated() {
        if freemiumDBPUserStateManager.didActivate && freemiumDBPUserStateManager.upgradeToSubscriptionTimestamp == nil {
            freemiumDBPUserStateManager.upgradeToSubscriptionTimestamp = Date()
        }
    }
}

// MARK: - Wide Event

private extension SubscriptionPagesUseSubscriptionFeature {

    // Attempt to retrieve restoreEmailAppSettingsWideEventData sent from Preferences/View/PreferencesRootView.swift
    func retrieveRestoreEmailAppSettingsWideEventDataIfNeeded() {
        let flows = wideEvent.getAllFlowData(SubscriptionRestoreWideEventData.self)
        if let data = flows.last(where: { $0.restorePlatform == .emailAddress && $0.emailAddressRestoreDuration?.start != nil && $0.emailAddressRestoreDuration?.end == nil && $0.contextData.name == SubscriptionRestoreFunnelOrigin.appSettings.rawValue }) {
            self.restoreEmailAppSettingsWideEventData = data
        }
    }

    func setupRestoreEmailOfferPageWideEventDataIfNeeded() {
        let restoreEmailOfferPageWideEventData = SubscriptionRestoreWideEventData(
            restorePlatform: .emailAddress,
            contextData: WideEventContextData(name: SubscriptionRestoreFunnelOrigin.purchaseOffer.rawValue)
        )
        self.restoreEmailOfferPageWideEventData = restoreEmailOfferPageWideEventData
        restoreEmailOfferPageWideEventData.emailAddressRestoreDuration = WideEvent.MeasuredInterval.startingNow()
        wideEvent.startFlow(restoreEmailOfferPageWideEventData)
    }

    func markEmailAddressRestoreAsFailure(data dataList: [SubscriptionRestoreWideEventData], with error: Error? = nil) {
        for data in dataList {
            data.emailAddressRestoreDuration?.complete()
            if let error {
                data.errorData = .init(error: error)
            }
            wideEvent.completeFlow(data, status: .failure, onComplete: { _, _ in })
        }
    }

    func markEmailAddressRestoreAsSuccess(data dataList: [SubscriptionRestoreWideEventData]) {
        for data in dataList {
            data.emailAddressRestoreDuration?.complete()
            wideEvent.completeFlow(data, status: .success, onComplete: { _, _ in })
        }
    }
}
