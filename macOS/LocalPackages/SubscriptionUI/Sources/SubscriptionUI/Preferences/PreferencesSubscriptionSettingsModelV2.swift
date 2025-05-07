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

public final class PreferencesSubscriptionSettingsModelV2: ObservableObject {

    @Published var subscriptionDetails: String?
    @Published var subscriptionStatus: PrivacyProSubscription.Status = .unknown

    @Published var email: String?
    var hasEmail: Bool { !(email?.isEmpty ?? true) }

    private var subscriptionPlatform: PrivacyProSubscription.Platform?
    var currentPurchasePlatform: SubscriptionEnvironment.PurchasePlatform { subscriptionManager.currentEnvironment.purchasePlatform }

    private let subscriptionManager: SubscriptionManagerV2

    private let openURLHandler: (URL) -> Void
    public let userEventHandler: (PreferencesSubscriptionModel.UserEvent) -> Void
    private var fetchSubscriptionDetailsTask: Task<(), Never>?

    private var subscriptionChangeObserver: Any?

    @Published public var settingsState: PreferencesSubscriptionSettingsState = .subscriptionPendingActivation

    private var cancellables = Set<AnyCancellable>()

    public enum UserEvent {
        case openFeedback,
//             iHaveASubscriptionClick,
//             activateSubscriptionViaEmailClick,
//             activateSubscriptionViaRestoreAppStorePurchaseClick,
             manageEmailClick,
             addToDeviceActivationFlow,
             openSubscriptionSettingsClick,
             changePlanOrBillingClick,
             removeSubscriptionClick
    }

    public init(openURLHandler: @escaping (URL) -> Void,
                userEventHandler: @escaping (PreferencesSubscriptionModel.UserEvent) -> Void,
                subscriptionManager: SubscriptionManagerV2,
                subscriptionStateUpdate: AnyPublisher<PreferencesSidebarSubscriptionState, Never>
    ) {
        self.subscriptionManager = subscriptionManager
        self.openURLHandler = openURLHandler
        self.userEventHandler = userEventHandler

        Task {
            await self.updateSubscription(cachePolicy: .returnCacheDataElseLoad)
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
                await self?.updateSubscription(cachePolicy: .returnCacheDataDontLoad)
            }
        }

        Publishers.CombineLatest($subscriptionStatus, subscriptionStateUpdate)
            .map { status, state in

                let hasAnyEntitlement = !state.userEntitlements.isEmpty

                Logger.subscription.debug("""
//Update subscription state:
subscriptionStatus: \(status.rawValue)
hasAnyEntitlement: \(hasAnyEntitlement)
""")

                switch status {
                case .expired, .inactive:
                    return PreferencesSubscriptionSettingsState.subscriptionExpired
                case .autoRenewable, .notAutoRenewable, .gracePeriod:
                    if hasAnyEntitlement {
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
        userEventHandler(.openSubscriptionSettingsClick)
        fetchAndUpdateSubscriptionDetails()
    }

    @MainActor
    func purchaseAction() {
        openURLHandler(subscriptionManager.url(for: .purchase))
    }

    enum ChangePlanOrBillingAction {
        case presentSheet(ManageSubscriptionSheet)
        case navigateToManageSubscription(() -> Void)
    }

    @MainActor
    func changePlanOrBillingAction() async -> ChangePlanOrBillingAction {

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
            NSWorkspace.shared.open(subscriptionManager.url(for: .manageSubscriptionsInAppStore))
        case .stripe:
            Task {
                do {
                    let customerPortalURL = try await subscriptionManager.getCustomerPortalURL()
                    openURLHandler(customerPortalURL)
                } catch {
                    Logger.general.log("Error getting customer portal URL: \(error, privacy: .public)")
                }
            }
        }
    }

    private func confirmIfSignedInToSameAccount() async -> Bool {
//        if #available(macOS 12.0, *) {
//            guard let lastTransactionJWSRepresentation = await subscriptionManager.storePurchaseManager().mostRecentTransaction() else { return false }
//            switch await subscriptionManager.authEndpointService.storeLogin(signature: lastTransactionJWSRepresentation) {
//            case .success(let response):
//                return response.externalID == accountManager.externalID
//            case .failure:
//                return false
//            }
//        }

        return false
    }

    @MainActor
    func openLearnMore() {
        let learnMoreURL = URL(string: "https://duckduckgo.com/duckduckgo-help-pages/privacy-pro/adding-email")!
        openURLHandler(learnMoreURL)
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
        let eventType: PreferencesSubscriptionModel.UserEvent
        let url: URL

        switch type {
        case .activationFlow:
            eventType = .addToDeviceActivationFlow
            url = subscriptionManager.url(for: .activationFlow)
        case .activationFlowAddEmailStep:
            eventType = .addToDeviceActivationFlow
            url = subscriptionManager.url(for: .activationFlowAddEmailStep)
        case .activationFlowLinkViaEmailStep:
            eventType = .addToDeviceActivationFlow
            url = subscriptionManager.url(for: .activationFlowLinkViaEmailStep)
        case .editEmail:
            eventType = .manageEmailClick
            url = subscriptionManager.url(for: .manageEmail)
        }

        Task { @MainActor in
            userEventHandler(eventType)
            openURLHandler(url)
        }
    }

    @MainActor
    func removeFromThisDeviceAction() {
        userEventHandler(.removeSubscriptionClick)
        Task {
            await subscriptionManager.signOut(notifyUI: true)
        }
    }

    @MainActor
    func openFAQ() {
        openURLHandler(subscriptionManager.url(for: .faq))
    }

    @MainActor
    func openUnifiedFeedbackForm() {
        userEventHandler(.openFeedback)
    }

    @MainActor
    func openPrivacyPolicy() {
        openURLHandler(subscriptionManager.url(for: .privacyPolicy))
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
            await self?.updateSubscription(cachePolicy: .reloadIgnoringLocalCacheData)
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
                updateDescription(for: subscription.expiresOrRenewsAt, status: subscription.status, period: subscription.billingPeriod)
                subscriptionPlatform = subscription.platform
                subscriptionStatus = subscription.status
            }
        } catch {
            Logger.subscription.error("Error getting subscription: \(error, privacy: .public)")
            Task { @MainActor in
                subscriptionPlatform = .unknown
                subscriptionStatus = .unknown
            }
        }

//        guard let token = accountManager.accessToken else {
//            subscriptionManager.subscriptionEndpointService.signOut()
//            return
//        }
//
//        switch await subscriptionManager.subscriptionEndpointService.getSubscription(accessToken: token, cachePolicy: cachePolicy) {
//        case .success(let subscription):
//            updateDescription(for: subscription.expiresOrRenewsAt, status: subscription.status, period: subscription.billingPeriod)
//            subscriptionPlatform = subscription.platform
//            subscriptionStatus = subscription.status
//        case .failure:
//            break
//        }
    }

    @MainActor
    func updateDescription(for date: Date, status: PrivacyProSubscription.Status, period: PrivacyProSubscription.BillingPeriod) {
        let formattedDate = dateFormatter.string(from: date)

        switch status {
        case .autoRenewable:
            self.subscriptionDetails = UserText.preferencesSubscriptionRenewingCaption(billingPeriod: period, formattedDate: formattedDate)
        case .expired, .inactive:
            self.subscriptionDetails = UserText.preferencesSubscriptionExpiredCaption(formattedDate: formattedDate)
        default:
            self.subscriptionDetails = UserText.preferencesSubscriptionExpiringCaption(billingPeriod: period, formattedDate: formattedDate)
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
