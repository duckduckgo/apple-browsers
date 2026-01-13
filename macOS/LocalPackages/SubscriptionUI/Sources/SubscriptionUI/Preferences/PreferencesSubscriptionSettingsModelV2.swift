//
//  PreferencesSubscriptionSettingsModelV2.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import struct Combine.AnyPublisher
import enum Combine.Publishers
import class Combine.AnyCancellable
import BrowserServicesKit
import os.log
import Persistence
import PrivacyConfig

public enum PreferencesSubscriptionSettingsState: String {
    case subscriptionPendingActivation, subscriptionActive, subscriptionExpired, subscriptionFreeTrialActive
}

public final class PreferencesSubscriptionSettingsModelV2: ObservableObject {

    @Published var subscriptionDetails: String?
    @Published var subscriptionStatus: DuckDuckGoSubscription.Status = .unknown
    @Published private var hasActiveTrialOffer: Bool = false
    @Published private(set) var subscriptionTier: TierName?
    private var subscriptionPlatform: DuckDuckGoSubscription.Platform?
    private var isSubscriptionActive: Bool = false
    private var availableChanges: DuckDuckGoSubscription.AvailableChanges?

    /// Returns the tier badge variant to display, or nil if badge should not be shown
    /// Shows badge if tier is Pro, or if Pro tier purchase feature flag is enabled
    var tierBadgeToDisplay: TierBadgeView.Variant? {
        guard let tier = subscriptionTier else { return nil }
        guard tier == .pro || isProTierPurchaseEnabled() else { return nil }
        switch tier {
        case .plus: return .plus
        case .pro: return .pro
        }
    }

    /// Returns true if "View All Plans" option should be shown
    /// Requirements:
    /// - Subscription is active
    /// - Pro tier purchase feature flag is enabled OR user has Pro tier subscription
    var shouldShowViewAllPlans: Bool {
        guard isSubscriptionActive else { return false }
        return isProTierPurchaseEnabled() || subscriptionTier == .pro
    }

    /// Returns true if "Upgrade" option should be shown
    /// Requirements:
    /// - Subscription is active
    /// - Pro tier purchase feature flag is enabled
    /// - There are available upgrades
    var shouldShowUpgrade: Bool {
        guard isSubscriptionActive else { return false }
        guard isProTierPurchaseEnabled() else { return false }
        return firstAvailableUpgradeTier != nil
    }

    /// Returns the first available upgrade tier name, sorted by order
    var firstAvailableUpgradeTier: String? {
        availableChanges?.upgrade
            .sorted { $0.order < $1.order }
            .first?.tier
    }

    @Published var email: String?
    var hasEmail: Bool { !(email?.isEmpty ?? true) }

    var expiredSubscriptionPurchaseButtonTitle: String {
        if winBackOfferVisibilityManager.isOfferAvailable {
            UserText.winBackCampaignLoggedInPreferencesCTA
        } else if blackFridayCampaignProvider.isCampaignEnabled {
            UserText.blackFridayCampaignPreferencesCTA(discountPercent: blackFridayCampaignProvider.discountPercent)
        } else {
            UserText.viewPlansExpiredButtonTitle
        }
    }

    var currentPurchasePlatform: SubscriptionEnvironment.PurchasePlatform { subscriptionManager.currentEnvironment.purchasePlatform }

    private let subscriptionManager: SubscriptionManagerV2
    private let keyValueStore: ThrowingKeyValueStoring
    private let winBackOfferVisibilityManager: WinBackOfferVisibilityManaging
    private let blackFridayCampaignProvider: BlackFridayCampaignProviding
    private let userEventHandler: (PreferencesSubscriptionSettingsModelV2.UserEvent) -> Void
    private let isProTierPurchaseEnabled: () -> Bool
    private var fetchSubscriptionDetailsTask: Task<(), Never>?

    private var subscriptionChangeObserver: Any?

    @Published public var settingsState: PreferencesSubscriptionSettingsState = .subscriptionPendingActivation

    private var cancellables = Set<AnyCancellable>()

