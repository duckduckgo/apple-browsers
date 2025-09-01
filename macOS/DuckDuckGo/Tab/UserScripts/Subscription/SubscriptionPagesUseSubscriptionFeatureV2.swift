//
//  SubscriptionPagesUseSubscriptionFeatureV2.swift
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
    let useSubscriptionsAuthV2: Bool
    let usePaidDuckAi: Bool
    let useAlternateStripePaymentFlow: Bool
}

/// Use Subscription sub-feature
final class SubscriptionPagesUseSubscriptionFeatureV2: Subfeature {

    private enum OriginDomains {
        static let duckduckgo = "duckduckgo.com"
    }

    weak var broker: UserScriptMessageBroker?

    let featureName = "useSubscription"
    lazy var messageOriginPolicy: MessageOriginPolicy = .only(rules: [
        HostnameMatchingRule.makeExactRule(for: subscriptionManager.url(for: .baseURL)) ?? .exact(hostname: OriginDomains.duckduckgo)
    ])

    let subscriptionManager: SubscriptionManagerV2
    var subscriptionPlatform: SubscriptionEnvironment.PurchasePlatform { subscriptionManager.currentEnvironment.purchasePlatform }
    let stripePurchaseFlow: any StripePurchaseFlowV2
    let subscriptionErrorReporter = DefaultSubscriptionErrorReporter()
    let subscriptionSuccessPixelHandler: SubscriptionAttributionPixelHandler
    let uiHandler: SubscriptionUIHandling
    let subscriptionFeatureAvailability: SubscriptionFeatureAvailability
    private var freemiumDBPUserStateManager: FreemiumDBPUserStateManager
    private let notificationCenter: NotificationCenter
    /// The `DataBrokerProtectionFreemiumPixelHandler` instance used to fire pixels
    private let dataBrokerProtectionFreemiumPixelHandler: EventMapping<DataBrokerProtectionFreemiumPixels>

    private let featureFlagger: FeatureFlagger
    private let aiChatURL: URL
    private let widePixel: WidePixelManaging
    private var widePixelData: SubscriptionPurchaseWidePixelData?

