//
//  SubscriptionPagesUseSubscriptionFeature.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Common
import Foundation
import WebKit
import UserScript
import Combine
import Subscription
import Core
import os.log
import Networking

struct SubscriptionPagesUseSubscriptionFeatureConstants {
    static let featureName = "useSubscription"
    static let os = "ios"
    static let empty = ""
    static let token = "token"
}

private struct OriginDomains {
    static let duckduckgo = "duckduckgo.com"
    static let abrown = "abrown.duckduckgo.com"
}

private struct Handlers {
    // Auth V1
    static let getSubscription = "getSubscription"
    static let setSubscription = "setSubscription"
    // Auth V2
    static let setAuthTokens = "setAuthTokens"
    static let getAuthAccessToken = "getAuthAccessToken"
    static let getFeatureConfig = "getFeatureConfig"
    // ---
    static let backToSettings = "backToSettings"
    static let getSubscriptionOptions = "getSubscriptionOptions"
    static let subscriptionSelected = "subscriptionSelected"
    static let activateSubscription = "activateSubscription"
    static let featureSelected = "featureSelected"
    // Pixels related events
    static let subscriptionsMonthlyPriceClicked = "subscriptionsMonthlyPriceClicked"
    static let subscriptionsYearlyPriceClicked = "subscriptionsYearlyPriceClicked"
    static let subscriptionsUnknownPriceClicked = "subscriptionsUnknownPriceClicked"
    static let subscriptionsAddEmailSuccess = "subscriptionsAddEmailSuccess"
    static let subscriptionsWelcomeAddEmailClicked = "subscriptionsWelcomeAddEmailClicked"
    static let subscriptionsWelcomeFaqClicked = "subscriptionsWelcomeFaqClicked"
    static let getAccessToken = "getAccessToken"
}

enum UseSubscriptionError: Error {
    case purchaseFailed,
         missingEntitlements,
         failedToGetSubscriptionOptions,
         failedToSetSubscription,
         cancelledByUser,
         accountCreationFailed,
         activeSubscriptionAlreadyPresent,
         restoreFailedDueToNoSubscription,
         restoreFailedDueToExpiredSubscription,
         otherRestoreError,
         generalError
}

enum SubscriptionTransactionStatus: String {
    case idle, purchasing, restoring, polling
}

// https://app.asana.com/0/1205842942115003/1209254337758531/f
public struct GetFeatureConfigurationResponse: Encodable {
    let useUnifiedFeedback: Bool = true
    let useSubscriptionsAuthV2: Bool
    let usePaidDuckAi: Bool
}

public struct AccessTokenValue: Codable {
    let accessToken: String
}

protocol SubscriptionPagesUseSubscriptionFeature: Subfeature, ObservableObject {
    var transactionStatusPublisher: Published<SubscriptionTransactionStatus>.Publisher { get }
    var transactionStatus: SubscriptionTransactionStatus { get }
    var transactionErrorPublisher: Published<UseSubscriptionError?>.Publisher { get }
    var transactionError: UseSubscriptionError? { get }

    var onSetSubscription: (() -> Void)? { get set }
    var onBackToSettings: (() -> Void)? { get set }
    var onFeatureSelected: ((Entitlement.ProductName) -> Void)? { get set }
    var onActivateSubscription: (() -> Void)? { get set }

    func with(broker: UserScriptMessageBroker)
    func handler(forMethodNamed methodName: String) -> Subfeature.Handler?

    func getSubscriptionOptions(params: Any, original: WKScriptMessage) async -> Encodable?
    func subscriptionSelected(params: Any, original: WKScriptMessage) async -> Encodable?
    // Auth V1
    func getSubscription(params: Any, original: WKScriptMessage) async -> Encodable?
    func setSubscription(params: Any, original: WKScriptMessage) async -> Encodable?
    // Auth V2
    func setAuthTokens(params: Any, original: WKScriptMessage) async throws -> Encodable?
    func getAuthAccessToken(params: Any, original: WKScriptMessage) async throws -> Encodable?
    func getFeatureConfig(params: Any, original: WKScriptMessage) async throws -> Encodable?
    // ---
    func activateSubscription(params: Any, original: WKScriptMessage) async -> Encodable?
    func featureSelected(params: Any, original: WKScriptMessage) async -> Encodable?
    func backToSettings(params: Any, original: WKScriptMessage) async -> Encodable?
    func getAccessToken(params: Any, original: WKScriptMessage) async throws -> Encodable?

    func subscriptionsMonthlyPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable?
    func subscriptionsYearlyPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable?
    func subscriptionsUnknownPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable?
    func subscriptionsAddEmailSuccess(params: Any, original: WKScriptMessage) async -> Encodable?
    func subscriptionsWelcomeAddEmailClicked(params: Any, original: WKScriptMessage) async -> Encodable?
    func subscriptionsWelcomeFaqClicked(params: Any, original: WKScriptMessage) async -> Encodable?

