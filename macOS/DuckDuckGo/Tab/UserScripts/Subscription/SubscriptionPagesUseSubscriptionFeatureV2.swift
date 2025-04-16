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
    private let freemiumDBPPixelExperimentManager: FreemiumDBPPixelExperimentManaging
    private let notificationCenter: NotificationCenter
    /// The `FreemiumDBPExperimentPixelHandler` instance used to fire pixels
    private let freemiumDBPExperimentPixelHandler: EventMapping<FreemiumDBPExperimentPixel>

    public init(subscriptionManager: SubscriptionManagerV2,
                subscriptionSuccessPixelHandler: SubscriptionAttributionPixelHandler = PrivacyProSubscriptionAttributionPixelHandler(),
                stripePurchaseFlow: StripePurchaseFlowV2,
                uiHandler: SubscriptionUIHandling,
                subscriptionFeatureAvailability: SubscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(),
                freemiumDBPUserStateManager: FreemiumDBPUserStateManager = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp),
                freemiumDBPPixelExperimentManager: FreemiumDBPPixelExperimentManaging,
                notificationCenter: NotificationCenter = .default,
                freemiumDBPExperimentPixelHandler: EventMapping<FreemiumDBPExperimentPixel> = FreemiumDBPExperimentPixelHandler()) {
        self.subscriptionManager = subscriptionManager
        self.stripePurchaseFlow = stripePurchaseFlow
        self.subscriptionSuccessPixelHandler = subscriptionSuccessPixelHandler
        self.uiHandler = uiHandler
        self.subscriptionFeatureAvailability = subscriptionFeatureAvailability
        self.freemiumDBPUserStateManager = freemiumDBPUserStateManager
        self.freemiumDBPPixelExperimentManager = freemiumDBPPixelExperimentManager
        self.notificationCenter = notificationCenter
        self.freemiumDBPExperimentPixelHandler = freemiumDBPExperimentPixelHandler
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
            try await subscriptionManager.getSubscription(cachePolicy: .reloadIgnoringLocalCacheData)
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
        return GetFeatureValue(useSubscriptionsAuthV2: true)
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
            if #available(macOS 12.0, *) {
                if let appStoreSubscriptionOptions = await subscriptionManager.storePurchaseManager().subscriptionOptions() {
                    subscriptionOptions = appStoreSubscriptionOptions
                }
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

    func subscriptionSelected(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        PixelKit.fire(PrivacyProPixel.privacyProPurchaseAttempt, frequency: .legacyDailyAndCount)
        struct SubscriptionSelection: Decodable {
            let id: String
        }

        let message = original

        await setPixelOrigin(from: message)

        if subscriptionManager.currentEnvironment.purchasePlatform == .appStore {
            if #available(macOS 12.0, *) {
                guard let subscriptionSelection: SubscriptionSelection = CodableHelper.decode(from: params) else {
                    assertionFailure("SubscriptionPagesUserScript: expected JSON representation of SubscriptionSelection")
                    subscriptionErrorReporter.report(subscriptionActivationError: .generalError)
                    await uiHandler.dismissProgressViewController()
                    return nil
                }

                Logger.subscription.log("[Purchase] Starting purchase for: \(subscriptionSelection.id, privacy: .public)")

                await uiHandler.presentProgressViewController(withTitle: UserText.purchasingSubscriptionTitle)

                // Check for active subscriptions
                if await subscriptionManager.storePurchaseManager().hasActiveSubscription() {
                    // Sandbox note: Looks like our BE is not receiving updates when a subscription transitions from grace period to expired, so during testing we can end up with a subscription in grace period and we will not be able to purchase a new one, only restore it because Transaction.currentEntitlements will not return the subscription to restore.
                    PixelKit.fire(PrivacyProPixel.privacyProRestoreAfterPurchaseAttempt)
                    Logger.subscription.log("[Purchase] Found active subscription during purchase")
                    subscriptionErrorReporter.report(subscriptionActivationError: .hasActiveSubscription)
                    await showSubscriptionFoundAlert(originalMessage: message)
                    await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "canceled"))
                    return nil
                }

                let purchaseTransactionJWS: String
                let appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager,
                                                                       storePurchaseManager: subscriptionManager.storePurchaseManager())
                let appStorePurchaseFlow = DefaultAppStorePurchaseFlowV2(subscriptionManager: subscriptionManager,
                                                                         storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                         appStoreRestoreFlow: appStoreRestoreFlow)

                Logger.subscription.log("[Purchase] Purchasing")
                let purchaseResult = await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelection.id)
                switch purchaseResult {
                case .success(let transactionJWS):
                    purchaseTransactionJWS = transactionJWS
                case .failure(let error):
                    switch error {
                    case .noProductsFound:
                        subscriptionErrorReporter.report(subscriptionActivationError: .subscriptionNotFound)
                    case .activeSubscriptionAlreadyPresent:
                        subscriptionErrorReporter.report(subscriptionActivationError: .activeSubscriptionAlreadyPresent)
                    case .authenticatingWithTransactionFailed:
                        subscriptionErrorReporter.report(subscriptionActivationError: .generalError)
                    case .accountCreationFailed:
                        subscriptionErrorReporter.report(subscriptionActivationError: .accountCreationFailed)
                    case .purchaseFailed:
                        subscriptionErrorReporter.report(subscriptionActivationError: .purchaseFailed)
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
                    return nil
                }

                await uiHandler.updateProgressViewController(title: UserText.completingPurchaseTitle)

                let completePurchaseResult = await appStorePurchaseFlow.completeSubscriptionPurchase(with: purchaseTransactionJWS, additionalParams: nil)
                switch completePurchaseResult {
                case .success(let purchaseUpdate):
                    Logger.subscription.log("[Purchase] Purchase completed")
                    PixelKit.fire(PrivacyProPixel.privacyProPurchaseSuccess, frequency: .legacyDailyAndCount)
                    sendFreemiumSubscriptionPixelIfFreemiumActivated()
                    saveSubscriptionUpgradeTimestampIfFreemiumActivated()
                    PixelKit.fire(PrivacyProPixel.privacyProSubscriptionActivated, frequency: .uniqueByName)
                    subscriptionSuccessPixelHandler.fireSuccessfulSubscriptionAttributionPixel()
                    sendSubscriptionUpgradeFromFreemiumNotificationIfFreemiumActivated()
                    await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: purchaseUpdate)
                case .failure(let error):
                    switch error {
                    case .noProductsFound:
                        subscriptionErrorReporter.report(subscriptionActivationError: .subscriptionNotFound)
                    case .activeSubscriptionAlreadyPresent:
                        subscriptionErrorReporter.report(subscriptionActivationError: .activeSubscriptionAlreadyPresent)
                    case .authenticatingWithTransactionFailed:
                        subscriptionErrorReporter.report(subscriptionActivationError: .generalError)
                    case .accountCreationFailed:
                        subscriptionErrorReporter.report(subscriptionActivationError: .accountCreationFailed)
                    case .purchaseFailed:
                        subscriptionErrorReporter.report(subscriptionActivationError: .purchaseFailed)
                    case .cancelledByUser:
                        subscriptionErrorReporter.report(subscriptionActivationError: .cancelledByUser)
                    case .missingEntitlements:
                        subscriptionErrorReporter.report(subscriptionActivationError: .missingEntitlements)
                        DispatchQueue.main.async { [weak self] in
                            self?.notificationCenter.post(name: .subscriptionPageCloseAndOpenPreferences, object: self)
                        }
                        await uiHandler.dismissProgressViewController()
                        return nil
                    case .internalError:
                        assertionFailure("Internal error")
                    }

                    await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "completed"))
                }
            }
        } else if subscriptionPlatform == .stripe {
            let emailAccessToken = try? EmailManager().getToken()
            let result = await stripePurchaseFlow.prepareSubscriptionPurchase(emailAccessToken: emailAccessToken)
            switch result {
            case .success(let success):
                await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: success)
            case .failure(let error):
                await showSomethingWentWrongAlert()
                switch error {
                case .noProductsFound:
                    subscriptionErrorReporter.report(subscriptionActivationError: .subscriptionNotFound)
                case .accountCreationFailed:
                    subscriptionErrorReporter.report(subscriptionActivationError: .accountCreationFailed)
                }
                await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "canceled"))
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
        case .unknown:
            break
        }

        return nil
    }

    func completeStripePayment(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        await uiHandler.presentProgressViewController(withTitle: UserText.completingPurchaseTitle)
        await stripePurchaseFlow.completeSubscriptionPurchase()
        await uiHandler.dismissProgressViewController()

        PixelKit.fire(PrivacyProPixel.privacyProPurchaseStripeSuccess, frequency: .legacyDailyAndCount)
        sendFreemiumSubscriptionPixelIfFreemiumActivated()
        saveSubscriptionUpgradeTimestampIfFreemiumActivated()
        subscriptionSuccessPixelHandler.fireSuccessfulSubscriptionAttributionPixel()
        sendSubscriptionUpgradeFromFreemiumNotificationIfFreemiumActivated()
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
        PixelKit.fire(PrivacyProPixel.privacyProPurchaseFailure, frequency: .legacyDailyAndCount)
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
    private func setPixelOrigin(from message: WKScriptMessage) async {
        // If the user has performed a Freemium scan, set a Freemium origin and return
        guard !setFreemiumOriginIfScanPerformed() else { return }

        // Else, Extract the origin from the webview URL to use for attribution pixel.
        subscriptionSuccessPixelHandler.origin = await originFrom(originalMessage: message)
    }
}

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

    func subscriptionAccessActionHandleAction(event: SubscriptionAccessActionHandlingEvent) {
        switch event {
        case .activateAddEmailClick:
            PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseEmailStart, frequency: .legacyDailyAndCount)
        default: break
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
            freemiumDBPExperimentPixelHandler.fire(FreemiumDBPExperimentPixel.subscription, parameters: freemiumDBPPixelExperimentManager.pixelParameters)
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

    /// Sets the origin for attribution if the user has started their first Freemium PIR scan
    ///
    /// This method checks whether the user has started their first Freemium PIR scan.
    /// If they have, the method sets the subscription success tracking origin to `"funnel_pro_mac_freemium"` and returns `true`.
    ///
    /// - Returns:
    ///   - `true` if the origin is set because the user has started their first Freemim PIR scan.
    ///   - `false` if a first scan has not been started and the origin is not set.
    func setFreemiumOriginIfScanPerformed() -> Bool {
        let origin = PrivacyProSubscriptionAttributionPixelHandler.Consts.freemiumOrigin
        if freemiumDBPUserStateManager.didPostFirstProfileSavedNotification {
            subscriptionSuccessPixelHandler.origin = origin
            return true
        }
        return false
    }
}
