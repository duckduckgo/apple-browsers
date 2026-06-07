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
import FoundationExtensions
import Foundation
import WebKit
import UserScript
import Combine
import Subscription
import Core
import os.log
import Networking
import PixelKit
import PrivacyConfig
import DataBrokerProtectionCore
import DataBrokerProtection_iOS

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
    static let getSubscriptionTierOptions = "getSubscriptionTierOptions"
    static let subscriptionSelected = "subscriptionSelected"
    static let subscriptionChangeSelected = "subscriptionChangeSelected"
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
    static let completeStripePayment = "completeStripePayment"
}

enum UseSubscriptionError: Error {
    case purchaseFailed,
         purchasePendingTransaction,
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

public enum SubscriptionTransactionStatus: String {
    case idle, purchasing, restoring, polling, changingPlan, planChangePolling
}

// https://app.asana.com/0/1205842942115003/1209254337758531/f
public struct GetFeatureConfigurationResponse: Encodable {
    let useUnifiedFeedback: Bool = true
    let useSubscriptionsAuthV2: Bool = true
    let usePaidDuckAi: Bool
    let useAlternateStripePaymentFlow: Bool
    let useGetSubscriptionTierOptions: Bool = true
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
    var onFeatureSelected: ((SubscriptionEntitlement) -> Void)? { get set }
    var onActivateSubscription: (() -> Void)? { get set }

    func with(broker: UserScriptMessageBroker)
    func handler(forMethodNamed methodName: String) -> Subfeature.Handler?

    func subscriptionSelected(params: Any, original: WKScriptMessage) async -> Encodable?
    // Subscription + Auth
    func getSubscription(params: Any, original: WKScriptMessage) async -> Encodable?
    func setSubscription(params: Any, original: WKScriptMessage) async -> Encodable?
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
    private let appStorePurchaseFlow: AppStorePurchaseFlow
    private let appStoreRestoreFlow: AppStoreRestoreFlow
    private let subscriptionFeatureAvailability: SubscriptionFeatureAvailability
    private let subscriptionDataReporter: SubscriptionDataReporting?
    private let internalUserDecider: InternalUserDecider
    private let wideEvent: WideEventManaging
    private let tierEventReporter: SubscriptionTierEventReporting
    private let pendingTransactionHandler: PendingTransactionHandling
    private let subscriptionFlowsExecuter: SubscriptionFlowsExecuting
    private let freemiumDBPUserStateManager: FreemiumDBPUserStateManaging
    private var purchaseWideEventData: SubscriptionPurchaseWideEventData?
    private var subscriptionRestoreWideEventData: SubscriptionRestoreWideEventData?
    private var planChangeWideEventData: SubscriptionPlanChangeWideEventData?
    private var subscriptionPlatform: SubscriptionEnvironment.PurchasePlatform { subscriptionManager.currentEnvironment.purchasePlatform }
    private let requestValidator: any ScriptRequestValidator

    init(subscriptionManager: SubscriptionManager,
         subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
         subscriptionAttributionOrigin: String?,
         appStorePurchaseFlow: AppStorePurchaseFlow,
         appStoreRestoreFlow: AppStoreRestoreFlow,
         subscriptionDataReporter: SubscriptionDataReporting? = nil,
         internalUserDecider: InternalUserDecider,
         wideEvent: WideEventManaging,
         tierEventReporter: SubscriptionTierEventReporting = DefaultSubscriptionTierEventReporter(),
         pendingTransactionHandler: PendingTransactionHandling,
         subscriptionFlowsExecuter: SubscriptionFlowsExecuting,
         requestValidator: any ScriptRequestValidator,
         freemiumDBPUserStateManager: FreemiumDBPUserStateManaging = DefaultFreemiumDBPUserStateManager(
            userDefaults: .dbp,
            isUserAuthenticated: { false },
            isFreemiumEnabled: { true }
         )) {
        self.subscriptionManager = subscriptionManager
        self.subscriptionFeatureAvailability = subscriptionFeatureAvailability
        self.appStorePurchaseFlow = appStorePurchaseFlow
        self.appStoreRestoreFlow = appStoreRestoreFlow
        self.subscriptionAttributionOrigin = subscriptionAttributionOrigin
        self.subscriptionDataReporter = subscriptionAttributionOrigin != nil ? subscriptionDataReporter : nil
        self.internalUserDecider = internalUserDecider
        self.wideEvent = wideEvent
        self.tierEventReporter = tierEventReporter
        self.pendingTransactionHandler = pendingTransactionHandler
        self.subscriptionFlowsExecuter = subscriptionFlowsExecuter
        self.requestValidator = requestValidator
        self.freemiumDBPUserStateManager = freemiumDBPUserStateManager
    }