    func pushPurchaseUpdate(originalMessage: WKScriptMessage, purchaseUpdate: PurchaseUpdate) async
    func restoreAccountFromAppStorePurchase() async throws
    func cleanup()
}

final class DefaultSubscriptionPagesUseSubscriptionFeature: SubscriptionPagesUseSubscriptionFeature {

    private let subscriptionAttributionOrigin: String?
    private let subscriptionManager: SubscriptionManager
    private let subscriptionFeatureAvailability: SubscriptionFeatureAvailability
    private var accountManager: AccountManager { subscriptionManager.accountManager }
    private let appStorePurchaseFlow: AppStorePurchaseFlow
    private let appStoreRestoreFlow: AppStoreRestoreFlow
    private let appStoreAccountManagementFlow: AppStoreAccountManagementFlow
    private let privacyProDataReporter: PrivacyProDataReporting?
    private let subscriptionFreeTrialsHelper: SubscriptionFreeTrialsHelping

    init(subscriptionManager: SubscriptionManager,
         subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
         subscriptionAttributionOrigin: String?,
         appStorePurchaseFlow: AppStorePurchaseFlow,
         appStoreRestoreFlow: AppStoreRestoreFlow,
         appStoreAccountManagementFlow: AppStoreAccountManagementFlow,
         privacyProDataReporter: PrivacyProDataReporting? = nil,
         subscriptionFreeTrialsHelper: SubscriptionFreeTrialsHelping = SubscriptionFreeTrialsHelper()) {
        self.subscriptionManager = subscriptionManager
        self.subscriptionFeatureAvailability = subscriptionFeatureAvailability
        self.appStorePurchaseFlow = appStorePurchaseFlow
        self.appStoreRestoreFlow = appStoreRestoreFlow
        self.appStoreAccountManagementFlow = appStoreAccountManagementFlow
        self.subscriptionAttributionOrigin = subscriptionAttributionOrigin
        self.privacyProDataReporter = subscriptionAttributionOrigin != nil ? privacyProDataReporter : nil
        self.subscriptionFreeTrialsHelper = subscriptionFreeTrialsHelper
    }

    // Transaction Status and errors are observed from ViewModels to handle errors in the UI
    @Published private(set) var transactionStatus: SubscriptionTransactionStatus = .idle
    var transactionStatusPublisher: Published<SubscriptionTransactionStatus>.Publisher { $transactionStatus }
    @Published private(set) var transactionError: UseSubscriptionError?
    var transactionErrorPublisher: Published<UseSubscriptionError?>.Publisher { $transactionError }

    // Subscription Activation Actions
    var onSetSubscription: (() -> Void)?
    var onBackToSettings: (() -> Void)?
    var onFeatureSelected: ((Entitlement.ProductName) -> Void)?
    var onActivateSubscription: (() -> Void)?

    struct FeatureSelection: Codable {
        let productFeature: Entitlement.ProductName
    }

    weak var broker: UserScriptMessageBroker?

    var featureName = SubscriptionPagesUseSubscriptionFeatureConstants.featureName
    lazy var messageOriginPolicy: MessageOriginPolicy = .only(rules: [
        HostnameMatchingRule.makeExactRule(for: subscriptionManager.url(for: .baseURL)) ?? .exact(hostname: OriginDomains.duckduckgo)
    ])

    var originalMessage: WKScriptMessage?

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {

        Logger.subscription.debug("WebView handler: \(methodName)")
        switch methodName {
        case Handlers.getSubscription: return getSubscription
        case Handlers.setSubscription: return setSubscription
        case Handlers.getSubscriptionOptions: return getSubscriptionOptions
        case Handlers.subscriptionSelected: return subscriptionSelected
        case Handlers.activateSubscription: return activateSubscription
        case Handlers.featureSelected: return featureSelected
        case Handlers.backToSettings: return backToSettings
            // Pixel related events
        case Handlers.subscriptionsMonthlyPriceClicked: return subscriptionsMonthlyPriceClicked
        case Handlers.subscriptionsYearlyPriceClicked: return subscriptionsYearlyPriceClicked
        case Handlers.subscriptionsUnknownPriceClicked: return subscriptionsUnknownPriceClicked
        case Handlers.subscriptionsAddEmailSuccess: return subscriptionsAddEmailSuccess
        case Handlers.subscriptionsWelcomeAddEmailClicked: return subscriptionsWelcomeAddEmailClicked
        case Handlers.subscriptionsWelcomeFaqClicked: return subscriptionsWelcomeFaqClicked
        case Handlers.getAccessToken: return getAccessToken
        default:
            Logger.subscription.error("Unhandled web message: \(methodName)")
            return nil
        }
    }

    /// Values that the Frontend can use to determine the current state.
    // swiftlint:disable nesting
    struct SubscriptionValues: Codable {
        enum CodingKeys: String, CodingKey {
            case token
        }
        let token: String
    }
    // swiftlint:enable nesting

    private func resetSubscriptionFlow() {
        setTransactionError(nil)
    }

