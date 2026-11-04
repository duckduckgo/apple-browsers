//
//  PreferencesSubscriptionWithdrawalModel.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import Networking
import Subscription

struct SubscriptionWithdrawalOffer: Equatable {
    let eligibleUntil: String?
    let refundAmount: String?
    let tierName: String
    let entitlements: [SubscriptionEntitlement]
}

struct SubscriptionWithdrawalConfirmation: Equatable {
    let withdrawalDate: String
    let refundAmount: String?
}

final class PreferencesSubscriptionWithdrawalModel: ObservableObject {

    @Published private(set) var eligibility: WithdrawalEligibility?
    @Published private(set) var subscription: DuckDuckGoSubscription?
    @Published var isShowingError = false
    @Published private(set) var isWithdrawing = false
    @Published private(set) var confirmation: SubscriptionWithdrawalConfirmation?

    private static let amountLocale = Locale(identifier: "en_US_POSIX")

    private let subscriptionManager: SubscriptionManager
    private let isFeatureEnabled: () -> Bool
    private let locale: Locale
    private let userEventHandler: (PreferencesSubscriptionSettingsModel.UserEvent) -> Void
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
    private lazy var currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        return formatter
    }()
    private lazy var listFormatter: ListFormatter = {
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter
    }()

    init(subscriptionManager: SubscriptionManager,
         isFeatureEnabled: @escaping () -> Bool,
         locale: Locale = .current,
         userEventHandler: @escaping (PreferencesSubscriptionSettingsModel.UserEvent) -> Void) {
        self.subscriptionManager = subscriptionManager
        self.isFeatureEnabled = isFeatureEnabled
        self.locale = locale
        self.userEventHandler = userEventHandler
        dateFormatter.locale = locale
    }

    var offer: SubscriptionWithdrawalOffer? {
        guard isFeatureEnabled(),
              let subscription,
              subscription.platform == .stripe,
              let eligibility,
              eligibility.eligible else {
            return nil
        }
        return SubscriptionWithdrawalOffer(eligibleUntil: eligibility.eligibleUntil.map { dateFormatter.string(from: $0) },
                                           refundAmount: formattedAmount(eligibility.refundAmount, currency: eligibility.refundCurrency),
                                           tierName: (subscription.tier ?? .plus).rawValue.capitalized,
                                           entitlements: subscription.features ?? [])
    }

    var helpPageURL: URL {
        subscriptionManager.url(for: .helpPagesCancelOrChangeSubscription)
    }

    func confirmationMessage(for offer: SubscriptionWithdrawalOffer) -> String {
        let message = offer.refundAmount.map { UserText.withdrawDialogMessage(tierName: offer.tierName, refundAmount: $0) }
            ?? UserText.withdrawDialogMessage(tierName: offer.tierName)
        let entitlements = Set(offer.entitlements)
        var featureNames: [String] = []
        if entitlements.contains(.networkProtection) {
            featureNames.append(UserText.vpnServiceTitle)
        }
        if entitlements.contains(.dataBrokerProtection) {
            featureNames.append(UserText.personalInformationRemovalServiceTitle)
        }
        if entitlements.contains(.identityTheftRestoration) || entitlements.contains(.identityTheftRestorationGlobal) {
            featureNames.append(UserText.identityTheftRestorationServiceTitle)
        }
        if entitlements.contains(.paidAIChat) {
            featureNames.append(UserText.paidAIChatTitle)
        }
        guard !featureNames.isEmpty, let list = listFormatter.string(from: featureNames) else { return message }
        return message + "\n\n" + UserText.withdrawDialogFeaturesMessage(features: list)
    }

    @MainActor
    func fetchEligibility(for subscription: DuckDuckGoSubscription) async {
        self.subscription = subscription
        guard isFeatureEnabled(),
              subscriptionManager.isUserAuthenticated,
              subscription.platform == .stripe else {
            eligibility = nil
            return
        }
        do {
            eligibility = try await subscriptionManager.getWithdrawalEligibility()
        } catch {
            eligibility = nil
            userEventHandler(.withdrawalEligibilityDidFail(error))
        }
    }

    @MainActor
    func withdraw() async {
        guard !isWithdrawing else { return }
        isWithdrawing = true
        userEventHandler(.didClickConfirmWithdrawal)
        userEventHandler(.withdrawalDidStart)

        do {
            let response = try await subscriptionManager.withdrawSubscription()
            finishWithdrawing()
            confirmation = SubscriptionWithdrawalConfirmation(withdrawalDate: dateFormatter.string(from: response.requestedAt ?? Date()),
                                                              refundAmount: formattedAmount(response.refundedAmount, currency: response.currency)
                                                                ?? formattedAmount(eligibility?.refundAmount, currency: eligibility?.refundCurrency))
        } catch {
            finishWithdrawing()
            userEventHandler(.withdrawalDidFail(error))
            if case SubscriptionEndpointServiceError.invalidResponseCode(.conflict) = error {
                eligibility = nil
            } else {
                isShowingError = true
            }
        }
    }

    @MainActor
    private func finishWithdrawing() {
        isWithdrawing = false
        userEventHandler(.withdrawalDidFinish)
    }

    @MainActor
    func completeWithdrawalIfNeeded() async {
        guard confirmation != nil else { return }
        await subscriptionManager.signOut(notifyUI: true, userInitiated: true)
        confirmation = nil
        eligibility = nil
    }

    @MainActor
    func withdrawTapped() {
        userEventHandler(.didClickWithdraw)
    }

    @MainActor
    func confirmationShown() {
        userEventHandler(.didShowWithdrawalDialog)
    }

    @MainActor
    func keepTapped() {
        userEventHandler(.didClickKeepSubscription)
    }

    @MainActor
    func openHelpPage() {
        userEventHandler(.openURL(.helpPagesCancelOrChangeSubscription))
    }

    private func formattedAmount(_ amount: String?, currency: String?) -> String? {
        guard let amount, let currencyCode = currency?.uppercased() else { return nil }
        currencyFormatter.currencyCode = currencyCode
        guard let decimal = Decimal(string: amount, locale: Self.amountLocale),
              let formatted = currencyFormatter.string(from: decimal as NSDecimalNumber) else {
            return "\(amount) \(currencyCode)"
        }
        return formatted
    }
}