    // Transaction Status and errors are observed from ViewModels to handle errors in the UI
    @Published private(set) var transactionStatus: SubscriptionTransactionStatus = .idle
    var transactionStatusPublisher: Published<SubscriptionTransactionStatus>.Publisher { $transactionStatus }
    @Published private(set) var transactionError: UseSubscriptionError?
    var transactionErrorPublisher: Published<UseSubscriptionError?>.Publisher { $transactionError }

    // Subscription Activation Actions
    var onSetSubscription: (() -> Void)?
    var onBackToSettings: (() -> Void)?
    var onFeatureSelected: ((SubscriptionEntitlement) -> Void)?
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
    
    var subscriptionRestoreEmailAddressWideEventData: SubscriptionRestoreWideEventData?

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        Logger.subscription.debug("WebView handler: \(methodName)")
        print("🇯🇵 [subscriptionPages bridge] FE -> Native handler method=\(methodName)")

        switch methodName {
        case Handlers.setAuthTokens: return setAuthTokens
        case Handlers.getAuthAccessToken: return getAuthAccessToken
        case Handlers.getFeatureConfig: return getFeatureConfig
        case Handlers.getSubscriptionTierOptions: return getSubscriptionTierOptions
        case Handlers.subscriptionSelected: return subscriptionSelected
        case Handlers.subscriptionChangeSelected: return subscriptionChangeSelected
        case Handlers.activateSubscription: return activateSubscription
        case Handlers.featureSelected: return featureSelected
        case Handlers.backToSettings: return backToSettings
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
        print("🇯🇵 [subscriptionPages bridge] Native transactionError=\(error.map(String.init(describing:)) ?? "nil")")
    }

    private func setTransactionStatus(_ status: SubscriptionTransactionStatus) {
        if status != transactionStatus {
            Logger.subscription.log("Transaction state updated: \(status.rawValue)")
            print("🇯🇵 [subscriptionPages bridge] Native transactionStatus \(transactionStatus.rawValue) -> \(status.rawValue)")
            transactionStatus = status
        }
    }

    /// If the FE never redirects after we push Stripe redirect (e.g. mobile), the back button stays hidden. Reset to idle after this delay so the user can go back.
    private static let stripeRedirectSafetyTimeoutSeconds: UInt64 = 8

    private enum StripeRedirectSafetyTimeoutError: Error {
        case couldNotRedirect
    }

    private func startStripeRedirectSafetyTimeout() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.stripeRedirectSafetyTimeoutSeconds * 1_000_000_000)
            await MainActor.run {
                guard let self = self else { return }
                self.setTransactionStatus(.idle)
                if let data = self.planChangeWideEventData {
                    data.markAsFailed(at: SubscriptionPlanChangeWideEventData.FailingStep.confirmation,
                                     error: StripeRedirectSafetyTimeoutError.couldNotRedirect)
                    self.wideEvent.completeFlow(data, status: .failure, onComplete: { _, _ in })
                    self.planChangeWideEventData = nil
                }
            }
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
        print("🇯🇵 [subscriptionPages bridge] FE -> Native setAuthTokens host=\(original.messageHost)")

        guard let subscriptionValues: SubscriptionValuesV2 = CodableHelper.decode(from: params) else {
            print("🇯🇵 [subscriptionPages bridge] Native setAuthTokens decodeFailed")
            Logger.subscription.fault("SubscriptionPagesUserScript: expected JSON representation of SubscriptionValues")
            assertionFailure("SubscriptionPagesUserScript: expected JSON representation of SubscriptionValues")
            setTransactionError(.generalError)
            markEmailAddressRestoreWideEventFlowAsFailed(with: UseSubscriptionError.generalError)
            return nil
        }

        // Clear subscription Cache
        subscriptionManager.clearSubscriptionCache()
        print("🇯🇵 [subscriptionPages bridge] Native cleared subscription cache before adopting FE tokens")

