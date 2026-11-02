//
//  SubscriptionWithdrawalFlowModel.swift
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

/// Display-ready values for the "Withdraw from Contract" row and its confirmation alert.
struct SubscriptionWithdrawalOffer: Equatable {
    let eligibleUntil: String?
    let refundAmount: String
    let tierName: String
    let entitlements: [SubscriptionEntitlement]
}

/// Display-ready values for the withdrawn screen shown after a successful withdrawal.
struct SubscriptionWithdrawalConfirmation: Equatable {
    let withdrawalDate: String
    let refundAmount: String
}

final class SubscriptionWithdrawalFlowModel: ObservableObject {

    @Published private(set) var eligibility: WithdrawalEligibility?
    @Published var isShowingError = false

    private static let amountLocale = Locale(identifier: "en_US_POSIX")

    private let subscriptionManager: SubscriptionManager
    private let featureFlagger: FeatureFlagger
    private let locale: Locale
    private let dateFormatter: DateFormatter
    private let instrumentation: SubscriptionWithdrawalInstrumenting
    private let openURL: @MainActor (URL) -> Void
    private var isWithdrawing = false
    private lazy var currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        return formatter
    }()

    init(subscriptionManager: SubscriptionManager,
         featureFlagger: FeatureFlagger,
         locale: Locale,
         dateFormatter: DateFormatter,
         instrumentation: SubscriptionWithdrawalInstrumenting = SubscriptionWithdrawalInstrumentation(),
         openURL: @escaping @MainActor (URL) -> Void) {
        self.subscriptionManager = subscriptionManager
        self.featureFlagger = featureFlagger
        self.locale = locale
        self.dateFormatter = dateFormatter
        self.instrumentation = instrumentation
        self.openURL = openURL
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
        let message = UserText.subscriptionWithdrawConfirmMessage(tierName: offer.tierName, refundAmount: offer.refundAmount)
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
        let listFormatter = ListFormatter()
        listFormatter.locale = locale
        guard let list = listFormatter.string(from: featureNames) else { return message }
        return message + "\n\n" + UserText.subscriptionWithdrawConfirmFeaturesMessage(features: list)
    }

    @MainActor
    func fetchEligibility() async {
        guard featureFlagger.isFeatureOn(.stripeInternationalSubscriptionWithdrawal),
              subscriptionManager.isUserAuthenticated else { return }
        do {
            eligibility = try await subscriptionManager.getWithdrawalEligibility()
        } catch {
            Logger.subscription.error("Failed to fetch withdrawal eligibility: \(error, privacy: .public)")
            instrumentation.eligibilityFailed(error)
        }
    }

    @MainActor
    func withdraw() async -> SubscriptionWithdrawalConfirmation? {
        guard !isWithdrawing else { return nil }
        isWithdrawing = true
        defer { isWithdrawing = false }
        instrumentation.confirmClicked()

        do {
            let response = try await subscriptionManager.withdrawSubscription()
            let confirmation = SubscriptionWithdrawalConfirmation(withdrawalDate: dateFormatter.string(from: response.requestedAt ?? Date()),
                                                                  refundAmount: formattedAmount(response.refundedAmount, currency: response.currency))
            await subscriptionManager.signOut(notifyUI: true, userInitiated: true)
            return confirmation
        } catch {
            instrumentation.withdrawalFailed(error)
            if case SubscriptionEndpointServiceError.invalidResponseCode(.conflict) = error {
                eligibility = nil
            } else {
                isShowingError = true
            }
        }
        return nil
    }

    func withdrawTapped() {
        instrumentation.withdrawClicked()
        instrumentation.dialogShown()
    }

    func keepTapped() {
        instrumentation.keepClicked()
    }

    @MainActor
    func openHelpPage() {
        let helpURL = URL(string: AppDeepLinkSchemes.quickLink.appending(subscriptionManager.url(for: .helpPagesCancelOrChangeSubscription).absoluteString))!
        openURL(helpURL)
    }

    private func formattedAmount(_ amount: String?, currency: String?) -> String {
        let currencyCode = currency?.uppercased()
        guard let amount, let currencyCode,
              let decimal = Decimal(string: amount, locale: Self.amountLocale) else {
            return [amount, currencyCode].compactMap { $0 }.joined(separator: " ")
        }
        currencyFormatter.currencyCode = currencyCode
        return currencyFormatter.string(from: decimal as NSDecimalNumber) ?? "\(amount) \(currencyCode)"
    }
}
