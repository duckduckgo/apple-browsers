//
//  SubscriptionOnboardingVPNTipsCarousel.swift
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

/// The "What to know about using your VPN" carousel: three horizontally-scrolling cards, each an icon +
/// headline + body. Cards are a fixed width with the neighbours peeking at the edges; the row scrolls
/// freely. Each card reuses
/// `SubscriptionOnboardingCard` + `CardItem` for its surface and content.
struct SubscriptionOnboardingVPNTipsCarousel: View {
    private enum Metrics {
        static let cardWidth: CGFloat = 217
        static let horizontalPadding: CGFloat = 28
        static let verticalPadding: CGFloat = 32
        static let cardSpacing: CGFloat = 16
        static let iconSpacing: CGFloat = 4
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Metrics.cardSpacing) {
                ForEach(Tip.allCases, id: \.self) { tip in
                    card(for: tip)
                }
            }
        }
    }

    private enum Tip: CaseIterable {
        case noCaps
        case speed
        case blocked

        var icon: Image {
            switch self {
            case .noCaps: Image(.keyhole56)
            case .speed: Image(.responseGood56)
            case .blocked: Image(.onboardingVPN56)
            }
        }

        var title: String {
            switch self {
            case .noCaps: UserText.subscriptionOnboardingVPNTipNoCapsTitle
            case .speed: UserText.subscriptionOnboardingVPNTipSpeedTitle
            case .blocked: UserText.subscriptionOnboardingVPNTipBlockedTitle
            }
        }

        var bodyText: String {
            switch self {
            case .noCaps: UserText.subscriptionOnboardingVPNTipNoCapsBody
            case .speed: UserText.subscriptionOnboardingVPNTipSpeedBody
            case .blocked: UserText.subscriptionOnboardingVPNTipBlockedBody
            }
        }
    }
}

extension SubscriptionOnboardingVPNTipsCarousel {
    private func card(for tip: Tip) -> some View {
        SubscriptionOnboardingCard(
            CardItem(
                icon: CardItemIcon(position: .topLeading, visual: .image(tip.icon), size: .size56, spacing: Metrics.iconSpacing),
                title: CardItemText(tip.title, font: .headline),
                text: CardItemText(tip.bodyText, font: .subheadRegular)),
            style: .borderless,
            contentInset: .init(horizontal: Metrics.horizontalPadding, vertical: Metrics.verticalPadding))
        .frame(width: Metrics.cardWidth)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG

private struct SubscriptionOnboardingVPNTipsCarouselPreview: View {
    var body: some View {
        VStack {
            Spacer()
            SubscriptionOnboardingVPNTipsCarousel()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(designSystemColor: .surfaceTertiary).ignoresSafeArea())
    }
}

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingVPNTipsCarouselPreview()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingVPNTipsCarouselPreview()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingVPNTipsCarouselPreview()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