    public enum UserEvent {
        case openFeedback,
             openURL(SubscriptionURL),
             openManageSubscriptionsInAppStore,
             openCustomerPortalURL(URL),
             didClickManageEmail,
             didOpenSubscriptionSettings,
             didClickChangePlanOrBilling,
             didClickRemoveSubscription,
             openWinBackOfferLandingPage
    }

    public init(userEventHandler: @escaping (PreferencesSubscriptionSettingsModelV2.UserEvent) -> Void,
                subscriptionManager: SubscriptionManagerV2,
                subscriptionStateUpdate: AnyPublisher<PreferencesSidebarSubscriptionState, Never>,
                keyValueStore: ThrowingKeyValueStoring,
                winBackOfferVisibilityManager: WinBackOfferVisibilityManaging,
                blackFridayCampaignProvider: BlackFridayCampaignProviding,
                isProTierPurchaseEnabled: @escaping () -> Bool) {
        self.subscriptionManager = subscriptionManager
        self.userEventHandler = userEventHandler
        self.keyValueStore = keyValueStore
        self.winBackOfferVisibilityManager = winBackOfferVisibilityManager
        self.blackFridayCampaignProvider = blackFridayCampaignProvider
        self.isProTierPurchaseEnabled = isProTierPurchaseEnabled
        Task {
            await self.updateSubscription(cachePolicy: .cacheFirst)
        }

        self.email = subscriptionManager.userEmail

        subscriptionChangeObserver = NotificationCenter.default.addObserver(forName: .subscriptionDidChange, object: nil, queue: .main) { _ in
            Logger.general.debug("SubscriptionDidChange notification received")
            guard self.fetchSubscriptionDetailsTask == nil else { return }
            self.fetchSubscriptionDetailsTask = Task { [weak self] in
                defer {
                    self?.fetchSubscriptionDetailsTask = nil
                }

                await self?.fetchEmail()
                await self?.updateSubscription(cachePolicy: .cacheFirst)
            }
        }

        Publishers.CombineLatest3($subscriptionStatus, $hasActiveTrialOffer, subscriptionStateUpdate)
            .map { status, hasTrialOffer, state in

                Logger.subscription.debug("""
Update subscription state: \(state.debugDescription, privacy: .public)
hasActiveTrialOffer: \(hasTrialOffer, privacy: .public)
""")

                switch status {
                case .expired, .inactive:
                    return PreferencesSubscriptionSettingsState.subscriptionExpired
                case .autoRenewable, .notAutoRenewable, .gracePeriod:
                    // Check for free trial first
                    if hasTrialOffer {
                        return PreferencesSubscriptionSettingsState.subscriptionFreeTrialActive
                    } else if state.hasAnyEntitlement {
                        return PreferencesSubscriptionSettingsState.subscriptionActive
                    } else {
                        return PreferencesSubscriptionSettingsState.subscriptionPendingActivation
                    }
                default:
                    return PreferencesSubscriptionSettingsState.subscriptionPendingActivation
                }

            }
            .removeDuplicates()
            .assign(to: \.settingsState, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    deinit {
        if let subscriptionChangeObserver {
            NotificationCenter.default.removeObserver(subscriptionChangeObserver)
        }
    }

    @MainActor
    func didAppear() {
        userEventHandler(.didOpenSubscriptionSettings)
        fetchAndUpdateSubscriptionDetails()
    }

    @MainActor
    func purchaseAction() {
        if winBackOfferVisibilityManager.isOfferAvailable {
            userEventHandler(.openWinBackOfferLandingPage)
        } else {
            userEventHandler(.openURL(.purchase))
        }
    }

    enum ChangePlanOrBillingAction {
        case presentSheet(ManageSubscriptionSheet)
        case navigateToManageSubscription(() -> Void)
        case showInternalSubscriptionAlert
    }

    enum ViewAllPlansAction {
        case navigateToPlans(() -> Void)
        case navigateToManageSubscription(() -> Void)
        case presentSheet(ManageSubscriptionSheet)
        case showInternalSubscriptionAlert
    }

    /// Returns the appropriate action for "View All Plans" or "Upgrade" based on:
    /// - Subscription platform: where the subscription was purchased
    /// - Current app platform: App Store version vs Stripe (Sparkling) version
    /// - Parameter url: The subscription URL to navigate to (defaults to `.plans`)
    @MainActor
    func viewAllPlansAction(url: SubscriptionURL = .plans) -> ViewAllPlansAction {
        guard let subscriptionPlatform = subscriptionPlatform else {
            assertionFailure("Missing or unknown subscriptionPlatform")
            return .navigateToPlans { }
        }

        switch subscriptionPlatform {
        case .apple:
            if currentPurchasePlatform == .appStore {
                // Apple subscription on App Store app → show plans/upgrade page
                return .navigateToPlans { [weak self] in
                    self?.userEventHandler(.openURL(url))
                }
            } else {
                // Apple subscription on Stripe app → show Apple dialog with instructions
                return .presentSheet(.apple)
            }
        case .stripe:
            if currentPurchasePlatform == .stripe {
                // Stripe subscription on Stripe app → show plans/upgrade page
                return .navigateToPlans { [weak self] in
                    self?.userEventHandler(.openURL(url))
                }
            } else {
                // Stripe subscription on App Store app → redirect to Stripe portal
                return .navigateToManageSubscription { [weak self] in
                    self?.openStripeCustomerPortal()
                }
            }
        case .google:
            return .presentSheet(.google)
        case .unknown:
            return .showInternalSubscriptionAlert
        }
    }

    private func openStripeCustomerPortal() {
        Task {
            do {
                let url = try await subscriptionManager.getCustomerPortalURL()
                userEventHandler(.openCustomerPortalURL(url))
            } catch {
                Logger.general.log("Error getting customer portal URL: \(error, privacy: .public)")
            }
        }
    }

    @MainActor
    func changePlanOrBillingAction() async -> ChangePlanOrBillingAction {
        userEventHandler(.didClickChangePlanOrBilling)

        guard let platform = subscriptionPlatform else {
            assertionFailure("Missing or unknown subscriptionPlatform")
            return .navigateToManageSubscription { }
        }

        switch platform {
        case .apple:
            return .navigateToManageSubscription { [weak self] in
                self?.changePlanOrBilling(for: .appStore)
            }
        case .google:
            return .presentSheet(.google)
        case .stripe:
            return .navigateToManageSubscription { [weak self] in
                self?.changePlanOrBilling(for: .stripe)
            }
        case .unknown:
            return .showInternalSubscriptionAlert
        }
    }

    private func changePlanOrBilling(for environment: SubscriptionEnvironment.PurchasePlatform) {
        switch environment {
        case .appStore:
            userEventHandler(.openManageSubscriptionsInAppStore)
        case .stripe:
            Task {
                do {
                    let url = try await subscriptionManager.getCustomerPortalURL()
                    userEventHandler(.openCustomerPortalURL(url))
                } catch {
                    Logger.general.log("Error getting customer portal URL: \(error, privacy: .public)")
                }
            }
        }
    }

    @MainActor
    func openLearnMore() {
        userEventHandler(.openURL(.helpPagesAddingEmail))
    }

    @MainActor
    func activationFlowAction() {
        switch (subscriptionPlatform, hasEmail) {
        case (.apple, _):
            handleEmailAction(type: .activationFlow)
        case (_, false):
            handleEmailAction(type: .activationFlowAddEmailStep)
        case (_, true):
            handleEmailAction(type: .activationFlowLinkViaEmailStep)
        }
    }

    @MainActor
    func editEmailAction() {
        handleEmailAction(type: .editEmail)
    }

    private enum SubscriptionEmailActionType {
        case activationFlow, activationFlowAddEmailStep, activationFlowLinkViaEmailStep, editEmail
    }

    private func handleEmailAction(type: SubscriptionEmailActionType) {
        Task { @MainActor in
            switch type {
            case .activationFlow:
                userEventHandler(.openURL(.activationFlow))
            case .activationFlowAddEmailStep:
                userEventHandler(.openURL(.activationFlowAddEmailStep))
            case .activationFlowLinkViaEmailStep:
                userEventHandler(.openURL(.activationFlowLinkViaEmailStep))
            case .editEmail:
                userEventHandler(.didClickManageEmail)
                userEventHandler(.openURL(.manageEmail))
            }
        }
    }

    @MainActor
    func removeFromThisDeviceAction() {
        userEventHandler(.didClickRemoveSubscription)
        Task {
            await subscriptionManager.signOut(notifyUI: true, userInitiated: true)
        }
    }

    @MainActor
    func openFAQ() {
        userEventHandler(.openURL(.faq))
    }

    @MainActor
    func openUnifiedFeedbackForm() {
        userEventHandler(.openFeedback)
    }

    @MainActor
    func openPrivacyPolicy() {
        userEventHandler(.openURL(.privacyPolicy))
    }

    @MainActor
    func refreshSubscriptionPendingState() {

        if subscriptionManager.currentEnvironment.purchasePlatform == .appStore {
            if #available(macOS 12.0, *) {
                Task {
                    let appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager,
                                                                           storePurchaseManager: subscriptionManager.storePurchaseManager())
                    await appStoreRestoreFlow.restoreAccountFromPastPurchase()
                    fetchAndUpdateSubscriptionDetails()
                }
            }
        } else {
            fetchAndUpdateSubscriptionDetails()
        }
    }