        guard !subscriptionValues.accessToken.isEmpty, !subscriptionValues.refreshToken.isEmpty else {
            print("🇯🇵 [subscriptionPages bridge] Native setAuthTokens received emptyToken accessTokenEmpty=\(subscriptionValues.accessToken.isEmpty) refreshTokenEmpty=\(subscriptionValues.refreshToken.isEmpty)")
            Logger.subscription.fault("Empty access token or refresh token provided")
            markEmailAddressRestoreWideEventFlowAsFailed(with: nil)
            return nil
        }

        do {
            try await subscriptionManager.adopt(accessToken: subscriptionValues.accessToken, refreshToken: subscriptionValues.refreshToken)
            guard let subscription = try await subscriptionManager.getSubscription(forceRefresh: true) else {
                print("🇯🇵 [subscriptionPages bridge] Native setAuthTokens adopted tokens but subscription lookup returned nil")
                Logger.subscription.error("No subscription found after token adoption")
                setTransactionError(.failedToSetSubscription)
                markEmailAddressRestoreWideEventFlowAsFailed(with: UseSubscriptionError.failedToSetSubscription)
                return nil
            }
            Logger.subscription.log("Subscription retrieved: \(subscription.isActive ? "active" : "inactive", privacy: .public)")
            print("🇯🇵 [subscriptionPages bridge] Native setAuthTokens subscription status=\(subscription.status.rawValue) isActive=\(subscription.isActive) tier=\(subscription.tier?.rawValue ?? "nil")")
            markEmailAddressRestoreWideEventFlowAsSuccess()
        } catch {
            print("🇯🇵 [subscriptionPages bridge] Native setAuthTokens failed error=\(error)")
            Logger.subscription.error("Failed to adopt V2 tokens: \(error, privacy: .public)")
            setTransactionError(.failedToSetSubscription)
            markEmailAddressRestoreWideEventFlowAsFailed(with: UseSubscriptionError.failedToSetSubscription)
        }
        return nil
    }

    func getAuthAccessToken(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        print("🇯🇵 [subscriptionPages bridge] FE -> Native getAuthAccessToken host=\(original.messageHost)")
        guard await requestValidator.canPageRequestToken(original) else {
            print("🇯🇵 [subscriptionPages bridge] Native getAuthAccessToken rejectedByValidator host=\(original.messageHost)")
            Logger.subscription.error("Unauthorised access to token")
            return nil
        }
        let tokenContainer = try? await subscriptionManager.getTokenContainer(policy: .localValid)
        print("🇯🇵 [subscriptionPages bridge] Native getAuthAccessToken result=\(tokenContainer?.accessToken.isEmpty == false ? "available" : "missing") length=\(tokenContainer?.accessToken.count ?? 0)")
        return AccessTokenValue(accessToken: tokenContainer?.accessToken ?? "")
    }

    func getFeatureConfig(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        let response = GetFeatureConfigurationResponse(
            usePaidDuckAi: subscriptionFeatureAvailability.isPaidAIChatEnabled,
            useAlternateStripePaymentFlow: subscriptionFeatureAvailability.isSupportsAlternateStripePaymentFlowEnabled,
        )
        print("🇯🇵 [subscriptionPages bridge] FE -> Native getFeatureConfig host=\(original.messageHost) usePaidDuckAi=\(response.usePaidDuckAi) alternateStripe=\(response.useAlternateStripePaymentFlow)")
        return response
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

    func getSubscriptionTierOptions(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        print("🇯🇵 [subscriptionPages bridge] FE -> Native getSubscriptionTierOptions host=\(original.messageHost) includeProTier=\(subscriptionFeatureAvailability.isProTierPurchaseEnabled)")
        tierEventReporter.reportTierOptionsRequested()

        let subscriptionTierOptionsResponse = await subscriptionManager.subscriptionTierOptions(includeProTier: subscriptionFeatureAvailability.isProTierPurchaseEnabled)

        switch subscriptionTierOptionsResponse {
        case .success(let subscriptionTierOptions):
            // Check if Pro tier was unexpectedly returned
            let hasProTier = subscriptionTierOptions.products.contains { $0.tier == .pro }
            if hasProTier && !subscriptionFeatureAvailability.isProTierPurchaseEnabled {
                tierEventReporter.reportTierOptionsUnexpectedProTier()
            }

            tierEventReporter.reportTierOptionsSuccess()
            print("🇯🇵 [subscriptionPages bridge] Native -> FE getSubscriptionTierOptions success productCount=\(subscriptionTierOptions.products.count) purchaseAllowed=\(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)")

            guard subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed else { return subscriptionTierOptions.withoutPurchaseOptions() }
            return subscriptionTierOptions

        case .failure(let error):
            print("🇯🇵 [subscriptionPages bridge] Native -> FE getSubscriptionTierOptions failure error=\(error)")
            Logger.subscription.error("Failed to obtain subscription tier options")
            setTransactionError(.failedToGetSubscriptionOptions)

            tierEventReporter.reportTierOptionsFailure(error: error)

            return SubscriptionTierOptions.empty
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func subscriptionSelected(params: Any, original: WKScriptMessage) async -> Encodable? {
        print("🇯🇵 [subscriptionPages bridge] FE -> Native subscriptionSelected host=\(original.messageHost)")

        DailyPixel.fireDailyAndCount(
            pixel: .subscriptionPurchaseAttempt,
            pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
            withAdditionalParameters: subscriptionAttributionOrigin.map { [AttributionParameter.origin: $0] } ?? [:]
        )
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

        // 1: Parse subscription selection from message object
        let message = original
        guard let subscriptionSelection: SubscriptionSelection = CodableHelper.decode(from: params) else {
            print("🇯🇵 [subscriptionPages bridge] Native subscriptionSelected decodeFailed")
            assertionFailure("SubscriptionPagesUserScript: expected JSON representation of SubscriptionSelection")
            Logger.subscription.error("SubscriptionPagesUserScript: expected JSON representation of SubscriptionSelection")
            setTransactionStatus(.idle)
            return nil
        }
        print("🇯🇵 [subscriptionPages bridge] Native subscriptionSelected productId=\(subscriptionSelection.id) experiment=\(subscriptionSelection.experiment?.name ?? "nil")")

        // 2: Check for active subscriptions
        if await subscriptionManager.storePurchaseManager().hasActiveSubscription() {
            print("🇯🇵 [subscriptionPages bridge] Native subscriptionSelected store already has active subscription")
            Logger.subscription.log("Subscription already active")
            setTransactionError(.activeSubscriptionAlreadyPresent)
            Pixel.fire(pixel: .subscriptionRestoreAfterPurchaseAttempt)
            setTransactionStatus(.idle)
            return nil
        }

        // 3: Configure wide event and start the flow
        let freeTrialEligible = subscriptionManager.storePurchaseManager().isUserEligibleForFreeTrial()

        let data = SubscriptionPurchaseWideEventData(
            purchasePlatform: .appStore,
            subscriptionIdentifier: subscriptionSelection.id,
            freeTrialEligible: freeTrialEligible,
            funnelName: subscriptionAttributionOrigin)

        self.purchaseWideEventData = data
        wideEvent.startFlow(data)

        let purchaseTransactionJWS: String

        // 4: Execute App Store purchase (account creation + StoreKit transaction) and handle the result
        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelection.id, includeProTier: subscriptionFeatureAvailability.isProTierPurchaseEnabled) {
        case .success(let result):
            Logger.subscription.log("Subscription purchased successfully")
            print("🇯🇵 [subscriptionPages bridge] Native StoreKit purchase success transactionJWSLength=\(result.transactionJWS.count)")
            purchaseTransactionJWS = result.transactionJWS

            if let accountCreationDuration = result.accountCreationDuration, let purchaseWideEventData {
                purchaseWideEventData.createAccountDuration = accountCreationDuration
            }
        case .failure(let error):
            print("🇯🇵 [subscriptionPages bridge] Native StoreKit purchase failure error=\(error)")
            Logger.subscription.error("App store purchase error: \(error.localizedDescription)")
            setTransactionStatus(.idle)
            switch error {
            case .cancelledByUser:
                setTransactionError(.cancelledByUser)
                print("🇯🇵 [subscriptionPages bridge] Native -> FE onPurchaseUpdate canceled")
                await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate.canceled)

                if let purchaseWideEventData {
                    wideEvent.completeFlow(purchaseWideEventData, status: .cancelled, onComplete: { _, _ in })
                }

                return nil
            case .accountCreationFailed(let accountCreationError):
                setTransactionError(.accountCreationFailed)

                if let purchaseWideEventData {
                    purchaseWideEventData.markAsFailed(at: .accountCreate, error: accountCreationError)
                    wideEvent.completeFlow(purchaseWideEventData, status: .failure, onComplete: { _, _ in })
                }
            case .activeSubscriptionAlreadyPresent:
                // If we found a subscription, then this is not a purchase flow - discard the purchase pixel.
                if let purchaseWideEventData {
                    wideEvent.discardFlow(purchaseWideEventData)
                    self.purchaseWideEventData = nil
                }

                setTransactionError(.activeSubscriptionAlreadyPresent)
            case .internalError(let internalError):
                setTransactionError(.purchaseFailed)

                if let purchaseWideEventData {
                    purchaseWideEventData.markAsFailed(at: .accountPayment, error: internalError ?? error)
                    wideEvent.completeFlow(purchaseWideEventData, status: .failure, onComplete: { _, _ in })
                }
            case .transactionPendingAuthentication:
                pendingTransactionHandler.markPurchasePending()
                setTransactionError(.purchasePendingTransaction)
                
                if let purchaseWideEventData {
                    purchaseWideEventData.markAsFailed(at: .accountPayment, error: error)
                    wideEvent.completeFlow(purchaseWideEventData, status: .failure, onComplete: { _, _ in })
                }
            default:
                setTransactionError(.purchaseFailed)

                if let purchaseWideEventData {
                    purchaseWideEventData.markAsFailed(at: .accountPayment, error: error)
                    wideEvent.completeFlow(purchaseWideEventData, status: .failure, onComplete: { _, _ in })
                }
            }
            originalMessage = original
            return nil
        }

        setTransactionStatus(.polling)

        guard purchaseTransactionJWS.isEmpty == false else {
            print("🇯🇵 [subscriptionPages bridge] Native completePurchase aborted emptyTransactionJWS")
            Logger.subscription.fault("Purchase transaction JWS is empty")
            assertionFailure("Purchase transaction JWS is empty")
            setTransactionStatus(.idle)
            
            if let purchaseWideEventData {
                wideEvent.completeFlow(purchaseWideEventData, status: .failure, onComplete: { _, _ in })
            }
            
            return nil
        }

        var subscriptionParameters: [String: String]?
        if let frontEndExperiment = subscriptionSelection.experiment {
            subscriptionParameters = frontEndExperiment.asParameters()
        }

        if let purchaseWideEventData {
            purchaseWideEventData.activateAccountDuration = WideEvent.MeasuredInterval.startingNow()
            wideEvent.updateFlow(purchaseWideEventData)
        }

        switch await appStorePurchaseFlow.completeSubscriptionPurchase(with: purchaseTransactionJWS,
                                                                       additionalParams: subscriptionParameters) {
        case .success:
            Logger.subscription.log("Subscription purchase completed successfully")
            print("🇯🇵 [subscriptionPages bridge] Native completeSubscriptionPurchase success; posting subscriptionDidChange and pushing completed")
            DailyPixel.fireDailyAndCount(pixel: .subscriptionPurchaseSuccess,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
            UniquePixel.fire(pixel: .subscriptionActivated)
            Pixel.fireAttribution(pixel: .subscriptionSuccessfulSubscriptionAttribution, origin: subscriptionAttributionOrigin, freeTrial: freeTrialEligible, subscriptionDataReporter: subscriptionDataReporter)
            fireFreemiumUpsellPixel()
            setTransactionStatus(.idle)
            NotificationCenter.default.post(name: .subscriptionDidChange, object: self)
            await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate.completed)

            if let purchaseWideEventData {
                purchaseWideEventData.activateAccountDuration?.complete()
                wideEvent.updateFlow(purchaseWideEventData)
                wideEvent.completeFlow(purchaseWideEventData, status: .success(reason: nil), onComplete: { _, _ in })
            }

        case .failure(let error):
            print("🇯🇵 [subscriptionPages bridge] Native completeSubscriptionPurchase failure error=\(error); signing out and pushing completed")
            Logger.subscription.error("App store complete subscription purchase error: \(error, privacy: .public)")

            await subscriptionManager.signOut(notifyUI: true)

            setTransactionStatus(.idle)
            setTransactionError(.missingEntitlements)
            await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate.completed)

            // Send the wide event error as long as the account isn't missing entitlements
            // If entitlements are missing, the app will check again later and send the pixel as a success if
            // they were fetched, or `unknown` if not
            if let purchaseWideEventData, error != .missingEntitlements {
                purchaseWideEventData.markAsFailed(at: .accountActivation, error: error)
                wideEvent.updateFlow(purchaseWideEventData)
                wideEvent.completeFlow(purchaseWideEventData, status: .failure, onComplete: { _, _ in })
            }
        }
        return nil
    }

    // MARK: - Tier Change

    func subscriptionChangeSelected(params: Any, original: WKScriptMessage) async -> Encodable? {
        print("🇯🇵 [subscriptionPages bridge] FE -> Native subscriptionChangeSelected host=\(original.messageHost)")
        struct SubscriptionChangeSelection: Decodable {
            let id: String
            let change: String?  // "upgrade" or "downgrade"
        }

        let message = original

        guard let subscriptionSelection: SubscriptionChangeSelection = CodableHelper.decode(from: params) else {
            print("🇯🇵 [subscriptionPages bridge] Native subscriptionChangeSelected decodeFailed")
            Logger.subscription.error("SubscriptionPagesUserScript: expected JSON representation of SubscriptionChangeSelection")
            setTransactionStatus(.idle)
            return nil
        }
        print("🇯🇵 [subscriptionPages bridge] Native subscriptionChangeSelected productId=\(subscriptionSelection.id) change=\(subscriptionSelection.change ?? "nil")")

        Logger.subscription.log("[TierChange] Starting \(subscriptionSelection.change ?? "change", privacy: .public) for: \(subscriptionSelection.id, privacy: .public)")

        let currentSubscription = try? await subscriptionManager.getSubscription()
        let effectivePlatform: DuckDuckGoSubscription.Platform = currentSubscription?.platform ?? (subscriptionPlatform == .stripe ? .stripe : .apple)

        Logger.subscription.log("[TierChange] Starting from subscription: \(currentSubscription?.productId ?? "unknown", privacy: .public)")

        switch effectivePlatform {
        case .apple:
            await subscriptionFlowsExecuter.performTierChange(
                to: subscriptionSelection.id,
                changeType: subscriptionSelection.change,
                contextName: subscriptionAttributionOrigin,
                setTransactionStatus: { self.setTransactionStatus($0) },
                setTransactionError: { self.setTransactionError($0.map { self.useSubscriptionError(from: $0) }) },
                pushPurchaseUpdate: { await self.pushPurchaseUpdate(originalMessage: message, purchaseUpdate: $0) }
            )
            return nil
        case .stripe:
            setTransactionError(nil)
            setTransactionStatus(.changingPlan)

            let fromPlan = currentSubscription?.productId ?? ""
            let changeType = SubscriptionPlanChangeWideEventData.ChangeType.parse(string: subscriptionSelection.change)
            let wideData = SubscriptionPlanChangeWideEventData(
                purchasePlatform: .stripe,
                changeType: changeType,
                fromPlan: fromPlan,
                toPlan: subscriptionSelection.id,
                funnelName: subscriptionAttributionOrigin
            )
            planChangeWideEventData = wideData
            wideEvent.startFlow(wideData)

            let accessToken: String
            do {
                let tokenContainer = try await subscriptionManager.getTokenContainer(policy: .localValid)
                accessToken = tokenContainer.accessToken
                Logger.subscription.log("[TierChange] Retrieved access token for Stripe tier change")
            } catch {
                Logger.subscription.error("[TierChange] Failed to get token for Stripe tier change: \(error, privacy: .public)")
                setTransactionStatus(.idle)
                setTransactionError(.otherRestoreError)
                await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate(type: "canceled"))
                wideData.markAsFailed(at: SubscriptionPlanChangeWideEventData.FailingStep.payment, error: error)
                wideEvent.completeFlow(wideData, status: .failure, onComplete: { _, _ in })
                planChangeWideEventData = nil
                return nil
            }

            wideData.confirmationDuration = WideEvent.MeasuredInterval.startingNow()
            wideEvent.updateFlow(wideData)
            await pushPurchaseUpdate(originalMessage: message, purchaseUpdate: PurchaseUpdate.redirect(withToken: accessToken))
            // Spinner stays until FE redirects (completeStripePayment) or safety timeout clears it so back button reappears
            startStripeRedirectSafetyTimeout()
            return nil
        case .google, .unknown:
            setTransactionStatus(.idle)
            setTransactionError(.otherRestoreError)
            return nil
        }
    }

    private func useSubscriptionError(from error: AppStorePurchaseFlowError) -> UseSubscriptionError {
        switch error {
        case .cancelledByUser:
            return .cancelledByUser
        case .transactionPendingAuthentication:
            return .purchasePendingTransaction
        case .missingEntitlements:
            return .missingEntitlements
        default:
            return .purchaseFailed
        }
    }

    func activateSubscription(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.subscription.log("Activating Subscription")
        print("🇯🇵 [subscriptionPages bridge] FE -> Native activateSubscription host=\(original.messageHost)")
        Pixel.fire(pixel: .subscriptionRestorePurchaseOfferPageEntry, debounce: 2)
        onActivateSubscription?()
        return nil
    }

    func featureSelected(params: Any, original: WKScriptMessage) async -> Encodable? {
        print("🇯🇵 [subscriptionPages bridge] FE -> Native featureSelected host=\(original.messageHost)")
        guard let featureSelection: FeatureSelection = CodableHelper.decode(from: params) else {
            print("🇯🇵 [subscriptionPages bridge] Native featureSelected decodeFailed")
            assertionFailure("SubscriptionPagesUserScript: expected JSON representation of FeatureSelection")
            Logger.subscription.error("SubscriptionPagesUserScript: expected JSON representation of FeatureSelection")
            return nil
        }
        print("🇯🇵 [subscriptionPages bridge] Native featureSelected productFeature=\(featureSelection.productFeature.rawValue)")

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
            onFeatureSelected?(.paidAIChat)
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

    func completeStripePayment(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        struct StripePaymentCompletion: Decodable {
            let change: String?
        }
        let completion: StripePaymentCompletion? = CodableHelper.decode(from: params)
        if let changeType = completion?.change {
            Logger.subscription.log("[TierChange] Stripe \(changeType, privacy: .public) completed successfully")
        }

        setTransactionError(nil)
        let isPlanChange = (planChangeWideEventData != nil)
        setTransactionStatus(isPlanChange ? .planChangePolling : .polling)

        subscriptionManager.clearSubscriptionCache()
        _ = try? await subscriptionManager.getTokenContainer(policy: .localForceRefresh)
        print("🇯🇵 [subscriptionPages bridge] Native completeStripePayment posting subscriptionDidChange isPlanChange=\(isPlanChange)")
        NotificationCenter.default.post(name: .subscriptionDidChange, object: self)

        if let data = planChangeWideEventData {
            data.confirmationDuration?.complete()
            wideEvent.updateFlow(data)
            wideEvent.completeFlow(data, status: .success, onComplete: { _, _ in })
            planChangeWideEventData = nil
        }

        setTransactionStatus(.idle)
        return [String: String]()
    }

    func getAccessToken(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        print("🇯🇵 [subscriptionPages bridge] FE -> Native getAccessToken host=\(original.messageHost)")
        guard await requestValidator.canPageRequestToken(original) else {
            print("🇯🇵 [subscriptionPages bridge] Native getAccessToken rejectedByValidator host=\(original.messageHost)")
            Logger.subscription.error("Unauthorised access to token")
            return nil
        }
        do {
            let accessToken = try await subscriptionManager.getTokenContainer(policy: .localValid).accessToken
            print("🇯🇵 [subscriptionPages bridge] Native getAccessToken result=available length=\(accessToken.count)")
            return [SubscriptionPagesUseSubscriptionFeatureConstants.token: accessToken]
        } catch {
            print("🇯🇵 [subscriptionPages bridge] Native getAccessToken result=missing error=\(error)")
            Logger.subscription.debug("No access token available: \(error)")
            return [String: String]()
        }
    }

    // MARK: Pixel related actions

    func subscriptionsMonthlyPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.subscription.log("Web function called: \(#function)")
        Pixel.fire(pixel: .subscriptionOfferMonthlyPriceClick)
        return nil
    }

    func subscriptionsYearlyPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.subscription.log("Web function called: \(#function)")
        Pixel.fire(pixel: .subscriptionOfferYearlyPriceClick)
        return nil
    }

    func subscriptionsUnknownPriceClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        // Not used
        Logger.subscription.log("Web function called: \(#function)")
        return nil
    }

    func subscriptionsAddEmailSuccess(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.subscription.log("Web function called: \(#function)")
        UniquePixel.fire(pixel: .subscriptionAddEmailSuccess)
        return nil
    }

    func subscriptionsWelcomeAddEmailClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.subscription.debug("Web function called: \(#function)")
        UniquePixel.fire(pixel: .subscriptionWelcomeAddDevice)
        return nil
    }

    func subscriptionsWelcomeFaqClicked(params: Any, original: WKScriptMessage) async -> Encodable? {
        Logger.subscription.log("Web function called: \(#function)")
        UniquePixel.fire(pixel: .subscriptionWelcomeFAQClick)
        return nil
    }

    // MARK: Push actions (Push Data back to WebViews)

    enum SubscribeActionName: String {
        case onPurchaseUpdate
    }

    @MainActor
    func pushPurchaseUpdate(originalMessage: WKScriptMessage, purchaseUpdate: PurchaseUpdate) async {
        guard let webView = originalMessage.webView else {
            print("🇯🇵 [subscriptionPages bridge] Native -> FE onPurchaseUpdate skipped webView=nil update=\(purchaseUpdateDebugSummary(purchaseUpdate))")
            return
        }

        print("🇯🇵 [subscriptionPages bridge] Native -> FE onPurchaseUpdate host=\(webView.url?.host ?? "nil") update=\(purchaseUpdateDebugSummary(purchaseUpdate))")
        pushAction(method: .onPurchaseUpdate, webView: webView, params: purchaseUpdate)
    }

    func pushAction(method: SubscribeActionName, webView: WKWebView, params: Encodable) {
        print("🇯🇵 [subscriptionPages bridge] Native -> FE pushAction method=\(method.rawValue) host=\(webView.url?.host ?? "nil")")
        let broker = UserScriptMessageBroker(context: SubscriptionPagesUserScript.context, requiresRunInPageContentWorld: true)
        broker.push(method: method.rawValue, params: params, for: self, into: webView)
    }

    private func purchaseUpdateDebugSummary(_ purchaseUpdate: PurchaseUpdate) -> String {
        guard let data = try? JSONEncoder().encode(purchaseUpdate),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "unavailable"
        }

        let type = json["type"] as? String ?? "unknown"
        let token = json["token"] as? String
        return "type=\(type) tokenPresent=\(token?.isEmpty == false) tokenLength=\(token?.count ?? 0)"
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

    private func fireFreemiumUpsellPixel() {
        guard freemiumDBPUserStateManager.didActivate, let pixelKit = PixelKit.shared else { return }
        DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .iOS).fire(.freemiumUpsell)
    }
}

