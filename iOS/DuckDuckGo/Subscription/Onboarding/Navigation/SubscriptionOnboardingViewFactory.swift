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

/// Builds the views for the post-subscription onboarding flow. The flow view model (next PR) owns a
/// factory and asks it for the current section's screen, so the flow itself stays view-agnostic.
protocol SubscriptionOnboardingViewFactory {
    func makeView(for section: SubscriptionOnboardingSection) -> AnyView
}

/// The default factory. The real section screens are wired in as later checkpoints build them (VPN and
/// Duck.ai); until then each section renders a placeholder.
struct DefaultSubscriptionOnboardingViewFactory: SubscriptionOnboardingViewFactory {
    func makeView(for section: SubscriptionOnboardingSection) -> AnyView {
        switch section {
        case .vpn:
            return AnyView(SubscriptionOnboardingVPNActivationView().subscriptionOnboardingNavigationContainer())
        case .duckAI:
            return AnyView(SubscriptionOnboardingDuckAIView().subscriptionOnboardingNavigationContainer())
        }
    }
}