    private func setTransactionError(_ error: UseSubscriptionError?) {
        transactionError = error
    }

    private func setTransactionStatus(_ status: SubscriptionTransactionStatus) {
        if status != transactionStatus {
            Logger.subscription.debug("Transaction state updated: \(status.rawValue)")
            transactionStatus = status
        }
    }

    // MARK: Broker Methods (Called from WebView via UserScripts)

    func getSubscription(params: Any, original: WKScriptMessage) async -> Encodable? {
        guard accountManager.isUserAuthenticated else { return [SubscriptionPagesUseSubscriptionFeatureConstants.token: SubscriptionPagesUseSubscriptionFeatureConstants.empty] }

        switch await appStoreAccountManagementFlow.refreshAuthTokenIfNeeded() {
        case .success(let currentAuthToken):
            return [SubscriptionPagesUseSubscriptionFeatureConstants.token: currentAuthToken]
        case .failure:
            return [SubscriptionPagesUseSubscriptionFeatureConstants.token: SubscriptionPagesUseSubscriptionFeatureConstants.empty]
        }
    }

    func getSubscriptionOptions(params: Any, original: WKScriptMessage) async -> Encodable? {
        resetSubscriptionFlow()

        var subscriptionOptions: SubscriptionOptions?

        if subscriptionFreeTrialsHelper.areFreeTrialsEnabled {
            subscriptionOptions = await freeTrialSubscriptionOptions()
        } else {
            subscriptionOptions = await subscriptionManager.storePurchaseManager().subscriptionOptions()
        }

        if let subscriptionOptions {
            if subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed {
                return subscriptionOptions
            } else {
                return subscriptionOptions.withoutPurchaseOptions()
            }
        } else {
            Logger.subscription.error("Failed to obtain subscription options")
            setTransactionError(.failedToGetSubscriptionOptions)
            return SubscriptionOptions.empty
        }
    }