    @MainActor
    private func fetchAndUpdateSubscriptionDetails() {
        guard fetchSubscriptionDetailsTask == nil else { return }

        fetchSubscriptionDetailsTask = Task { [weak self] in
            defer {
                self?.fetchSubscriptionDetailsTask = nil
            }

            await self?.fetchEmail()
            await self?.updateSubscription(cachePolicy: .remoteFirst)
        }
    }

    @MainActor func fetchEmail() async {
        let tokenContainer = try? await subscriptionManager.getTokenContainer(policy: .local)
        email = tokenContainer?.decodedAccessToken.email
    }

    @MainActor
    private func updateSubscription(cachePolicy: SubscriptionCachePolicy) async {
        do {
            let subscription = try await subscriptionManager.getSubscription(cachePolicy: cachePolicy)
            Task { @MainActor in
                updateDescription(for: subscription)
                subscriptionPlatform = subscription.platform
                subscriptionStatus = subscription.status
                hasActiveTrialOffer = subscription.hasActiveTrialOffer
                subscriptionTier = subscription.tier
                isSubscriptionActive = subscription.isActive
                availableChanges = subscription.availableChanges
            }
        } catch {
            Logger.subscription.error("Error getting subscription: \(error, privacy: .public)")
        }
    }

    @MainActor
    func updateDescription(for subscription: DuckDuckGoSubscription) {
        let hasActiveTrialOffer = subscription.hasActiveTrialOffer
        let status = subscription.status
        let period = subscription.billingPeriod
        let formattedDate = dateFormatter.string(from: subscription.expiresOrRenewsAt)

        switch status {
        case .autoRenewable:
            if hasActiveTrialOffer {
                self.subscriptionDetails = UserText.preferencesTrialSubscriptionRenewingCaption(billingPeriod: period, formattedDate: formattedDate)
            } else {
                self.subscriptionDetails = UserText.preferencesSubscriptionRenewingCaption(billingPeriod: period, formattedDate: formattedDate)
            }

        case .expired, .inactive:
            self.subscriptionDetails = UserText.preferencesSubscriptionExpiredCaption(formattedDate: formattedDate)
        default:
            if hasActiveTrialOffer {
                self.subscriptionDetails = UserText.preferencesTrialSubscriptionExpiringCaption(formattedDate: formattedDate)
            } else {
                self.subscriptionDetails = UserText.preferencesSubscriptionExpiringCaption(billingPeriod: period, formattedDate: formattedDate)
            }

        }
    }

    private var dateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none

        return dateFormatter
    }()

}

enum ManageSubscriptionSheet: Identifiable {
    case apple, google

    var id: Self {
        return self
    }
}
