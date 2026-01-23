//
//  SubscriptionSettingsViewModel.swift
//  DuckDuckGo
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
import SwiftUI
import StoreKit
import Subscription
import Core
import os.log
import PrivacyConfig
import Networking
import Persistence

final class SubscriptionSettingsViewModel: ObservableObject {

    private let subscriptionManager: SubscriptionManager
    private let userScriptsDependencies: DefaultScriptSourceProvider.Dependencies
    private var signOutObserver: Any?
    private var subscriptionChangeObserver: Any?
    private let featureFlagger: FeatureFlagger

    private var externalAllowedDomains = ["stripe.com"]

    struct State {
        var subscriptionDetails: String = ""
        var subscriptionEmail: String?
        var isShowingInternalSubscriptionNotice: Bool = false
        var isShowingRemovalNotice: Bool = false
        var shouldDismissView: Bool = false
        var isShowingGoogleView: Bool = false
        var isShowingFAQView: Bool = false
        var isShowingLearnMoreView: Bool = false
        var isShowingPlansView: Bool = false
        var isShowingUpgradeView: Bool = false
        var subscriptionInfo: DuckDuckGoSubscription?
        var isLoadingSubscriptionInfo: Bool = false

        // Used to display stripe WebUI
        var stripeViewModel: SubscriptionExternalLinkViewModel?
        var isShowingStripeView: Bool = false

        // Display error
        var isShowingConnectionError: Bool = false

        // Used to display the FAQ WebUI
        var faqViewModel: SubscriptionExternalLinkViewModel
        var learnMoreViewModel: SubscriptionExternalLinkViewModel

        let featureFlagger: FeatureFlagger

        init(faqURL: URL, learnMoreURL: URL, userScriptsDependencies: DefaultScriptSourceProvider.Dependencies, featureFlagger: FeatureFlagger) {
            self.featureFlagger = featureFlagger
            self.faqViewModel = SubscriptionExternalLinkViewModel(url: faqURL, userScriptsDependencies: userScriptsDependencies, featureFlagger: featureFlagger)
            self.learnMoreViewModel = SubscriptionExternalLinkViewModel(url: learnMoreURL, userScriptsDependencies: userScriptsDependencies, featureFlagger: featureFlagger)
        }
    }

    // Publish the currently selected feature
    @Published var selectedFeature: SettingsViewModel.SettingsDeepLinkSection?

    // Read only View State - Should only be modified from the VM
    @Published private(set) var state: State

    public let usesUnifiedFeedbackForm: Bool

    /// Returns the tier badge variant to display, or nil if badge should not be shown
    /// Shows badge if tier is Pro, or if Pro tier purchase feature flag is enabled
    var tierBadgeToDisplay: TierBadgeView.Variant? {
        guard let tier = state.subscriptionInfo?.tier else { return nil }
        guard tier == .pro || featureFlagger.isFeatureOn(.allowProTierPurchase) else { return nil }
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
        guard let subscriptionInfo = state.subscriptionInfo,
              subscriptionInfo.isActive else {
            return false
        }
        return featureFlagger.isFeatureOn(.allowProTierPurchase) || subscriptionInfo.tier == .pro
    }

    /// Returns true if "Upgrade" section should be shown
    /// Requirements:
    /// - Subscription is active
    /// - No pending plan (don't show upgrade if downgrade is scheduled)
    /// - Pro tier purchase feature flag is enabled
    /// - Backend reports available upgrades
    var shouldShowUpgrade: Bool {
        guard let subscriptionInfo = state.subscriptionInfo,
              subscriptionInfo.isActive else {
            return false
        }
        // Don't show upgrade if there's a pending plan (downgrade scheduled)
        guard subscriptionInfo.pendingPlans?.isEmpty ?? true else { return false }
        guard featureFlagger.isFeatureOn(.allowProTierPurchase) else { return false }
        return firstAvailableUpgradeTier != nil
    }

    /// Returns the first available upgrade tier name, sorted by order (lowest order first)
    var firstAvailableUpgradeTier: String? {
        state.subscriptionInfo?.availableChanges?.upgrade
            .sorted { $0.order < $1.order }
            .first?.tier
    }

