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

/// The live provider, reading the cached subscription
@MainActor
final class DefaultSubscriptionOnboardingSubscriptionProvider: SubscriptionOnboardingSubscriptionProviding {
    private let subscriptionManager: any SubscriptionManager

    init(subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager) {
        self.subscriptionManager = subscriptionManager
    }

    /// Errors are swallowed; screen degrades to paid variant.
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

@MainActor
final class SubscriptionOnboardingOrderConfirmationViewModel: ObservableObject {

    enum State {
        case loading
        /// A free trial is running; the calendar card renders from this model.
        case freeTrial(SubscriptionOnboardingFreeTrialCalendarCardModel)
        /// Paid purchase or implausible trial dates (no card shown).
        case paid
    }

    /// Lengths the calendar strip can draw
    private static let drawableTrialLengths = 1...10

    @Published private(set) var state: State = .loading

    private let subscriptionProvider: SubscriptionOnboardingSubscriptionProviding
    private let now: Date
    private let calendar: Calendar
    private let onNext: () -> Void

    init(subscriptionProvider: SubscriptionOnboardingSubscriptionProviding? = nil,
         now: Date = Date(),
         calendar: Calendar = .current,
         onNext: @escaping () -> Void = {}) {
        self.subscriptionProvider = subscriptionProvider ?? DefaultSubscriptionOnboardingSubscriptionProvider()
        self.now = now
        self.calendar = calendar
        self.onNext = onNext
    }

    // MARK: - Display values

    var freeTrialCard: SubscriptionOnboardingFreeTrialCalendarCardModel? {
        guard case .freeTrial(let model) = state else { return nil }
        return model
    }

    // MARK: - Actions

    func load() async {
        guard case .loading = state else { return }
        state = Self.state(for: await subscriptionProvider.fetchSubscription(), now: now, calendar: calendar)
    }

    func proceed() {
        onNext()
    }
}

// MARK: - Mapping

private extension SubscriptionOnboardingOrderConfirmationViewModel {

    static func state(for subscription: DuckDuckGoSubscription?, now: Date, calendar: Calendar) -> State {
        guard let subscription,
              let trialLength = subscription.trialLengthInDays(calendar: calendar),
              drawableTrialLengths.contains(trialLength) else { return .paid }

        return .freeTrial(SubscriptionOnboardingFreeTrialCalendarCardModel(freeTrialStartDate: subscription.startedAt,
                                                                          billingStartDate: subscription.expiresOrRenewsAt,
                                                                          trialLength: trialLength,
                                                                          now: now,
                                                                          calendar: calendar))
    }
}

#if DEBUG

private struct UnresolvedSubscriptionProvider: SubscriptionOnboardingSubscriptionProviding {
    func fetchSubscription() async -> DuckDuckGoSubscription? { nil }
}

extension SubscriptionOnboardingOrderConfirmationViewModel {
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