    func subscriptionSelected(params: Any, original: WKScriptMessage) async -> Encodable? {

        DailyPixel.fireDailyAndCount(pixel: .privacyProPurchaseAttempt,
                                     pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
        setTransactionError(nil)
        setTransactionStatus(.purchasing)
        resetSubscriptionFlow()

        struct SubscriptionSelection: Decodable {
            struct Experiment: Codable {
                let name: String
                let cohort: String

                func asParameters() -> [String: String] {
                    [
                        "experimentName": name,
                        "experimentCohort": cohort,
                    ]
                }
            }

            let id: String
            let experiment: Experiment?
        }

        let message = original
        guard let subscriptionSelection: SubscriptionSelection = DecodableHelper.decode(from: params) else {
            assertionFailure("SubscriptionPagesUserScript: expected JSON representation of SubscriptionSelection")
            Logger.subscription.error("SubscriptionPagesUserScript: expected JSON representation of SubscriptionSelection")
            setTransactionStatus(.idle)
            return nil
        }

        // Check for active subscriptions
        if await subscriptionManager.storePurchaseManager().hasActiveSubscription() {
            Logger.subscription.debug("Subscription already active")
            setTransactionError(.activeSubscriptionAlreadyPresent)
            Pixel.fire(pixel: .privacyProRestoreAfterPurchaseAttempt)
            setTransactionStatus(.idle)
            return nil
        }

        let emailAccessToken = try? EmailManager().getToken()
        let purchaseTransactionJWS: String

        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelection.id,
                                                               emailAccessToken: emailAccessToken) {
        case .success(let transactionJWS):
            Logger.subscription.debug("Subscription purchased successfully")
            purchaseTransactionJWS = transactionJWS

        case .failure(let error):
            Logger.subscription.error("App store purchase error: \(error.localizedDescription)")
            setTransactionStatus(.idle)
            switch error {
            case .cancelledByUser:
                setTransactionError(.cancelledByUser)
                await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "canceled"))
                return nil
            case .accountCreationFailed:
                setTransactionError(.accountCreationFailed)
            case .activeSubscriptionAlreadyPresent:
                setTransactionError(.activeSubscriptionAlreadyPresent)
            default:
                setTransactionError(.purchaseFailed)
            }
            originalMessage = original
            return nil
        }

        setTransactionStatus(.polling)

        var subscriptionParameters: [String: String]?
        if let frontEndExperiment = subscriptionSelection.experiment {
            subscriptionParameters = frontEndExperiment.asParameters()
        }

        switch await appStorePurchaseFlow.completeSubscriptionPurchase(with: purchaseTransactionJWS, additionalParams: subscriptionParameters) {
        case .success(let purchaseUpdate):
            Logger.subscription.debug("Subscription purchase completed successfully")
            DailyPixel.fireDailyAndCount(pixel: .privacyProPurchaseSuccess,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
            UniquePixel.fire(pixel: .privacyProSubscriptionActivated)
            Pixel.fireAttribution(pixel: .privacyProSuccessfulSubscriptionAttribution, origin: subscriptionAttributionOrigin, privacyProDataReporter: privacyProDataReporter)
            setTransactionStatus(.idle)
            await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: purchaseUpdate)
        case .failure(let error):
            Logger.subscription.error("App store complete subscription purchase error: \(error.localizedDescription)")
            setTransactionStatus(.idle)
            setTransactionError(.missingEntitlements)
            await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "completed"))
        }
        return nil
    }

    func setSubscription(params: Any, original: WKScriptMessage) async -> Encodable? {
        guard let subscriptionValues: SubscriptionValues = DecodableHelper.decode(from: params) else {
            assertionFailure("SubscriptionPagesUserScript: expected JSON representation of SubscriptionValues")
            Logger.subscription.error("SubscriptionPagesUserScript: expected JSON representation of SubscriptionValues")
            setTransactionError(.generalError)
            return nil
        }

        // Clear subscription Cache
        subscriptionManager.subscriptionEndpointService.signOut()

        let authToken = subscriptionValues.token
        if case let .success(accessToken) = await accountManager.exchangeAuthTokenToAccessToken(authToken),
           case let .success(accountDetails) = await accountManager.fetchAccountDetails(with: accessToken) {
            accountManager.storeAuthToken(token: authToken)
            accountManager.storeAccount(token: accessToken, email: accountDetails.email, externalID: accountDetails.externalID)
            onSetSubscription?()
        } else {
            Logger.subscription.error("Failed to set subscription")
            setTransactionError(.failedToSetSubscription)
        }

        return nil
    }

    // Auth V2 unused methods
    func setAuthTokens(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        assertionFailure("SubscriptionPagesUserScript: setAuthTokens not implemented")
        return nil
    }

    func getAuthAccessToken(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        assertionFailure("SubscriptionPagesUserScript: getAuthAccessToken not implemented")
        return nil
    }

    func getFeatureConfig(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        assertionFailure("SubscriptionPagesUserScript: getFeatureConfig not implemented")
        return nil
    }

    func activateSubscription(params: Any, original: WKScriptMessage) async -> Encodable? {
        Pixel.fire(pixel: .privacyProRestorePurchaseOfferPageEntry, debounce: 2)
        onActivateSubscription?()
        return nil
    }

    func featureSelected(params: Any, original: WKScriptMessage) async -> Encodable? {
        guard let featureSelection: FeatureSelection = DecodableHelper.decode(from: params) else {
            assertionFailure("SubscriptionPagesUserScript: expected JSON representation of FeatureSelection")
            Logger.subscription.error("SubscriptionPagesUserScript: expected JSON representation of FeatureSelection")
            return nil
        }

        onFeatureSelected?(featureSelection.productFeature)

        return nil
    }

    func backToSettings(params: Any, original: WKScriptMessage) async -> Encodable? {
        guard let accessToken = accountManager.accessToken else {
            Logger.subscription.error("Missing access token")
            return nil
        }

        switch await accountManager.fetchAccountDetails(with: accessToken) {
        case .success(let accountDetails):
            switch await subscriptionManager.subscriptionEndpointService.getSubscription(accessToken: accessToken) {
            case .success:
                accountManager.storeAccount(token: accessToken,
                                            email: accountDetails.email,
                                            externalID: accountDetails.externalID)
                onBackToSettings?()
            case .failure(let error):
                Logger.subscription.error("Error retrieving subscription details: \(error.localizedDescription)")
            }
        case .failure(let error):
            Logger.subscription.error("Could not get account Details: \(error.localizedDescription)")
            setTransactionError(.generalError)
        }
        return nil
    }

    func getAccessToken(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        if let accessToken = subscriptionManager.accountManager.accessToken {
            return [SubscriptionPagesUseSubscriptionFeatureConstants.token: accessToken]
        } else {
            return [String: String]()
        }
    }

    // MARK: Pixel related actions

    func subscriptionsMonthlyPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.subscription.debug("Web function called: \(#function)")
        Pixel.fire(pixel: .privacyProOfferMonthlyPriceClick)
        return nil
    }

    func subscriptionsYearlyPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.subscription.debug("Web function called: \(#function)")
        Pixel.fire(pixel: .privacyProOfferYearlyPriceClick)
        return nil
    }

    func subscriptionsUnknownPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        // Not used
        Logger.subscription.debug("Web function called: \(#function)")
        return nil
    }

    func subscriptionsAddEmailSuccess(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.subscription.debug("Web function called: \(#function)")
        UniquePixel.fire(pixel: .privacyProAddEmailSuccess)
        return nil
    }

    func subscriptionsWelcomeAddEmailClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.subscription.debug("Web function called: \(#function)")
        UniquePixel.fire(pixel: .privacyProWelcomeAddDevice)
        return nil
    }

    func subscriptionsWelcomeFaqClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.subscription.debug("Web function called: \(#function)")
        UniquePixel.fire(pixel: .privacyProWelcomeFAQClick)
        return nil
    }

    // MARK: Push actions (Push Data back to WebViews)

    enum SubscribeActionName: String {
        case onPurchaseUpdate
    }

    @MainActor
    func pushPurchaseUpdate(originalMessage: WKScriptMessage, purchaseUpdate: PurchaseUpdate) async {
        guard let webView = originalMessage.webView else { return }

        pushAction(method: .onPurchaseUpdate, webView: webView, params: purchaseUpdate)
    }

    func pushAction(method: SubscribeActionName, webView: WKWebView, params: Encodable) {
        let broker = UserScriptMessageBroker(context: SubscriptionPagesUserScript.context, requiresRunInPageContentWorld: true )
        broker.push(method: method.rawValue, params: params, for: self, into: webView)
    }

    // MARK: Native methods - Called from ViewModels

    func restoreAccountFromAppStorePurchase() async throws {
        setTransactionStatus(.restoring)
        let result = await appStoreRestoreFlow.restoreAccountFromPastPurchase()
        switch result {
        case .success:
            setTransactionStatus(.idle)
        case .failure(let error):
            let mappedError = mapAppStoreRestoreErrorToTransactionError(error)
            setTransactionStatus(.idle)
            throw mappedError
        }
    }

    // MARK: Utility Methods

    func mapAppStoreRestoreErrorToTransactionError(_ error: AppStoreRestoreFlowError) -> UseSubscriptionError {
        Logger.subscription.error("\(#function): \(error.localizedDescription)")
        switch error {
        case .subscriptionExpired:
            return .restoreFailedDueToExpiredSubscription
        case .missingAccountOrTransactions:
            return .restoreFailedDueToNoSubscription
        default:
            return .otherRestoreError
        }
    }

    func cleanup() {
        setTransactionStatus(.idle)
        setTransactionError(nil)
        broker = nil
        onFeatureSelected = nil
        onSetSubscription = nil
        onActivateSubscription = nil
        onBackToSettings = nil
    }
}

