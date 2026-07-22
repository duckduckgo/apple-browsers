//
//  SubscriptionOnboardingViewFactory.swift
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

import SwiftUI

/// Builds the views for the post-subscription onboarding flow. The flow view model owns a factory and asks it
/// for the current section's screen — passing itself as the section's ``SubscriptionOnboardingSectionDelegate``
/// and its ``SubscriptionOnboardingPrefetcher`` — so the flow itself stays view-agnostic.
protocol SubscriptionOnboardingViewFactory {
    @MainActor
    func makeView(for section: SubscriptionOnboardingSection,
                  delegate: SubscriptionOnboardingSectionDelegate,
                  prefetcher: SubscriptionOnboardingPrefetcher) -> AnyView
}

/// The default factory: builds each section's screen with a view model wired to the flow's delegate and
/// shared prefetcher.
struct DefaultSubscriptionOnboardingViewFactory: SubscriptionOnboardingViewFactory {
    @MainActor
    func makeView(for section: SubscriptionOnboardingSection,
                  delegate: SubscriptionOnboardingSectionDelegate,
                  prefetcher: SubscriptionOnboardingPrefetcher) -> AnyView {
        switch section {
        case .vpn:
            let viewModel = SubscriptionOnboardingVPNActivationViewModel(prefetcher: prefetcher, delegate: delegate)
            return AnyView(SubscriptionOnboardingVPNActivationView(viewModel: viewModel).subscriptionOnboardingNavigationContainer())
        case .duckAI:
            let viewModel = SubscriptionOnboardingDuckAIViewModel(prefetcher: prefetcher, delegate: delegate)
            return AnyView(SubscriptionOnboardingDuckAIView(viewModel: viewModel).subscriptionOnboardingNavigationContainer())
        }
    }
}