// MARK: - Wide Pixel

private extension DefaultSubscriptionPagesUseSubscriptionFeature {
    
    func markEmailAddressRestoreWideEventFlowAsSuccess() {
        guard let restoreWideEventData = self.subscriptionRestoreEmailAddressWideEventData else { return }
        restoreWideEventData.emailAddressRestoreDuration?.complete()
        wideEvent.completeFlow(restoreWideEventData, status: .success, onComplete: { _, _ in })
        self.subscriptionRestoreEmailAddressWideEventData = nil
    }
    
    func markEmailAddressRestoreWideEventFlowAsFailed(with error: Error?) {
        guard let restoreWideEventData = self.subscriptionRestoreEmailAddressWideEventData else { return }
        restoreWideEventData.emailAddressRestoreDuration?.complete()
        if let error {
            restoreWideEventData.errorData = .init(error: error)
        }
        wideEvent.completeFlow(restoreWideEventData, status: .failure, onComplete: { _, _ in })
        self.subscriptionRestoreEmailAddressWideEventData = nil
    }
}

extension Pixel {

    enum AttributionParameters {
        static let origin = "origin"
        static let locale = "locale"
        static let freeTrial = "free_trial"
    }

    static func fireAttribution(pixel: Pixel.Event, origin: String?, freeTrial: Bool? = nil, locale: Locale = .current, subscriptionDataReporter: SubscriptionDataReporting?) {
        var parameters: [String: String] = [:]
        parameters[AttributionParameters.locale] = locale.identifier
        if let origin {
            parameters[AttributionParameters.origin] = origin
        }
        if let freeTrial {
            parameters[AttributionParameters.freeTrial] = String(freeTrial)
        }
        Self.fire(
            pixel: pixel,
            withAdditionalParameters: subscriptionDataReporter?.mergeRandomizedParameters(for: .origin(origin), with: parameters) ?? parameters
        )
    }

}