private extension DefaultSubscriptionPagesUseSubscriptionFeature {
    /// Retrieves free trial subscription options.
    ///
    /// - Returns: A `SubscriptionOptions` object containing the relevant subscription options.
    func freeTrialSubscriptionOptions() async -> SubscriptionOptions? {
        guard let subscriptionOptions = await subscriptionManager.storePurchaseManager().freeTrialSubscriptionOptions() else {
            /*
             Fallback to standard subscription options if nil.
             This could occur if the Free Trial offer in AppStoreConnect had an end date in the past.
             */
            return await subscriptionManager.storePurchaseManager().subscriptionOptions()
        }
        return subscriptionOptions
    }
}

final class DefaultSubscriptionPagesUseSubscriptionFeatureV2: SubscriptionPagesUseSubscriptionFeature {

    private let subscriptionAttributionOrigin: String?
    private let subscriptionManager: SubscriptionManagerV2
    private let appStorePurchaseFlow: AppStorePurchaseFlowV2
    private let appStoreRestoreFlow: AppStoreRestoreFlowV2
    private let subscriptionFeatureAvailability: SubscriptionFeatureAvailability
    private let privacyProDataReporter: PrivacyProDataReporting?
    private let subscriptionFreeTrialsHelper: SubscriptionFreeTrialsHelping

    init(subscriptionManager: SubscriptionManagerV2,
         subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
         subscriptionAttributionOrigin: String?,
         appStorePurchaseFlow: AppStorePurchaseFlowV2,
         appStoreRestoreFlow: AppStoreRestoreFlowV2,
         privacyProDataReporter: PrivacyProDataReporting? = nil,
         subscriptionFreeTrialsHelper: SubscriptionFreeTrialsHelping = SubscriptionFreeTrialsHelper()) {
        self.subscriptionManager = subscriptionManager
        self.subscriptionFeatureAvailability = subscriptionFeatureAvailability
        self.appStorePurchaseFlow = appStorePurchaseFlow
        self.appStoreRestoreFlow = appStoreRestoreFlow
        self.subscriptionAttributionOrigin = subscriptionAttributionOrigin
        self.privacyProDataReporter = subscriptionAttributionOrigin != nil ? privacyProDataReporter : nil
        self.subscriptionFreeTrialsHelper = subscriptionFreeTrialsHelper
    }

    // Transaction Status and errors are observed from ViewModels to handle errors in the UI
    @Published private(set) var transactionStatus: SubscriptionTransactionStatus = .idle
    var transactionStatusPublisher: Published<SubscriptionTransactionStatus>.Publisher { $transactionStatus }
    @Published private(set) var transactionError: UseSubscriptionError?
    var transactionErrorPublisher: Published<UseSubscriptionError?>.Publisher { $transactionError }

    // Subscription Activation Actions
    var onSetSubscription: (() -> Void)?
    var onBackToSettings: (() -> Void)?
    var onFeatureSelected: ((Entitlement.ProductName) -> Void)?
    var onActivateSubscription: (() -> Void)?

    struct FeatureSelection: Codable {
        let productFeature: SubscriptionEntitlement
    }

