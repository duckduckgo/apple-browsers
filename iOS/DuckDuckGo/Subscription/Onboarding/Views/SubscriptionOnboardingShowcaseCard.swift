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

/// A showcase card presenting a single feature or benefit as an icon above a title and body text.
private enum ShowcaseCardMetrics {
    static let iconSpacing: CGFloat = 8
    static let titleTextSpacing: CGFloat = 4
    static let textBlockLeadingInset: CGFloat = 4
}

struct SubscriptionOnboardingShowcaseCard<Footer: View>: View {
    private let icon: Image
    private let title: String
    private let text: String
    private let footer: Footer

    /// Creates a card whose `footer` renders below the title/body inside the same bordered card (via
    /// `SubscriptionOnboardingCard`'s footer slot) — e.g. the "Devices" card's platform grid.
    init(icon: Image, title: String, text: String, @ViewBuilder footer: () -> Footer) {
        self.icon = icon
        self.title = title
        self.text = text
        self.footer = footer()
    }

    var body: some View {
        SubscriptionOnboardingCard(
            style: .bordered,
            header: { EmptyView() },
            items: {
                VStack(alignment: .leading, spacing: ShowcaseCardMetrics.iconSpacing) {
                    IconBadge(icon: icon)
                    CardItem(
                        title: CardItemText(title, font: .footnoteSemibold),
                        text: CardItemText(text, font: .footnoteRegular),
                        titleTextSpacing: ShowcaseCardMetrics.titleTextSpacing,
                        textBlockLeadingInset: ShowcaseCardMetrics.textBlockLeadingInset)
                }
            },
            footer: { footer.padding(.leading, ShowcaseCardMetrics.textBlockLeadingInset) })
        .accessibilityElement(children: .combine)
    }
}

extension SubscriptionOnboardingShowcaseCard where Footer == EmptyView {
    /// Creates a card with no footer.
    init(icon: Image, title: String, text: String) {
        self.init(icon: icon, title: title, text: text) { EmptyView() }
    }
}

#if DEBUG

private struct SubscriptionOnboardingShowcaseCardPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SubscriptionOnboardingShowcaseCard(
                    icon: Image(systemName: "creditcard.fill"),
                    title: "Recover financial losses",
                    text: """
                        We'll work with financial institutions to help reverse any fraudulent \
                        transactions, and we'll reimburse certain out-of-pocket expenses*** in the \
                        event that you become a victim of identity theft or fraud.
                        """)

                SubscriptionOnboardingShowcaseCard(
                    icon: Image(systemName: "doc.text.magnifyingglass"),
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

#Preview("With footer") {
    RebrandedPreview {
        ScrollView {
            SubscriptionOnboardingShowcaseCard(
                icon: Image(systemName: "laptopcomputer.and.iphone"),
                title: "Devices",
                text: "Full-device coverage on up to 5 devices at once.") {
                SubscriptionOnboardingPlatformGrid()
            }
            .padding()
        }
        .background(Color(designSystemColor: .surfaceTertiary).ignoresSafeArea())
    }
}

#endif