    public init(subscriptionManager: SubscriptionManagerV2,
                subscriptionSuccessPixelHandler: SubscriptionAttributionPixelHandler = PrivacyProSubscriptionAttributionPixelHandler(),
                stripePurchaseFlow: StripePurchaseFlowV2,
                uiHandler: SubscriptionUIHandling,
                subscriptionFeatureAvailability: SubscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(),
                freemiumDBPUserStateManager: FreemiumDBPUserStateManager = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp),
                notificationCenter: NotificationCenter = .default,
                dataBrokerProtectionFreemiumPixelHandler: EventMapping<DataBrokerProtectionFreemiumPixels> = DataBrokerProtectionFreemiumPixelHandler(),
                featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
                aiChatURL: URL,
                widePixel: WidePixelManaging = WidePixel()) {
        self.subscriptionManager = subscriptionManager
        self.stripePurchaseFlow = stripePurchaseFlow
        self.subscriptionSuccessPixelHandler = subscriptionSuccessPixelHandler
        self.uiHandler = uiHandler
        self.aiChatURL = aiChatURL
        self.subscriptionFeatureAvailability = subscriptionFeatureAvailability
        self.freemiumDBPUserStateManager = freemiumDBPUserStateManager
        self.notificationCenter = notificationCenter
        self.dataBrokerProtectionFreemiumPixelHandler = dataBrokerProtectionFreemiumPixelHandler
        self.featureFlagger = featureFlagger
        self.widePixel = widePixel
    }

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    struct Handlers {
        static let setAuthTokens = "setAuthTokens"
        static let getAuthAccessToken = "getAuthAccessToken"
        static let getFeatureConfig = "getFeatureConfig"
        static let backToSettings = "backToSettings"
        static let getSubscriptionOptions = "getSubscriptionOptions"
        static let subscriptionSelected = "subscriptionSelected"
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
        case Handlers.getSubscriptionOptions: return getSubscriptionOptions
        case Handlers.subscriptionSelected: return subscriptionSelected
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

        PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseEmailSuccess, frequency: .legacyDailyAndCount)

        guard let subscriptionValues: SubscriptionValuesV2 = CodableHelper.decode(from: params) else {
            Logger.subscription.fault("SubscriptionPagesUserScript: expected JSON representation of SubscriptionValues")
            assertionFailure("SubscriptionPagesUserScript: expected JSON representation of SubscriptionValues")
            return nil
        }

        // Clear subscription Cache
        subscriptionManager.clearSubscriptionCache()

        guard !subscriptionValues.accessToken.isEmpty, !subscriptionValues.refreshToken.isEmpty else {
            Logger.subscription.fault("Empty access token or refresh token provided")
            return nil
        }

        do {
            try await subscriptionManager.adopt(accessToken: subscriptionValues.accessToken, refreshToken: subscriptionValues.refreshToken)
            try await subscriptionManager.getSubscription(cachePolicy: .remoteFirst)
            Logger.subscription.log("Subscription retrieved")
        } catch {
            Logger.subscription.error("Failed to adopt V2 tokens: \(error, privacy: .public)")
        }
        return nil
    }

    func getAuthAccessToken(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        let tokenContainer = try? await subscriptionManager.getTokenContainer(policy: .localValid)
        return AccessTokenValue(accessToken: tokenContainer?.accessToken ?? "")
    }

    func getFeatureConfig(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        return GetFeatureValue(
            useSubscriptionsAuthV2: true,
            usePaidDuckAi: subscriptionFeatureAvailability.isPaidAIChatEnabled,
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

    func getSubscriptionOptions(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        var subscriptionOptions = SubscriptionOptionsV2.empty

        switch subscriptionPlatform {
        case .appStore:
            guard #available(macOS 12.0, *) else { break }

            if featureFlagger.isFeatureOn(.privacyProFreeTrial),
               let freeTrialOptions = await freeTrialSubscriptionOptions() {
                subscriptionOptions = freeTrialOptions
            } else if let appStoreSubscriptionOptions = await subscriptionManager.storePurchaseManager().subscriptionOptions() {
                subscriptionOptions = appStoreSubscriptionOptions
            }
        case .stripe:
            switch await stripePurchaseFlow.subscriptionOptions() {
            case .success(let stripeSubscriptionOptions):
                subscriptionOptions = stripeSubscriptionOptions
            case .failure:
                break
            }
        }

        guard subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed else { return subscriptionOptions.withoutPurchaseOptions() }

        return subscriptionOptions
    }

    // swiftlint:disable:next cyclomatic_complexity
    func subscriptionSelected(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        PixelKit.fire(PrivacyProPixel.privacyProPurchaseAttempt, frequency: .legacyDailyAndCount)
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
                    subscriptionErrorReporter.report(subscriptionActivationError: .otherPurchaseError)
                    await uiHandler.dismissProgressViewController()
                    return nil
                }

                Logger.subscription.log("[Purchase] Starting purchase for: \(subscriptionSelection.id, privacy: .public)")

                // 2: Show purchase progress UI to user
                await uiHandler.presentProgressViewController(withTitle: UserText.purchasingSubscriptionTitle)

                // 3: Check for active subscriptions
                if await subscriptionManager.storePurchaseManager().hasActiveSubscription() {
                    // Sandbox note: Looks like our BE is not receiving updates when a subscription transitions from grace period to expired, so during testing we can end up with a subscription in grace period and we will not be able to purchase a new one, only restore it because Transaction.currentEntitlements will not return the subscription to restore.
                    PixelKit.fire(PrivacyProPixel.privacyProRestoreAfterPurchaseAttempt)
                    Logger.subscription.log("[Purchase] Found active subscription during purchase")
                    subscriptionErrorReporter.report(subscriptionActivationError: .activeSubscriptionAlreadyPresent)
                    await showSubscriptionFoundAlert(originalMessage: message)
                    await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "canceled"))
                    return nil
                }

                // 4: Configure wide pixel and start the flow
                let freeTrialEligible = subscriptionManager.storePurchaseManager().isUserEligibleForFreeTrial()
                let data = SubscriptionPurchaseWidePixelData(purchasePlatform: .appStore,
                                                             subscriptionIdentifier: subscriptionSelection.id,
                                                             freeTrialEligible: freeTrialEligible,
                                                             contextData: WidePixelContextData(name: origin ?? ""))
                self.widePixelData = data

                if subscriptionFeatureAvailability.isSubscriptionPurchaseWidePixelMeasurementEnabled {
                    widePixel.startFlow(data)
                }

                // 5: No existing subscription was found, so proceed with the remaining purchase flow
                let purchaseTransactionJWS: String
                let appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager,
                                                                       storePurchaseManager: subscriptionManager.storePurchaseManager())
                let appStorePurchaseFlow = DefaultAppStorePurchaseFlowV2(subscriptionManager: subscriptionManager,
                                                                         storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                         appStoreRestoreFlow: appStoreRestoreFlow)

                // 6: Execute App Store purchase (account creation + StoreKit transaction) and handle the result
                Logger.subscription.log("[Purchase] Purchasing")
                let purchaseResult = await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelection.id)

                switch purchaseResult {
                case .success(let result):
                    purchaseTransactionJWS = result.transactionJWS

                    // Account creation is only one piece of the purchase function's job, so we extract the creation
                    // duration from the result rather than time the execution of the entire call.
                    if let accountCreationDuration = result.accountCreationDuration {
                        data.createAccountDuration = accountCreationDuration
                    }
                case .failure(let error):
                    switch error {
                    case .noProductsFound:
                        subscriptionErrorReporter.report(subscriptionActivationError: .failedToGetSubscriptionOptions)
                    case .activeSubscriptionAlreadyPresent:
                        subscriptionErrorReporter.report(subscriptionActivationError: .activeSubscriptionAlreadyPresent)
                    case .authenticatingWithTransactionFailed:
                        subscriptionErrorReporter.report(subscriptionActivationError: .otherPurchaseError)
                    case .accountCreationFailed(let creationError):
                        subscriptionErrorReporter.report(subscriptionActivationError: .accountCreationFailed(creationError))
                    case .purchaseFailed(let purchaseError):
                        subscriptionErrorReporter.report(subscriptionActivationError: .purchaseFailed(purchaseError))
                    case .cancelledByUser:
                        subscriptionErrorReporter.report(subscriptionActivationError: .cancelledByUser)
                    case .missingEntitlements:
                        subscriptionErrorReporter.report(subscriptionActivationError: .missingEntitlements)
                    case .internalError:
                        assertionFailure("Internal error")
                    }

                    if error != .cancelledByUser {
                        await showSomethingWentWrongAlert()
                    } else {
                        await uiHandler.dismissProgressViewController()
                    }

                    await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "canceled"))

                    // Complete the wide pixel flow if the purchase step fails:
                    if error == .cancelledByUser {
                        if subscriptionFeatureAvailability.isSubscriptionPurchaseWidePixelMeasurementEnabled {
                            widePixel.completeFlow(data, status: .cancelled, onComplete: { _, _ in })
                        }
                    } else if error == .activeSubscriptionAlreadyPresent {
                        // If we found a subscription, then this is not a purchase flow - discard the purchase pixel.
                        if subscriptionFeatureAvailability.isSubscriptionPurchaseWidePixelMeasurementEnabled, let data = self.widePixelData {
                            widePixel.discardFlow(data)
                            self.widePixelData = nil
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

                        if subscriptionFeatureAvailability.isSubscriptionPurchaseWidePixelMeasurementEnabled {
                            widePixel.completeFlow(data, status: .failure, onComplete: { _, _ in })
                        }
                    }

                    return nil
                }

                // 7: Update UI to indicate that the purchase is completing
                await uiHandler.updateProgressViewController(title: UserText.completingPurchaseTitle)

                // 8: Attempt to complete the purchase, measuring the duration
                var accountActivationDuration = WidePixel.MeasuredInterval.startingNow()
                data.activateAccountDuration = accountActivationDuration
                widePixel.updateFlow(data)

                let completePurchaseResult = await appStorePurchaseFlow.completeSubscriptionPurchase(with: purchaseTransactionJWS, additionalParams: nil)

                func completeWidePixelFlow(with error: Error) {
                    guard let widePixelData = self.widePixelData else { return }
                    accountActivationDuration.complete()
                    widePixelData.activateAccountDuration = accountActivationDuration
                    widePixelData.markAsFailed(at: .accountActivation, error: error)
                    widePixel.updateFlow(widePixelData)
                    widePixel.completeFlow(widePixelData, status: .failure, onComplete: { _, _ in })
                }

                // 9: Handle purchase completion result
                switch completePurchaseResult {
                case .success(let purchaseUpdate):
                    Logger.subscription.log("[Purchase] Purchase completed")
                    PixelKit.fire(PrivacyProPixel.privacyProPurchaseSuccess, frequency: .legacyDailyAndCount)
                    sendFreemiumSubscriptionPixelIfFreemiumActivated()
                    saveSubscriptionUpgradeTimestampIfFreemiumActivated()
                    PixelKit.fire(PrivacyProPixel.privacyProSubscriptionActivated, frequency: .uniqueByName)
                    subscriptionSuccessPixelHandler.fireSuccessfulSubscriptionAttributionPixel()
                    sendSubscriptionUpgradeFromFreemiumNotificationIfFreemiumActivated()
                    notificationCenter.post(name: .subscriptionDidChange, object: self)
                    await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: purchaseUpdate)

                    accountActivationDuration.complete()
                    data.activateAccountDuration = accountActivationDuration
                    widePixel.updateFlow(data)
                    widePixel.completeFlow(data, status: .success, onComplete: { _, _ in })
                case .failure(let error):
                    switch error {
                    case .noProductsFound:
                        subscriptionErrorReporter.report(subscriptionActivationError: .failedToGetSubscriptionOptions)
                        completeWidePixelFlow(with: error)
                    case .activeSubscriptionAlreadyPresent:
                        subscriptionErrorReporter.report(subscriptionActivationError: .activeSubscriptionAlreadyPresent)
                        completeWidePixelFlow(with: error)
                    case .authenticatingWithTransactionFailed:
                        subscriptionErrorReporter.report(subscriptionActivationError: .otherPurchaseError)
                        completeWidePixelFlow(with: error)
                    case .accountCreationFailed(let creationError):
                        subscriptionErrorReporter.report(subscriptionActivationError: .accountCreationFailed(creationError))
                        completeWidePixelFlow(with: error)
                    case .purchaseFailed(let purchaseError):
                        subscriptionErrorReporter.report(subscriptionActivationError: .purchaseFailed(purchaseError))
                        completeWidePixelFlow(with: error)
                    case .cancelledByUser:
                        subscriptionErrorReporter.report(subscriptionActivationError: .cancelledByUser)

                        if let widePixelData {
                            widePixel.completeFlow(widePixelData, status: .cancelled, onComplete: { _, _ in })
                        }
                    case .missingEntitlements:
                        // This case deliberately avoids sending a failure wide pixel in case activation succeeds later
                        subscriptionErrorReporter.report(subscriptionActivationError: .missingEntitlements)
                        DispatchQueue.main.async { [weak self] in
                            self?.notificationCenter.post(name: .subscriptionPageCloseAndOpenPreferences, object: self)
                        }
                        await uiHandler.dismissProgressViewController()
                        return nil
                    case .internalError(let internalError):
                        completeWidePixelFlow(with: internalError ?? error)
                        assertionFailure("Internal error")
                    }

                    await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "completed"))
                }
            }
        } else if subscriptionPlatform == .stripe {
            let emailAccessToken = try? EmailManager().getToken()
            let contextName = await originFrom(originalMessage: message) ?? ""

            if subscriptionFeatureAvailability.isSubscriptionPurchaseWidePixelMeasurementEnabled {
                let data = SubscriptionPurchaseWidePixelData(purchasePlatform: .stripe,
                                                             subscriptionIdentifier: nil, // Not available for Stripe
                                                             freeTrialEligible: true, // Always true for Stripe
                                                             contextData: WidePixelContextData(name: contextName))

                widePixel.startFlow(data)
                self.widePixelData = data
            }

            let result = await stripePurchaseFlow.prepareSubscriptionPurchase(emailAccessToken: emailAccessToken)
            switch result {
            case .success(let success):
                if subscriptionFeatureAvailability.isSubscriptionPurchaseWidePixelMeasurementEnabled, let widePixelData = self.widePixelData {
                    if let accountCreationDuration = success.accountCreationDuration {
                        widePixelData.createAccountDuration = accountCreationDuration
                    }

                    widePixel.updateFlow(widePixelData)
                }

                await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: success.purchaseUpdate)
            case .failure(let error):
                await showSomethingWentWrongAlert()
                switch error {
                case .noProductsFound:
                    subscriptionErrorReporter.report(subscriptionActivationError: .failedToGetSubscriptionOptions)
                case .accountCreationFailed(let creationError):
                    subscriptionErrorReporter.report(subscriptionActivationError: .accountCreationFailed(creationError))
                }

                await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "canceled"))

                if subscriptionFeatureAvailability.isSubscriptionPurchaseWidePixelMeasurementEnabled, let widePixelData = self.widePixelData {
                    widePixelData.markAsFailed(at: .accountCreate, error: error)
                    widePixel.updateFlow(widePixelData)
                    widePixel.completeFlow(widePixelData, status: .failure, onComplete: { _, _ in })
                }
            }
        }

        await uiHandler.dismissProgressViewController()
        return nil
    }

    // MARK: functions used in SubscriptionAccessActionHandlers

    func activateSubscription(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseOfferPageEntry)
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
            PixelKit.fire(PrivacyProPixel.privacyProWelcomeVPN, frequency: .uniqueByName)
            notificationCenter.post(name: .ToggleNetworkProtectionInMainWindow, object: self, userInfo: nil)
        case .dataBrokerProtection:
            PixelKit.fire(PrivacyProPixel.privacyProWelcomePersonalInformationRemoval, frequency: .uniqueByName)
            notificationCenter.post(name: .openPersonalInformationRemoval, object: self, userInfo: nil)
            await uiHandler.showTab(with: .dataBrokerProtection)
        case .identityTheftRestoration, .identityTheftRestorationGlobal:
            PixelKit.fire(PrivacyProPixel.privacyProWelcomeIdentityRestoration, frequency: .uniqueByName)
            let url = subscriptionManager.url(for: .identityTheftRestoration)
            await uiHandler.showTab(with: .identityTheftRestoration(url))
        case .paidAIChat:
            PixelKit.fire(PrivacyProPixel.privacyProWelcomeAIChat, frequency: .uniqueByName)
            await uiHandler.showTab(with: .aiChat(aiChatURL))
        case .unknown:
            break
        }

        return nil
    }

    func completeStripePayment(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        var accountActivationDuration = WidePixel.MeasuredInterval.startingNow()
        widePixelData?.activateAccountDuration = accountActivationDuration

        await uiHandler.presentProgressViewController(withTitle: UserText.completingPurchaseTitle)
        await stripePurchaseFlow.completeSubscriptionPurchase()
        await uiHandler.dismissProgressViewController()

        PixelKit.fire(PrivacyProPixel.privacyProPurchaseStripeSuccess, frequency: .legacyDailyAndCount)
        sendFreemiumSubscriptionPixelIfFreemiumActivated()
        saveSubscriptionUpgradeTimestampIfFreemiumActivated()
        subscriptionSuccessPixelHandler.fireSuccessfulSubscriptionAttributionPixel()
        sendSubscriptionUpgradeFromFreemiumNotificationIfFreemiumActivated()
        notificationCenter.post(name: .subscriptionDidChange, object: self)

        if subscriptionFeatureAvailability.isSubscriptionPurchaseWidePixelMeasurementEnabled, let data = self.widePixelData {
            accountActivationDuration.complete()
            data.activateAccountDuration = accountActivationDuration
            widePixel.updateFlow(data)
            widePixel.completeFlow(data, status: .success, onComplete: { _, _ in })
        }

        return [String: String]() // cannot be nil, the web app expect something back before redirecting the user to the final page
    }

    // MARK: Pixel related actions

    func subscriptionsMonthlyPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        PixelKit.fire(PrivacyProPixel.privacyProOfferMonthlyPriceClick)
        return nil
    }

    func subscriptionsYearlyPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        PixelKit.fire(PrivacyProPixel.privacyProOfferYearlyPriceClick)
        return nil
    }

    func subscriptionsUnknownPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        // Not used
        return nil
    }

    func subscriptionsAddEmailSuccess(params: Any, original: WKScriptMessage) async -> Encodable? {
        PixelKit.fire(PrivacyProPixel.privacyProAddEmailSuccess, frequency: .uniqueByName)
        return nil
    }

    func subscriptionsWelcomeAddEmailClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        PixelKit.fire(PrivacyProPixel.privacyProWelcomeAddDevice, frequency: .uniqueByName)
        return nil
    }

    func subscriptionsWelcomeFaqClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        PixelKit.fire(PrivacyProPixel.privacyProWelcomeFAQClick, frequency: .uniqueByName)
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
            PixelKit.fire(PrivacyProPixel.privacyProOfferScreenImpression)
        default: return
        }
    }

    func showSubscriptionFoundAlert(originalMessage: WKScriptMessage) async {

        switch await uiHandler.dismissProgressViewAndShow(alertType: .subscriptionFound, text: nil) {
        case .alertFirstButtonReturn:
            if #available(macOS 12.0, *) {
                let appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager,
                                                                       storePurchaseManager: subscriptionManager.storePurchaseManager())
                let result = await appStoreRestoreFlow.restoreAccountFromPastPurchase()
                switch result {
                case .success:
                    PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseStoreSuccess, frequency: .legacyDailyAndCount)
                case .failure(let error):
                    Logger.subscription.error("Failed to restore account from past purchase: \(error, privacy: .public)")
                }
                Task { @MainActor in
                    originalMessage.webView?.reload()
                }
            }
        default: return
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
extension SubscriptionPagesUseSubscriptionFeatureV2: SubscriptionAccessActionHandling {