    weak var broker: UserScriptMessageBroker?

    var featureName = SubscriptionPagesUseSubscriptionFeatureConstants.featureName
    lazy var messageOriginPolicy: MessageOriginPolicy = .only(rules: [
        HostnameMatchingRule.makeExactRule(for: subscriptionManager.url(for: .baseURL)) ?? .exact(hostname: OriginDomains.duckduckgo)
    ])

    var originalMessage: WKScriptMessage?

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        Logger.subscription.debug("WebView handler: \(methodName)")

        switch methodName {
        case Handlers.setAuthTokens: return setAuthTokens
        case Handlers.getAuthAccessToken: return getAuthAccessToken
        case Handlers.getFeatureConfig: return getFeatureConfig
        case Handlers.getSubscriptionOptions: return getSubscriptionOptions
        case Handlers.subscriptionSelected: return subscriptionSelected
        case Handlers.activateSubscription: return activateSubscription
        case Handlers.featureSelected: return featureSelected
        case Handlers.backToSettings: return backToSettings
            // Pixel related events
        case Handlers.subscriptionsMonthlyPriceClicked: return subscriptionsMonthlyPriceClicked
        case Handlers.subscriptionsYearlyPriceClicked: return subscriptionsYearlyPriceClicked
        case Handlers.subscriptionsUnknownPriceClicked: return subscriptionsUnknownPriceClicked
        case Handlers.subscriptionsAddEmailSuccess: return subscriptionsAddEmailSuccess
        case Handlers.subscriptionsWelcomeAddEmailClicked: return subscriptionsWelcomeAddEmailClicked
        case Handlers.subscriptionsWelcomeFaqClicked: return subscriptionsWelcomeFaqClicked
        case Handlers.getAccessToken: return getAccessToken
        default:
            Logger.subscription.error("Unhandled web message: \(methodName)")
            return nil
        }
    }

    /// Values that the Frontend can use to determine the current state.
    // swiftlint:disable nesting
    struct SubscriptionValues: Codable {
        enum CodingKeys: String, CodingKey {
            case token
        }
        let token: String
    }
    // swiftlint:enable nesting

    private func resetSubscriptionFlow() {
        setTransactionError(nil)
    }

    private func setTransactionError(_ error: UseSubscriptionError?) {
        transactionError = error
    }

    private func setTransactionStatus(_ status: SubscriptionTransactionStatus) {
        if status != transactionStatus {
            Logger.subscription.log("Transaction state updated: \(status.rawValue)")
            transactionStatus = status
        }
    }

    // MARK: Broker Methods (Called from WebView via UserScripts)

    // MARK: - Auth V2

    // https://app.asana.com/0/0/1209325145462549
    struct SubscriptionValuesV2: Codable {
        let accessToken: String
        let refreshToken: String
    }
    
    func setAuthTokens(params: Any, original: WKScriptMessage) async throws -> Encodable? {

        guard let subscriptionValues: SubscriptionValuesV2 = CodableHelper.decode(from: params) else {
            Logger.subscription.fault("SubscriptionPagesUserScript: expected JSON representation of SubscriptionValues")
            assertionFailure("SubscriptionPagesUserScript: expected JSON representation of SubscriptionValues")
            setTransactionError(.generalError)
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
            setTransactionError(.failedToSetSubscription)
        }
        return nil
    }

    func getAuthAccessToken(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        let tokenContainer = try? await subscriptionManager.getTokenContainer(policy: .localValid)
        return AccessTokenValue(accessToken: tokenContainer?.accessToken ?? "")
    }

    func getFeatureConfig(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        return GetFeatureConfigurationResponse(useSubscriptionsAuthV2: true, usePaidDuckAi: subscriptionFeatureAvailability.isPaidAIChatEnabled)
    }

    // Auth V1 unused methods

    func getSubscription(params: Any, original: WKScriptMessage) async -> Encodable? {
        assertionFailure("SubscriptionPagesUserScript: getSubscription not implemented")
        return nil
    }

    func setSubscription(params: Any, original: WKScriptMessage) async -> Encodable? {
        assertionFailure("SubscriptionPagesUserScript: setSubscription not implemented")
        return nil
    }

    // MARK: -

    func getSubscriptionOptions(params: Any, original: WKScriptMessage) async -> Encodable? {
        resetSubscriptionFlow()

        var subscriptionOptions: SubscriptionOptionsV2?

        if subscriptionFreeTrialsHelper.areFreeTrialsEnabled {
            subscriptionOptions = await freeTrialSubscriptionOptions()
        } else {
            subscriptionOptions = await subscriptionManager.storePurchaseManager().subscriptionOptions()
        }

        if let subscriptionOptions {
            if subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed {
                return subscriptionOptions
            } else {
                return subscriptionOptions.withoutPurchaseOptions()
            }
        } else {
            Logger.subscription.error("Failed to obtain subscription options")
            setTransactionError(.failedToGetSubscriptionOptions)
            return SubscriptionOptionsV2.empty
        }
    }

    func subscriptionSelected(params: Any, original: WKScriptMessage) async -> Encodable? {

        DailyPixel.fireDailyAndCount(pixel: .privacyProPurchaseAttempt,
                                     pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
        setTransactionError(nil)
        setTransactionStatus(.purchasing)
        resetSubscriptionFlow()

        struct SubscriptionSelection: Decodable {
            struct Experiment: Codable {
                let name: String
                let cohort: String

                func asParameters() -> [String: String] {
                    [
                        "experimentName": name,
                        "experimentCohort": cohort,
                    ]
                }
            }

            let id: String
            let experiment: Experiment?
        }

        let message = original
        guard let subscriptionSelection: SubscriptionSelection = CodableHelper.decode(from: params) else {
            assertionFailure("SubscriptionPagesUserScript: expected JSON representation of SubscriptionSelection")
            Logger.subscription.error("SubscriptionPagesUserScript: expected JSON representation of SubscriptionSelection")
            setTransactionStatus(.idle)
            return nil
        }

        // Check for active subscriptions
        if await subscriptionManager.storePurchaseManager().hasActiveSubscription() {
            Logger.subscription.log("Subscription already active")
            setTransactionError(.activeSubscriptionAlreadyPresent)
            Pixel.fire(pixel: .privacyProRestoreAfterPurchaseAttempt)
            setTransactionStatus(.idle)
            return nil
        }

        let purchaseTransactionJWS: String

        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelection.id) {
        case .success(let transactionJWS):
            Logger.subscription.log("Subscription purchased successfully")
            purchaseTransactionJWS = transactionJWS

        case .failure(let error):
            Logger.subscription.error("App store purchase error: \(error.localizedDescription)")
            setTransactionStatus(.idle)
            switch error {
            case .cancelledByUser:
                setTransactionError(.cancelledByUser)
                await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate.canceled)
                return nil
            case .accountCreationFailed:
                setTransactionError(.accountCreationFailed)
            case .activeSubscriptionAlreadyPresent:
                setTransactionError(.activeSubscriptionAlreadyPresent)
            default:
                setTransactionError(.purchaseFailed)
            }
            originalMessage = original
            return nil
        }

        setTransactionStatus(.polling)

        guard purchaseTransactionJWS.isEmpty == false else {
            Logger.subscription.fault("Purchase transaction JWS is empty")
            assertionFailure("Purchase transaction JWS is empty")
            setTransactionStatus(.idle)
            return nil
        }

        var subscriptionParameters: [String: String]?
        if let frontEndExperiment = subscriptionSelection.experiment {
            subscriptionParameters = frontEndExperiment.asParameters()
        }

        switch await appStorePurchaseFlow.completeSubscriptionPurchase(with: purchaseTransactionJWS,
                                                                       additionalParams: subscriptionParameters) {
        case .success:
            Logger.subscription.log("Subscription purchase completed successfully")
            DailyPixel.fireDailyAndCount(pixel: .privacyProPurchaseSuccess,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
            UniquePixel.fire(pixel: .privacyProSubscriptionActivated)
            Pixel.fireAttribution(pixel: .privacyProSuccessfulSubscriptionAttribution, origin: subscriptionAttributionOrigin, privacyProDataReporter: privacyProDataReporter)
            setTransactionStatus(.idle)
            await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate.completed)
        case .failure(let error):
            Logger.subscription.error("App store complete subscription purchase error: \(error, privacy: .public)")

            await subscriptionManager.signOut(notifyUI: true)

            setTransactionStatus(.idle)
            setTransactionError(.missingEntitlements)
            await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate.completed)
        }
        return nil
    }

    func activateSubscription(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.subscription.log("Activating Subscription")
        Pixel.fire(pixel: .privacyProRestorePurchaseOfferPageEntry, debounce: 2)
        onActivateSubscription?()
        return nil
    }

    func featureSelected(params: Any, original: WKScriptMessage) async -> Encodable? {
        guard let featureSelection: FeatureSelection = CodableHelper.decode(from: params) else {
            assertionFailure("SubscriptionPagesUserScript: expected JSON representation of FeatureSelection")
            Logger.subscription.error("SubscriptionPagesUserScript: expected JSON representation of FeatureSelection")
            return nil
        }

        switch featureSelection.productFeature {
        case .networkProtection:
            onFeatureSelected?(.networkProtection)
        case .dataBrokerProtection:
            onFeatureSelected?(.dataBrokerProtection)
        case .identityTheftRestoration:
            onFeatureSelected?(.identityTheftRestoration)
        case .identityTheftRestorationGlobal:
            onFeatureSelected?(.identityTheftRestorationGlobal)
        case .paidAIChat:
            // Follow up: Implement paidAIChat selection
            break
        case .unknown:
            break
        }

        return nil
    }

    func backToSettings(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.subscription.log("Back to settings")
        _ = try? await subscriptionManager.getTokenContainer(policy: .localForceRefresh)
        onBackToSettings?()
        return nil
    }

    func getAccessToken(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        do {
            let accessToken = try await subscriptionManager.getTokenContainer(policy: .localValid).accessToken
            return [SubscriptionPagesUseSubscriptionFeatureConstants.token: accessToken]
        } catch {
            Logger.subscription.debug("No access token available: \(error)")
            return [String: String]()
        }
    }

    // MARK: Pixel related actions

    func subscriptionsMonthlyPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.subscription.log("Web function called: \(#function)")
        Pixel.fire(pixel: .privacyProOfferMonthlyPriceClick)
        return nil
    }

    func subscriptionsYearlyPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.subscription.log("Web function called: \(#function)")
        Pixel.fire(pixel: .privacyProOfferYearlyPriceClick)
        return nil
    }

    func subscriptionsUnknownPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        // Not used
        Logger.subscription.log("Web function called: \(#function)")
        return nil
    }

    func subscriptionsAddEmailSuccess(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.subscription.log("Web function called: \(#function)")
        UniquePixel.fire(pixel: .privacyProAddEmailSuccess)
        return nil
    }

    func subscriptionsWelcomeAddEmailClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.subscription.debug("Web function called: \(#function)")
        UniquePixel.fire(pixel: .privacyProWelcomeAddDevice)
        return nil
    }

    func subscriptionsWelcomeFaqClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.subscription.log("Web function called: \(#function)")
        UniquePixel.fire(pixel: .privacyProWelcomeFAQClick)
        return nil
    }

    // MARK: Push actions (Push Data back to WebViews)

    enum SubscribeActionName: String {
        case onPurchaseUpdate
    }

    @MainActor
    func pushPurchaseUpdate(originalMessage: WKScriptMessage, purchaseUpdate: PurchaseUpdate) async {
        guard let webView = originalMessage.webView else { return }

        pushAction(method: .onPurchaseUpdate, webView: webView, params: purchaseUpdate)
    }

    func pushAction(method: SubscribeActionName, webView: WKWebView, params: Encodable) {
        let broker = UserScriptMessageBroker(context: SubscriptionPagesUserScript.context, requiresRunInPageContentWorld: true )
        broker.push(method: method.rawValue, params: params, for: self, into: webView)
    }

    // MARK: Native methods - Called from ViewModels

    func restoreAccountFromAppStorePurchase() async throws {
        setTransactionStatus(.restoring)
        let result = await appStoreRestoreFlow.restoreAccountFromPastPurchase()

        switch result {
        case .success:
            setTransactionStatus(.idle)
            Logger.subscription.log("Subscription restored successfully from App Store purchase")
        case .failure(let error):
            Logger.subscription.error("Failed to restore subscription from App Store purchase: \(error.localizedDescription)")
            setTransactionStatus(.idle)
            throw mapAppStoreRestoreErrorToTransactionError(error)
        }
    }

    // MARK: Utility Methods

    func mapAppStoreRestoreErrorToTransactionError(_ error: AppStoreRestoreFlowErrorV2) -> UseSubscriptionError {
        Logger.subscription.error("\(#function): \(error.localizedDescription)")
        switch error {
        case .subscriptionExpired:
            return .restoreFailedDueToExpiredSubscription
        case .missingAccountOrTransactions:
            return .restoreFailedDueToNoSubscription
        default:
            return .otherRestoreError
        }
    }

    func cleanup() {
        setTransactionStatus(.idle)
        setTransactionError(nil)
        broker = nil
        onFeatureSelected = nil
        onSetSubscription = nil
        onActivateSubscription = nil
        onBackToSettings = nil
    }
}