    var subscriptionManageButtonText: String {
        featureFlagger.isFeatureOn(.allowProTierPurchase)
            ? UserText.subscriptionManagePayment
            : UserText.subscriptionChangePlan
    }

    /// Handles navigation to plans page based on subscription platform
    /// - Parameters:
    ///   - goToUpgrade: If true, navigates to /plans?goToUpgrade=true for direct upgrade flow
    func navigateToPlans(goToUpgrade: Bool = false) {
        guard let platform = state.subscriptionInfo?.platform else { return }

        // Fire appropriate pixel
        if goToUpgrade {
            Pixel.fire(pixel: .subscriptionUpgradeClick)
        } else {
            Pixel.fire(pixel: .subscriptionViewAllPlansClick)
        }

        switch platform {
        case .apple:
            if goToUpgrade {
                state.isShowingUpgradeView = true
            } else {
                state.isShowingPlansView = true
            }
        case .google:
            displayGoogleView(true)
        case .stripe:
            Task { await manageStripeSubscription() }
        case .unknown:
            displayInternalSubscriptionNotice(true)
        }
    }

    func displayUpgradeView(_ value: Bool) {
        if value != state.isShowingUpgradeView {
            state.isShowingUpgradeView = value
        }
    }

    private let keyValueStorage: KeyValueStoring

    init(subscriptionManager: SubscriptionManager = AppDependencyProvider.shared.subscriptionManager,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         keyValueStorage: KeyValueStoring = SubscriptionSettingsStore(),
         userScriptsDependencies: DefaultScriptSourceProvider.Dependencies) {
        self.subscriptionManager = subscriptionManager
        self.userScriptsDependencies = userScriptsDependencies
        self.featureFlagger = featureFlagger
        let subscriptionFAQURL = subscriptionManager.url(for: .faq)
        let learnMoreURL = subscriptionFAQURL.appendingPathComponent("adding-email")
        self.state = State(faqURL: subscriptionFAQURL, learnMoreURL: learnMoreURL, userScriptsDependencies: userScriptsDependencies, featureFlagger: featureFlagger)
        self.usesUnifiedFeedbackForm = subscriptionManager.isUserAuthenticated
        self.keyValueStorage = keyValueStorage
        setupNotificationObservers()
    }

