//
//  SubscriptionOnboardingShowcaseCard.swift
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
import UIComponents

/// A showcase card for the post-subscription onboarding flow: a bordered card presenting a single feature
/// or benefit as a top-leading icon above a title and a paragraph of body text (e.g. an Identity Theft
/// Restoration benefit). Built from `SubscriptionOnboardingCard` + `CardItem`.
struct SubscriptionOnboardingShowcaseCard: View {
    private enum Metrics {
        static let iconSpacing: CGFloat = 8
        static let titleTextSpacing: CGFloat = 4
        static let textBlockLeadingInset: CGFloat = 2
    }

    private let visual: Graphic
    private let title: String
    private let text: String

    init(visual: Graphic, title: String, text: String) {
        self.visual = visual
        self.title = title
        self.text = text
    }

    var body: some View {
        SubscriptionOnboardingCard(
            CardItem(
                icon: CardItemIcon(position: .topLeading, visual: visual, size: .size32, spacing: Metrics.iconSpacing),
                title: CardItemText(title, font: .footnoteSemibold),
                text: CardItemText(text, font: .footnoteRegular),
                titleTextSpacing: Metrics.titleTextSpacing,
                textBlockLeadingInset: Metrics.textBlockLeadingInset),
            style: .bordered)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG

private struct SubscriptionOnboardingShowcaseCardPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SubscriptionOnboardingShowcaseCard(
                    visual: .image(Image(systemName: "creditcard.fill")),
                    title: "Recover financial losses",
                    text: """
                        We'll work with financial institutions to help reverse any fraudulent \
                        transactions, and we'll reimburse certain out-of-pocket expenses*** in the \
                        event that you become a victim of identity theft or fraud.
                        """)

                SubscriptionOnboardingShowcaseCard(
                    visual: .image(Image(systemName: "doc.text.magnifyingglass")),
                    title: "Fix your credit report",
                    text: "We'll help fix errors in your credit report that result from fraudulent activity.")
            }
            .padding()
        }
        .background(Color(designSystemColor: .surfaceTertiary).ignoresSafeArea())
    }
}

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingShowcaseCardPreview()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingShowcaseCardPreview()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingShowcaseCardPreview()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