private extension DefaultSubscriptionPagesUseSubscriptionFeatureV2 {
    /// Retrieves free trial subscription options.
    ///
    /// - Returns: A `SubscriptionOptions` object containing the relevant subscription options.
    func freeTrialSubscriptionOptions() async -> SubscriptionOptionsV2? {
        guard let subscriptionOptions = await subscriptionManager.storePurchaseManager().freeTrialSubscriptionOptions() else {
            /*
             Fallback to standard subscription options if nil.
             This could occur if the Free Trial offer in AppStoreConnect had an end date in the past.
             */
            return await subscriptionManager.storePurchaseManager().subscriptionOptions()
        }
        return subscriptionOptions
    }
}

extension Pixel {

    enum AttributionParameters {
        static let origin = "origin"
        static let locale = "locale"
    }

    static func fireAttribution(pixel: Pixel.Event, origin: String?, locale: Locale = .current, privacyProDataReporter: PrivacyProDataReporting?) {
        var parameters: [String: String] = [:]
        parameters[AttributionParameters.locale] = locale.identifier
        if let origin {
            parameters[AttributionParameters.origin] = origin
        }
        Self.fire(
            pixel: pixel,
            withAdditionalParameters: privacyProDataReporter?.mergeRandomizedParameters(for: .origin(origin), with: parameters) ?? parameters
        )
    }

}
