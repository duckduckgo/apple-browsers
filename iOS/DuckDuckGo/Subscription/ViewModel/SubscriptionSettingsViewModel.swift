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
import BrowserServicesKit
import Networking

final class SubscriptionSettingsViewModel: ObservableObject {
    
    private let subscriptionManager: SubscriptionManager
    private var signOutObserver: Any?
    
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

    public let enablesUnifiedFeedbackForm: Bool

    init(subscriptionManager: SubscriptionManager = AppDependencyProvider.shared.subscriptionManager!) {
        self.subscriptionManager = subscriptionManager
        let subscriptionFAQURL = subscriptionManager.url(for: .faq)
        let learnMoreURL = subscriptionFAQURL.appendingPathComponent("adding-email")
        self.state = State(faqURL: subscriptionFAQURL, learnMoreURL: learnMoreURL)
        self.enablesUnifiedFeedbackForm = subscriptionManager.accountManager.isUserAuthenticated

        setupNotificationObservers()
    }
    
    private var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
    
    func onFirstAppear() {
        Task {
            // Load initial state from the cache
            async let loadedEmailFromCache = await self.fetchAndUpdateAccountEmail(cachePolicy: .returnCacheDataElseLoad)
            async let loadedSubscriptionFromCache = await self.fetchAndUpdateSubscriptionDetails(cachePolicy: .returnCacheDataElseLoad,
                                                                                                 loadingIndicator: false)
            let (hasLoadedEmailFromCache, hasLoadedSubscriptionFromCache) = await (loadedEmailFromCache, loadedSubscriptionFromCache)
            
            // Reload remote subscription and email state
            async let reloadedEmail = await self.fetchAndUpdateAccountEmail(cachePolicy: .reloadIgnoringLocalCacheData)
            async let reloadedSubscription = await self.fetchAndUpdateSubscriptionDetails(cachePolicy: .reloadIgnoringLocalCacheData,
                                                                                          loadingIndicator: !hasLoadedSubscriptionFromCache)
            let (hasReloadedEmail, hasReloadedSubscription) = await (reloadedEmail, reloadedSubscription)
        }
    }
    
    private func fetchAndUpdateSubscriptionDetails(cachePolicy: APICachePolicy, loadingIndicator: Bool) async -> Bool {
        Logger.subscription.debug("\(#function)")
        guard let token = self.subscriptionManager.accountManager.accessToken else { return false }
        
        if loadingIndicator { displaySubscriptionLoader(true) }
        let subscriptionResult = await self.subscriptionManager.subscriptionEndpointService.getSubscription(accessToken: token,
                                                                                                            cachePolicy: cachePolicy)
        switch subscriptionResult {
        case .success(let subscription):
            DispatchQueue.main.async {
                self.state.subscriptionInfo = subscription
                if loadingIndicator { self.displaySubscriptionLoader(false) }
            }
            await updateSubscriptionsStatusMessage(subscription: subscription,
                                                   date: subscription.expiresOrRenewsAt,
                                                   product: subscription.productId,
                                                   billingPeriod: subscription.billingPeriod)
            return true
        case .failure(let error):
            Logger.subscription.error("\(#function) error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                if loadingIndicator { self.displaySubscriptionLoader(true) }
            }
            return false
        }
    }
    
    func fetchAndUpdateAccountEmail(cachePolicy: APICachePolicy = .returnCacheDataElseLoad) async -> Bool {
        Logger.subscription.debug("\(#function)")
        guard let token = self.subscriptionManager.accountManager.accessToken else { return false }
        
        switch cachePolicy {
        case .returnCacheDataElseLoad:
            DispatchQueue.main.async {
                self.state.subscriptionEmail = self.subscriptionManager.accountManager.email
            }
            return true
        case .reloadIgnoringLocalCacheData:
            break
        }

        switch await self.subscriptionManager.accountManager.fetchAccountDetails(with: token) {
        case .success(let details):
            Logger.subscription.debug("Account details fetched successfully")
            DispatchQueue.main.async {
                self.state.subscriptionEmail = details.email
            }
            
            // If fetched email is different then update accountManager
            if details.email != subscriptionManager.accountManager.email {
                let externalID = subscriptionManager.accountManager.externalID
                subscriptionManager.accountManager.storeAccount(token: token, email: details.email, externalID: externalID)
            }
            return true
        case .failure(let error):
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
        Logger.subscription.debug("User action: \(#function)")

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
        subscriptionManager.accountManager.signOut(skipNotification: false, userInitiated: true)
        _ = ActionMessageView()
        ActionMessageView.present(message: UserText.subscriptionRemovalConfirmation,
                                  presentationLocation: .withoutBottomBar)
    }
    
    func displayGoogleView(_ value: Bool) {
        if value != state.isShowingGoogleView {
            state.isShowingGoogleView = value
        }
    }
    
    func displayStripeView(_ value: Bool) {
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
    
    func displayFAQView(_ value: Bool) {
        if value != state.isShowingFAQView {
            state.isShowingFAQView = value
        }
    }
    
    func displayLearnMoreView(_ value: Bool) {
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
        guard let token = subscriptionManager.accountManager.accessToken,
              let externalID = subscriptionManager.accountManager.externalID else { return }
        let serviceResponse = await  subscriptionManager.subscriptionEndpointService.getCustomerPortalURL(accessToken: token, externalID: externalID)
        
        // Get Stripe Customer Portal URL and update the model
        if case .success(let response) = serviceResponse {
            guard let url = URL(string: response.customerPortalUrl) else { return }
            if let existingModel = state.stripeViewModel {
                existingModel.url = url
            } else {
                let model = SubscriptionExternalLinkViewModel(url: url, allowedDomains: externalAllowedDomains)
                DispatchQueue.main.async {
                    self.state.stripeViewModel = model
                }
            }
        }
        DispatchQueue.main.async {
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
    }
}
