//
//  SubscriptionOnboardingOrderConfirmationViewModel.swift
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
import Subscription
import os.log

/// A seam over the subscription fetch, so the trial mapping can be exercised without the network.
@MainActor
protocol SubscriptionOnboardingSubscriptionProviding {
    /// The purchased subscription, or `nil` when there is none or it could not be resolved.
    func fetchSubscription() async -> DuckDuckGoSubscription?
}

/// The live provider, reading the cached subscription the rest of the app reads from.
@MainActor
final class DefaultSubscriptionOnboardingSubscriptionProvider: SubscriptionOnboardingSubscriptionProviding {
    private let subscriptionManager: any SubscriptionManager

    init(subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager) {
        self.subscriptionManager = subscriptionManager
    }

    /// Errors are swallowed: the confirmation screen degrades to its paid variant rather than blocking the
    /// customer on the first screen after checkout.
    func fetchSubscription() async -> DuckDuckGoSubscription? {
        do {
            return try await subscriptionManager.getSubscription()
        } catch {
            // TODO|htang: report this with a pixel in Step 3.
            Logger.subscription.error("Order confirmation subscription fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// Backs the order confirmation screen, resolving whether the purchase started a free trial and, if so, the
/// calendar card that describes it.
@MainActor
final class SubscriptionOnboardingOrderConfirmationViewModel: ObservableObject {

    /// What the screen knows about the purchase.
    enum State {
        case loading
        /// A free trial is running; the calendar card renders from this model.
        case freeTrial(SubscriptionOnboardingFreeTrialCalendarCardModel)
        /// A paid purchase — or one whose trial dates don't describe a plausible trial. Neither shows a card.
        case paid
    }

    /// The calendar strip renders one column per trial day, so a span outside this range would render an
    /// unreadable or broken card. Anything else is treated as "no trial".
    private static let plausibleTrialLengths = 1...31

    @Published private(set) var state: State = .loading

    private let subscriptionProvider: SubscriptionOnboardingSubscriptionProviding
    private let now: Date
    private let calendar: Calendar

    /// `subscriptionProvider` is defaulted inside the body rather than in the signature: default arguments
    /// are evaluated in a nonisolated context, and the live provider's initializer is main-actor isolated.
    init(subscriptionProvider: SubscriptionOnboardingSubscriptionProviding? = nil,
         now: Date = Date(),
         calendar: Calendar = .current) {
        self.subscriptionProvider = subscriptionProvider ?? DefaultSubscriptionOnboardingSubscriptionProvider()
        self.now = now
        self.calendar = calendar
    }

    // MARK: - Display values

    /// Omitted until the subscription resolves so the screen shows the correct copy.
    var explanation: String? {
        switch state {
        case .loading: nil
        case .freeTrial: UserText.subscriptionOnboardingOrderConfirmationTrialExplanation
        case .paid: UserText.subscriptionOnboardingOrderConfirmationPaidExplanation
        }
    }

    /// The trial calendar card to render, or `nil` when there is no trial to describe.
    var freeTrialCard: SubscriptionOnboardingFreeTrialCalendarCardModel? {
        guard case .freeTrial(let model) = state else { return nil }
        return model
    }

    // MARK: - Actions

    func load() async {
        guard case .loading = state else { return }
        state = Self.state(for: await subscriptionProvider.fetchSubscription(), now: now, calendar: calendar)
    }
}

// MARK: - Mapping

private extension SubscriptionOnboardingOrderConfirmationViewModel {

    static func state(for subscription: DuckDuckGoSubscription?, now: Date, calendar: Calendar) -> State {
        guard let subscription, subscription.hasActiveTrialOffer else { return .paid }

        // During an active trial `expiresOrRenewsAt` is the date the trial ends and billing begins, which is
        // also what Subscription Settings renders as the trial's end.
        let billingStartDate = subscription.expiresOrRenewsAt
        guard let trialLength = trialLength(from: subscription.startedAt, to: billingStartDate, calendar: calendar) else {
            return .paid
        }

        return .freeTrial(SubscriptionOnboardingFreeTrialCalendarCardModel(freeTrialStartDate: subscription.startedAt,
                                                                          billingStartDate: billingStartDate,
                                                                          trialLength: trialLength,
                                                                          now: now,
                                                                          calendar: calendar))
    }

    /// The trial's whole-day length, or `nil` when the dates don't describe a plausible trial.
    static func trialLength(from start: Date, to billingStart: Date, calendar: Calendar) -> Int? {
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: start),
                                           to: calendar.startOfDay(for: billingStart)).day ?? 0
        return plausibleTrialLengths.contains(days) ? days : nil
    }
}

#if DEBUG

/// A provider that never resolves, so a seeded preview state is never overwritten.
private struct UnresolvedSubscriptionProvider: SubscriptionOnboardingSubscriptionProviding {
    func fetchSubscription() async -> DuckDuckGoSubscription? { nil }
}

extension SubscriptionOnboardingOrderConfirmationViewModel {
    /// A view model seeded with a fixed state for previews.
    static func preview(state: State) -> SubscriptionOnboardingOrderConfirmationViewModel {
        let viewModel = SubscriptionOnboardingOrderConfirmationViewModel(subscriptionProvider: UnresolvedSubscriptionProvider())
        viewModel.state = state
        return viewModel
    }
}

extension SubscriptionOnboardingOrderConfirmationViewModel.State {
    /// A deterministic free-trial state: a `length`-day trial that started `dayOffset` days ago, so previews
    /// render a stable "Day N" regardless of the current date.
    static func previewFreeTrial(dayOffset: Int = 0, length: Int = 7) -> Self {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.locale = Locale(identifier: "en_US")

        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 7)) ?? Date()
        let now = calendar.date(byAdding: .day, value: dayOffset, to: start) ?? start
        let billing = calendar.date(byAdding: .day, value: length, to: start) ?? start

        return .freeTrial(SubscriptionOnboardingFreeTrialCalendarCardModel(freeTrialStartDate: start,
                                                                           billingStartDate: billing,
                                                                           trialLength: length,
                                                                           now: now,
                                                                           calendar: calendar))
    }
}

#endif