    func subscriptionAccessActionRestorePurchases(message: WKScriptMessage) {
        if #available(macOS 12.0, *) {
            Task { @MainActor in
                let appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager,
                                                                       storePurchaseManager: subscriptionManager.storePurchaseManager())
                let subscriptionAppStoreRestorer = DefaultSubscriptionAppStoreRestorerV2(subscriptionManager: self.subscriptionManager,
                                                                                         appStoreRestoreFlow: appStoreRestoreFlow,
                                                                                         uiHandler: self.uiHandler)
                await subscriptionAppStoreRestorer.restoreAppStoreSubscription()
                message.webView?.reload()
            }
        }
    }

    func subscriptionAccessActionOpenURLHandler(url: URL) {
        Task {
            await self.uiHandler.showTab(with: .subscription(url))
        }
    }
}

private extension SubscriptionPagesUseSubscriptionFeatureV2 {

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

    /// Retrieves free trial subscription options for App Store.
    ///
    /// - Returns: A `SubscriptionOptionsV2` object containing the relevant subscription options, or nil if unavailable.
    ///   If free trial options are unavailable, falls back to standard subscription options.
    ///   This fallback could occur if the Free Trial offer in AppStoreConnect had an end date in the past.
    @available(macOS 12.0, *)
    func freeTrialSubscriptionOptions() async -> SubscriptionOptionsV2? {
        guard let options = await subscriptionManager.storePurchaseManager().freeTrialSubscriptionOptions() else {
            return await subscriptionManager.storePurchaseManager().subscriptionOptions()
        }
        return options
    }
}
