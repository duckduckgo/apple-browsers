//
//  SubscriptionSettingsViewModelV2.swift
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
import BrowserServicesKit
import Networking

final class SubscriptionSettingsViewModelV2: ObservableObject {

    private let subscriptionManager: SubscriptionManagerV2
    private var signOutObserver: Any?

    private var externalAllowedDomains = ["stripe.com"]

    struct State {
        var subscriptionDetails: String = ""
        var subscriptionEmail: String?
        var isShowingRemovalNotice: Bool = false
        var shouldDismissView: Bool = false
        var isShowingGoogleView: Bool = false
        var isShowingFAQView: Bool = false
        var isShowingLearnMoreView: Bool = false
        var subscriptionInfo: PrivacyProSubscription?
        var isLoadingSubscriptionInfo: Bool = false

        // Used to display stripe WebUI
        var stripeViewModel: SubscriptionExternalLinkViewModel?
        var isShowingStripeView: Bool = false

        // Display error
        var isShowingConnectionError: Bool = false

        // Used to display the FAQ WebUI
        var faqViewModel: SubscriptionExternalLinkViewModel
        var learnMoreViewModel: SubscriptionExternalLinkViewModel

        init(faqURL: URL, learnMoreURL: URL) {
            self.faqViewModel = SubscriptionExternalLinkViewModel(url: faqURL)
            self.learnMoreViewModel = SubscriptionExternalLinkViewModel(url: learnMoreURL)
        }
    }

    // Publish the currently selected feature
    @Published var selectedFeature: SettingsViewModel.SettingsDeepLinkSection?

    // Read only View State - Should only be modified from the VM
    @Published private(set) var state: State

    public let usesUnifiedFeedbackForm: Bool

    init(subscriptionManager: SubscriptionManagerV2 = AppDependencyProvider.shared.subscriptionManagerV2!) {
        self.subscriptionManager = subscriptionManager
        let subscriptionFAQURL = subscriptionManager.url(for: .faq)
        let learnMoreURL = subscriptionFAQURL.appendingPathComponent("adding-email")
        self.state = State(faqURL: subscriptionFAQURL, learnMoreURL: learnMoreURL)
        self.usesUnifiedFeedbackForm = subscriptionManager.isUserAuthenticated
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
            async let loadedEmailFromCache = await self.fetchAndUpdateAccountEmail(cachePolicy: .cacheOnly)
            async let loadedSubscriptionFromCache = await self.fetchAndUpdateSubscriptionDetails(cachePolicy: .cacheOnly,
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

        var tokensPolicy: AuthTokensCachePolicy = .local
        switch cachePolicy {
        case .remoteFirst:
            tokensPolicy = .localForceRefresh
        case .cacheFirst:
            tokensPolicy = .localValid
        case .cacheOnly:
            tokensPolicy = .local
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
        switch state.subscriptionInfo?.platform {
        case .apple:
            Task { await manageAppleSubscription() }
        case .google:
            displayGoogleView(true)
        case .stripe:
            Task { await manageStripeSubscription() }
        default:
            assertionFailure("Invalid subscription platform")
            return
        }
    }

    // MARK: -

    private func setupNotificationObservers() {
        signOutObserver = NotificationCenter.default.addObserver(forName: .accountDidSignOut, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async {
                self?.state.shouldDismissView = true
            }
        }
    }

    @MainActor
    private func updateSubscriptionsStatusMessage(subscription: PrivacyProSubscription, date: Date, product: String, billingPeriod: PrivacyProSubscription.BillingPeriod) {
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
            await subscriptionManager.signOut(notifyUI: true)
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

    func displayRemovalNotice(_ value: Bool) {
        if value != state.isShowingRemovalNotice {
            state.isShowingRemovalNotice = value
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
                let model = SubscriptionExternalLinkViewModel(url: url, allowedDomains: externalAllowedDomains)
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

    @MainActor
    private func openURL(_ url: URL) {
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    deinit {
        signOutObserver = nil
    }
}