    private var dateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
#if DEBUG
        dateFormatter.timeStyle = .medium
#else
        dateFormatter.timeStyle = .none
#endif
        return dateFormatter
    }()

    func onFirstAppear() {
        Task {
            // Load initial state from the cache
            async let loadedEmailFromCache = await self.fetchAndUpdateAccountEmail(cachePolicy: .cacheFirst)
            async let loadedSubscriptionFromCache = await self.fetchAndUpdateSubscriptionDetails(cachePolicy: .cacheFirst,
                                                                                                 loadingIndicator: false)
            let (hasLoadedEmailFromCache, hasLoadedSubscriptionFromCache) = await (loadedEmailFromCache, loadedSubscriptionFromCache)

            // Reload remote subscription and email state
            async let reloadedEmail = await self.fetchAndUpdateAccountEmail(cachePolicy: .remoteFirst)
            async let reloadedSubscription = await self.fetchAndUpdateSubscriptionDetails(cachePolicy: .remoteFirst,
                                                                                          loadingIndicator: !hasLoadedSubscriptionFromCache)
            let (hasReloadedEmail, hasReloadedSubscription) = await (reloadedEmail, reloadedSubscription)
        }
    }

    private func fetchAndUpdateSubscriptionDetails(cachePolicy: SubscriptionCachePolicy, loadingIndicator: Bool) async -> Bool {
        Logger.subscription.log("Fetch and update subscription details")
        guard subscriptionManager.isUserAuthenticated else { return false }

        if loadingIndicator { self.displaySubscriptionLoader(true) }

        do {
            let subscription = try await self.subscriptionManager.getSubscription(cachePolicy: cachePolicy)
            Task { @MainActor in
                self.state.subscriptionInfo = subscription
                if loadingIndicator { self.displaySubscriptionLoader(false) }
            }
            await updateSubscriptionsStatusMessage(subscription: subscription,
                                                   date: subscription.expiresOrRenewsAt,
                                                   product: subscription.productId,
                                                   billingPeriod: subscription.billingPeriod)
            return true
        } catch {
            Logger.subscription.error("\(#function) error: \(error.localizedDescription)")
            Task { @MainActor in
                if loadingIndicator { self.displaySubscriptionLoader(true) }
            }
            return false
        }
    }

    func fetchAndUpdateAccountEmail(cachePolicy: SubscriptionCachePolicy = .cacheFirst) async -> Bool {
        Logger.subscription.log("Fetch and update account email")
        guard subscriptionManager.isUserAuthenticated else { return false }

        let tokensPolicy: AuthTokensCachePolicy

        switch cachePolicy {
        case .remoteFirst:
            tokensPolicy = .localForceRefresh
        case .cacheFirst:
            tokensPolicy = .localValid
        }

        do {
            let tokenContainer = try await subscriptionManager.getTokenContainer(policy: tokensPolicy)
            Task { @MainActor in
                self.state.subscriptionEmail = tokenContainer.decodedAccessToken.email
            }
            return true
        } catch {
            Logger.subscription.error("\(#function) error: \(error.localizedDescription)")
            return false
        }
    }

    private func displaySubscriptionLoader(_ show: Bool) {
        DispatchQueue.main.async {
            self.state.isLoadingSubscriptionInfo = show
        }
    }

    func manageSubscription() {
        Logger.subscription.log("User action: \(#function)")

        guard let platform = state.subscriptionInfo?.platform else {
            assertionFailure("Invalid subscription platform")
            return
        }

        switch platform {
        case .apple:
            Task { await manageAppleSubscription() }
        case .google:
            displayGoogleView(true)
        case .stripe:
            Task { await manageStripeSubscription() }
        case .unknown:
            manageInternalSubscription()
        }
    }

    // MARK: -

    private func setupNotificationObservers() {
        signOutObserver = NotificationCenter.default.addObserver(forName: .accountDidSignOut, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async {
                self?.state.shouldDismissView = true
            }
        }

        subscriptionChangeObserver = NotificationCenter.default.addObserver(forName: .subscriptionDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { [weak self] in
                _ = await self?.fetchAndUpdateSubscriptionDetails(cachePolicy: .cacheFirst, loadingIndicator: false)
            }
        }
    }

    @MainActor
    private func updateSubscriptionsStatusMessage(subscription: DuckDuckGoSubscription, date: Date, product: String, billingPeriod: DuckDuckGoSubscription.BillingPeriod) {
        // Check for pending plan first (downgrade scheduled)
        if let pendingPlan = subscription.firstPendingPlan {
            let effectiveDate = dateFormatter.string(from: pendingPlan.effectiveAt)
            let tierName = pendingPlan.tier.rawValue.capitalized
            state.subscriptionDetails = UserText.pendingDowngradeInfo(tierName: tierName, billingPeriod: pendingPlan.billingPeriod, effectiveDate: effectiveDate)
            return
        }

        let date = dateFormatter.string(from: date)

        let hasActiveTrialOffer = subscription.hasActiveTrialOffer

        switch subscription.status {
        case .autoRenewable:
            if hasActiveTrialOffer {
                state.subscriptionDetails = UserText.renewingTrialSubscriptionInfo(billingPeriod: billingPeriod, renewalDate: date)
            } else {
                state.subscriptionDetails = UserText.renewingSubscriptionInfo(billingPeriod: billingPeriod, renewalDate: date)
            }
        case .notAutoRenewable:
            if hasActiveTrialOffer {
                state.subscriptionDetails = UserText.expiringTrialSubscriptionInfo(expiryDate: date)
            } else {
                state.subscriptionDetails = UserText.expiringSubscriptionInfo(billingPeriod: billingPeriod, expiryDate: date)
            }
        case .expired, .inactive:
            state.subscriptionDetails = UserText.expiredSubscriptionInfo(expiration: date)
        default:
            state.subscriptionDetails = UserText.expiringSubscriptionInfo(billingPeriod: billingPeriod, expiryDate: date)
        }
    }

    func removeSubscription() {
        Logger.subscription.log("Remove subscription")

        Task {
            await subscriptionManager.signOut(notifyUI: true, userInitiated: true)
            _ = await ActionMessageView()
            await ActionMessageView.present(message: UserText.subscriptionRemovalConfirmation,
                                            presentationLocation: .withoutBottomBar)
        }
    }

    func displayGoogleView(_ value: Bool) {
        Logger.subscription.log("Show google")
        if value != state.isShowingGoogleView {
            state.isShowingGoogleView = value
        }
    }

    func displayStripeView(_ value: Bool) {
        Logger.subscription.log("Show stripe")
        if value != state.isShowingStripeView {
            state.isShowingStripeView = value
        }
    }

    func displayInternalSubscriptionNotice(_ value: Bool) {
        if value != state.isShowingInternalSubscriptionNotice {
            state.isShowingInternalSubscriptionNotice = value
        }
    }

    func displayRemovalNotice(_ value: Bool) {
        if value != state.isShowingRemovalNotice {
            state.isShowingRemovalNotice = value
        }
    }

    func displayPlansView(_ value: Bool) {
        if value != state.isShowingPlansView {
            state.isShowingPlansView = value
        }
    }

    func displayFAQView(_ value: Bool) {
        Logger.subscription.log("Show faq")
        if value != state.isShowingFAQView {
            state.isShowingFAQView = value
        }
    }

    func displayLearnMoreView(_ value: Bool) {
        Logger.subscription.log("Show learn more")
        if value != state.isShowingLearnMoreView {
            state.isShowingLearnMoreView = value
        }
    }

    func showConnectionError(_ value: Bool) {
        if value != state.isShowingConnectionError {
            DispatchQueue.main.async {
                self.state.isShowingConnectionError = value
            }
        }
    }

    @MainActor
    func showTermsOfService() {
        let privacyPolicyQuickLinkURL = URL(string: AppDeepLinkSchemes.quickLink.appending(SettingsSubscriptionView.ViewConstants.privacyPolicyURL.absoluteString))!
        openURL(privacyPolicyQuickLinkURL)
    }

    // MARK: -

    @MainActor private func manageAppleSubscription() async {
        Logger.subscription.log("Managing Apple Subscription")
        if state.subscriptionInfo?.isActive ?? false {
            let url = subscriptionManager.url(for: .manageSubscriptionsInAppStore)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                do {
                    try await AppStore.showManageSubscriptions(in: windowScene)
                } catch {
                    self.openURL(url)
                }
            } else {
                self.openURL(url)
            }
        }
    }

    private func manageStripeSubscription() async {
        Logger.subscription.log("Managing Stripe Subscription")

        guard subscriptionManager.isUserAuthenticated else { return }

        do {
            // Get Stripe Customer Portal URL and update the model
            let url = try await subscriptionManager.getCustomerPortalURL()
            if let existingModel = state.stripeViewModel {
                existingModel.url = url
            } else {
                let model = SubscriptionExternalLinkViewModel(url: url,
                                                              allowedDomains: externalAllowedDomains,
                                                              userScriptsDependencies: userScriptsDependencies,
                                                              featureFlagger: featureFlagger)
                Task { @MainActor in
                    self.state.stripeViewModel = model
                }
            }
        } catch {
            Logger.subscription.error("\(error.localizedDescription)")
        }
        Task { @MainActor in
            self.displayStripeView(true)
        }
    }

    private func manageInternalSubscription() {
        Logger.subscription.log("Managing Internal Subscription")

        Task { @MainActor in
            self.displayInternalSubscriptionNotice(true)
        }
    }

    @MainActor
    private func openURL(_ url: URL) {
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    deinit {
        signOutObserver = nil
        subscriptionChangeObserver = nil
    }
}

public struct SubscriptionSettingsStore: KeyValueStoring {
    private let keyValueFileStore: KeyValueFileStore?

    public init() {
        if let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            self.keyValueFileStore = try? KeyValueFileStore(location: appSupportDir, name: "com.duckduckgo.app.subscriptionSettingsStore")
        } else {
            self.keyValueFileStore = nil
        }
    }

    public func object(forKey defaultName: String) -> Any? {
        try? keyValueFileStore?.object(forKey: defaultName)
    }
    public func set(_ value: Any?, forKey defaultName: String) {
        try? keyValueFileStore?.set(value, forKey: defaultName)
    }
    public func removeObject(forKey defaultName: String) {
        try? keyValueFileStore?.removeObject(forKey: defaultName)
    }
}
