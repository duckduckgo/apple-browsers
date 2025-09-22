//
//  PreferencesSubscriptionSettingsModelV1.swift
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

public final class PreferencesSubscriptionSettingsModelV1: ObservableObject {

    @Published var subscriptionDetails: String?
    @Published var subscriptionStatus: PrivacyProSubscription.Status?
    @Published private var hasActiveTrialOffer: Bool = false

    @Published var email: String?
    var hasEmail: Bool { !(email?.isEmpty ?? true) }

    private var subscriptionPlatform: PrivacyProSubscription.Platform?
    var currentPurchasePlatform: SubscriptionEnvironment.PurchasePlatform { subscriptionManager.currentEnvironment.purchasePlatform }

    private let subscriptionManager: SubscriptionManager
    private var accountManager: AccountManager {
        subscriptionManager.accountManager
    }
    private let userEventHandler: (PreferencesSubscriptionSettingsModelV2.UserEvent) -> Void
    private var fetchSubscriptionDetailsTask: Task<(), Never>?

    private var subscriptionChangeObserver: Any?

    @Published public var settingsState: PreferencesSubscriptionSettingsState = .subscriptionPendingActivation

    private var cancellables = Set<AnyCancellable>()

    public init(userEventHandler: @escaping (PreferencesSubscriptionSettingsModelV2.UserEvent) -> Void,
                subscriptionManager: SubscriptionManager,
                subscriptionStateUpdate: AnyPublisher<PreferencesSidebarSubscriptionState, Never>) {
        self.subscriptionManager = subscriptionManager
        self.userEventHandler = userEventHandler

        Task {
            await self.updateSubscription(cachePolicy: .returnCacheDataElseLoad)
        }

        self.email = accountManager.email

        subscriptionChangeObserver = NotificationCenter.default.addObserver(forName: .subscriptionDidChange, object: nil, queue: .main) { _ in
            Logger.general.debug("SubscriptionDidChange notification received")
            guard self.fetchSubscriptionDetailsTask == nil else { return }
            self.fetchSubscriptionDetailsTask = Task { [weak self] in
                defer {
                    self?.fetchSubscriptionDetailsTask = nil
                }

                await self?.fetchEmail()
                await self?.updateSubscription(cachePolicy: .returnCacheDataElseLoad)
            }
        }

        Publishers.CombineLatest3($subscriptionStatus, $hasActiveTrialOffer, subscriptionStateUpdate)
            .map { status, hasTrialOffer, state in
                let isSubscriptionActive: Bool? = {
                    guard let status else { return nil }
                    return status != .expired && status != .inactive
                }()

                // Check for free trial first
                if hasTrialOffer && isSubscriptionActive == true {
                    return PreferencesSubscriptionSettingsState.subscriptionFreeTrialActive
                }

                switch (isSubscriptionActive, state.hasAnyEntitlement) {
                case (.some(false), _): return PreferencesSubscriptionSettingsState.subscriptionExpired
                case (nil, _): return PreferencesSubscriptionSettingsState.subscriptionPendingActivation
                case (.some(true), false): return PreferencesSubscriptionSettingsState.subscriptionPendingActivation
                case (.some(true), true): return PreferencesSubscriptionSettingsState.subscriptionActive
                }
            }
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
        userEventHandler(.openURL(.purchase))
    }

    enum ChangePlanOrBillingAction {
        case presentSheet(ManageSubscriptionSheet)
        case navigateToManageSubscription(() -> Void)
    }

    @MainActor
    func changePlanOrBillingAction() async -> ChangePlanOrBillingAction {
        userEventHandler(.didClickChangePlanOrBilling)

        switch subscriptionPlatform {
        case .apple:
            if await confirmIfSignedInToSameAccount() {
                return .navigateToManageSubscription { [weak self] in
                    self?.changePlanOrBilling(for: .appStore)
                }
            } else {
                return .presentSheet(.apple)
            }
        case .google:
            return .presentSheet(.google)
        case .stripe:
            return .navigateToManageSubscription { [weak self] in
                self?.changePlanOrBilling(for: .stripe)
            }
        default:
            assertionFailure("Missing or unknown subscriptionPlatform")
            return .navigateToManageSubscription { }
        }
    }

    private func changePlanOrBilling(for environment: SubscriptionEnvironment.PurchasePlatform) {
        switch environment {
        case .appStore:
            userEventHandler(.openManageSubscriptionsInAppStore)
        case .stripe:
            Task {
                guard let accessToken = accountManager.accessToken, let externalID = accountManager.externalID,
                      case let .success(response) = await subscriptionManager.subscriptionEndpointService.getCustomerPortalURL(accessToken: accessToken, externalID: externalID) else { return }
                guard let url = URL(string: response.customerPortalUrl) else { return }

                userEventHandler(.openCustomerPortalURL(url))
            }
        }
    }

    private func confirmIfSignedInToSameAccount() async -> Bool {
        if #available(macOS 12.0, *) {
            guard let lastTransactionJWSRepresentation = await subscriptionManager.storePurchaseManager().mostRecentTransaction() else { return false }
            switch await subscriptionManager.authEndpointService.storeLogin(signature: lastTransactionJWSRepresentation) {
            case .success(let response):
                return response.externalID == accountManager.externalID
            case .failure:
                return false
            }
        }

        return false
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
        Task {
            if subscriptionPlatform == .apple && currentPurchasePlatform == .appStore {
                if #available(macOS 12.0, iOS 15.0, *) {
                    let appStoreAccountManagementFlow = DefaultAppStoreAccountManagementFlow(authEndpointService: subscriptionManager.authEndpointService,
                                                                                             storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                                             accountManager: subscriptionManager.accountManager)
                    await appStoreAccountManagementFlow.refreshAuthTokenIfNeeded()
                }
            }

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
    }

    @MainActor
    func removeFromThisDeviceAction() {
        userEventHandler(.didClickRemoveSubscription)
        accountManager.signOut()
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
                    let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: subscriptionManager.accountManager,
                                                                         storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                         subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                                         authEndpointService: subscriptionManager.authEndpointService)
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
            await self?.updateSubscription(cachePolicy: .reloadIgnoringLocalCacheData)
        }
    }

    @MainActor func fetchEmail() async {
        guard let accessToken = accountManager.accessToken else { return }

        if case let .success(response) = await subscriptionManager.authEndpointService.validateToken(accessToken: accessToken) {
            email = response.account.email
            if accountManager.email != response.account.email {
                accountManager.storeAccount(token: accessToken, email: response.account.email, externalID: response.account.externalID)
            }
        }
    }

    @MainActor
    private func updateSubscription(cachePolicy: APICachePolicy) async {
        guard let token = accountManager.accessToken else {
            subscriptionManager.subscriptionEndpointService.signOut()
            return
        }

        switch await subscriptionManager.subscriptionEndpointService.getSubscription(accessToken: token, cachePolicy: cachePolicy) {
        case .success(let subscription):
            updateDescription(for: subscription)
            subscriptionPlatform = subscription.platform
            subscriptionStatus = subscription.status
            hasActiveTrialOffer = subscription.hasActiveTrialOffer
        case .failure:
            break
        }
    }

    @MainActor
    func updateDescription(for subscription: PrivacyProSubscription) {

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

public enum PreferencesSubscriptionSettingsState: String {
    case subscriptionPendingActivation, subscriptionActive, subscriptionExpired, subscriptionFreeTrialActive
}
