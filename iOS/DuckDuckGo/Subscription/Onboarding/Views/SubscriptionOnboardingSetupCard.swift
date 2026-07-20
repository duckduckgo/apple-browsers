//
//  SubscriptionOnboardingSetupCard.swift
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
import DesignResourcesKit
import DuckUI
import UIComponents

/// The Subscription Settings re-entry card for the post-subscription onboarding flow: a borderless card
/// with a leading icon, a title carrying the current setup `percentage`, a short body line, and a
/// bottom-pinned primary CTA to resume the flow. Copy comes from `UserText`. Built from
/// `SubscriptionOnboardingCard` + `CardItem`
struct SubscriptionOnboardingSetupCard: View {
    private enum Metrics {
        static let iconSpacing: CGFloat = 12
        static let titleTextSpacing: CGFloat = 4
        static let buttonTopSpacing: CGFloat = 16
    }

    private let visual: Graphic
    private let percentage: Int
    private let onContinue: () -> Void

    init(visual: Graphic,
         percentage: Int,
         onContinue: @escaping () -> Void) {
        self.visual = visual
        self.percentage = percentage
        self.onContinue = onContinue
    }

    var body: some View {
        SubscriptionOnboardingCard(
            CardItem(
                icon: CardItemIcon(position: .leading, visual: visual, size: .size40, spacing: Metrics.iconSpacing),
                title: CardItemText(title, font: .headline),
                text: CardItemText(UserText.subscriptionOnboardingSetupCardBody, font: .bodyRegular),
                titleTextSpacing: Metrics.titleTextSpacing),
            style: .borderless) {
                Button(UserText.subscriptionOnboardingSetupCardButton, action: onContinue)
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .padding(.top, Metrics.buttonTopSpacing)
            }
    }

    private var title: String {
        String(format: UserText.subscriptionOnboardingSetupCardTitleFormat, clampedPercentage)
    }

    // TODO|htang: remove once percentage clamping is centralized in SubscriptionOnboardingFlowViewModel.
    private var clampedPercentage: Int {
        min(max(percentage, 0), 100)
    }
}

#if DEBUG

private struct SubscriptionOnboardingSetupCardPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SubscriptionOnboardingSetupCard(
                    visual: .image(Image(.subscription56)),
                    percentage: 75,
                    onContinue: {})

                SubscriptionOnboardingSetupCard(
                    visual: .image(Image(.subscription56)),
                    percentage: 25,
                    onContinue: {})
            }
            .padding()
        }
        .background(Color(designSystemColor: .surfaceTertiary).ignoresSafeArea())
    }
}

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingSetupCardPreview()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingSetupCardPreview()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingSetupCardPreview()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
