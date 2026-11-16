//
//  SubscriptionWithdrawalModel.swift
//  DuckDuckGo
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
import Core
import FeatureFlags_iOS
import Networking
import os.log
import PrivacyConfig
import Subscription
import UIKit

/// Display-ready values for the "Withdraw from Contract" row and its confirmation alert.
struct SubscriptionWithdrawalOffer {
    let eligibleUntil: String?
    let refundAmount: String?
    let tierName: String
    let entitlements: [SubscriptionEntitlement]
}

/// Display-ready values for the withdrawn state shown in Subscription Settings after a successful withdrawal.
struct SubscriptionWithdrawalConfirmation {
    let withdrawalDate: String
    let refundAmount: String?
}

final class SubscriptionWithdrawalModel: ObservableObject {

    @Published private(set) var eligibility: WithdrawalEligibility?
    @Published var isShowingError = false
    @Published private(set) var isWithdrawing = false
    @Published private(set) var confirmation: SubscriptionWithdrawalConfirmation?

    private static let amountLocale = Locale(identifier: "en_US_POSIX")

    private let subscriptionManager: SubscriptionManager
    private let featureFlagger: FeatureFlagger
    private let locale: Locale
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
    private let instrumentation: SubscriptionWithdrawalInstrumenting
    private let urlOpener: URLOpener
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
         featureFlagger: FeatureFlagger,
         locale: Locale,
         instrumentation: SubscriptionWithdrawalInstrumenting = SubscriptionWithdrawalInstrumentation(),
         urlOpener: URLOpener = UIApplication.shared) {
        self.subscriptionManager = subscriptionManager
        self.featureFlagger = featureFlagger
        self.locale = locale
        self.instrumentation = instrumentation
        self.urlOpener = urlOpener
    }

    func offer(for subscription: DuckDuckGoSubscription?) -> SubscriptionWithdrawalOffer? {
        guard featureFlagger.isFeatureOn(.stripeInternationalSubscriptionWithdrawal),
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

    func confirmationMessage(for offer: SubscriptionWithdrawalOffer) -> String {
        let message = offer.refundAmount.map { UserText.subscriptionWithdrawConfirmMessage(tierName: offer.tierName, refundAmount: $0) }
            ?? UserText.subscriptionWithdrawConfirmMessage(tierName: offer.tierName)
        let features = Set(offer.entitlements.compactMap(SubscriptionOnboardingChecklistItem.init(entitlement:)))
        let featureNames = [SubscriptionOnboardingChecklistItem.vpn, .pir, .idtr, .duckAI]
            .filter(features.contains)
            .map { feature in
                switch feature {
                case .vpn: return UserText.settingsPProVPNTitle
                case .pir: return UserText.settingsPProDBPTitle
                case .idtr: return UserText.settingsPProITRTitle
                case .duckAI: return UserText.settingsSubscriptionAiChatTitle
                }
            }
        guard !featureNames.isEmpty else { return message }
        guard let list = listFormatter.string(from: featureNames) else { return message }
        return message + "\n\n" + UserText.subscriptionWithdrawConfirmFeaturesMessage(features: list)
    }

    @MainActor
    func fetchEligibility(for subscription: DuckDuckGoSubscription) async {
        guard featureFlagger.isFeatureOn(.stripeInternationalSubscriptionWithdrawal),
              subscriptionManager.isUserAuthenticated,
              subscription.platform == .stripe else { return }
        do {
            eligibility = try await subscriptionManager.getWithdrawalEligibility()
        } catch {
            Logger.subscription.error("Failed to fetch withdrawal eligibility: \(error, privacy: .public)")
            instrumentation.eligibilityFailed(error)
        }
    }

    @MainActor
    func withdraw() async {
        guard !isWithdrawing else { return }
        isWithdrawing = true
        defer { isWithdrawing = false }
        instrumentation.confirmClicked()

        do {
            let response = try await subscriptionManager.withdrawSubscription()
            confirmation = SubscriptionWithdrawalConfirmation(withdrawalDate: dateFormatter.string(from: response.requestedAt ?? Date()),
                                                              refundAmount: formattedAmount(response.refundedAmount, currency: response.currency)
                                                                ?? formattedAmount(eligibility?.refundAmount, currency: eligibility?.refundCurrency))
        } catch {
            instrumentation.withdrawalFailed(error)
            if case SubscriptionEndpointServiceError.invalidResponseCode(.conflict) = error {
                eligibility = nil
            } else {
                isShowingError = true
            }
        }
    }

    func completeWithdrawal() async {
        await subscriptionManager.signOut(notifyUI: true, userInitiated: true)
    }

    func withdrawTapped() {
        instrumentation.withdrawClicked()
    }

    func confirmationShown() {
        instrumentation.dialogShown()
    }

    func keepTapped() {
        instrumentation.keepClicked()
    }

    @MainActor
    func openHelpPage() {
        guard let helpURL = URL(string: AppDeepLinkSchemes.quickLink.appending(subscriptionManager.url(for: .helpPagesCancelOrChangeSubscription).absoluteString)),
              urlOpener.canOpenURL(helpURL) else { return }
        urlOpener.open(helpURL)
    }

    private func formattedAmount(_ amount: String?, currency: String?) -> String? {
        guard let amount, let currencyCode = currency?.uppercased() else { return nil }
        guard let decimal = Decimal(string: amount, locale: Self.amountLocale) else {
            return "\(amount) \(currencyCode)"
        }
        currencyFormatter.currencyCode = currencyCode
        return currencyFormatter.string(from: decimal as NSDecimalNumber) ?? "\(amount) \(currencyCode)"
    }
}
