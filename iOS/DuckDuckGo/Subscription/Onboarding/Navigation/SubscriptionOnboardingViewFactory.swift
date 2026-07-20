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
/// factory and asks it for the current section's screen, so the flow itself stays view-agnostic. It also
/// builds the shared "Learn More" info sheets, keyed by ``SubscriptionOnboardingChecklistItem``, which a
/// section presents on demand.
protocol SubscriptionOnboardingViewFactory {
    func makeView(for section: SubscriptionOnboardingSection) -> AnyView
    func makeInfoView(for item: SubscriptionOnboardingChecklistItem, onClose: @escaping () -> Void) -> AnyView
}

/// The default factory. The real section screens are wired in as later checkpoints build them (VPN and
/// Duck.ai); until then each section renders a placeholder.
struct DefaultSubscriptionOnboardingViewFactory: SubscriptionOnboardingViewFactory {
    func makeView(for section: SubscriptionOnboardingSection) -> AnyView {
        switch section {
        case .vpn:
            return AnyView(SubscriptionOnboardingVPNActivationView().subscriptionOnboardingNavigationContainer())
        case .duckAI:
            return AnyView(placeholder(for: section))
        }
    }

    func makeInfoView(for item: SubscriptionOnboardingChecklistItem, onClose: @escaping () -> Void) -> AnyView {
        guard let content = SubscriptionOnboardingInfoContent.content(for: item) else {
            return AnyView(infoPlaceholder(for: item, onClose: onClose))
        }
        return AnyView(SubscriptionOnboardingInfoView(content: content, onClose: onClose)
            .subscriptionOnboardingNavigationContainer())
    }
}

private extension DefaultSubscriptionOnboardingViewFactory {
    func placeholder(for section: SubscriptionOnboardingSection) -> some View {
        SubscriptionOnboardingBaseView {
            Text(verbatim: "\(section)")
        }
    }

    func infoPlaceholder(for item: SubscriptionOnboardingChecklistItem, onClose: @escaping () -> Void) -> some View {
        SubscriptionOnboardingBaseView(navigationButton: .close(onClose)) {
            Text(verbatim: "\(item)")
        }
        .subscriptionOnboardingNavigationContainer()
    }
}
