//
//  SubscriptionOnboardingVPNTipsView.swift
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

/// The post-activation "What to know about using your VPN" screen: the shared tips carousel with a single
/// button that finishes the VPN section and moves the flow to the next one.
struct SubscriptionOnboardingVPNTipsView: View {

    var title: String? = nil
    weak var delegate: SubscriptionOnboardingSectionDelegate?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubscriptionOnboardingBaseView(
            title: title,
            navigationButton: .back({ dismiss() }),
            header: SubscriptionOnboardingHeaderView(title: UserText.subscriptionOnboardingVPNTipsTitle),
            footer: .single(.init(UserText.subscriptionOnboardingVPNTipsDoneButton) { delegate?.sectionDidRequestAdvance() })) {
            SubscriptionOnboardingVPNTipsCarousel()
                .padding(.top, 24)
        }
    }
}

#if DEBUG

#Preview("Tips") {
    RebrandedPreview {
        SubscriptionOnboardingVPNTipsView(
            title: String(format: UserText.subscriptionOnboardingStepIndicatorFormat, 1, 4))
        .subscriptionOnboardingNavigationContainer()
    }
}

#endif
