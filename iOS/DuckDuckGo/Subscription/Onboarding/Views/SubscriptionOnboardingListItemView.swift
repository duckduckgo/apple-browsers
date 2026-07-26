//
//  SubscriptionOnboardingListItemView.swift
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
import DesignResourcesKitIcons
import UIComponents

/// A single capsule-shaped row for the post-subscription onboarding flow: a leading status icon and a
/// label on a borderless, full-radius surface. The `status` picks the icon — an alert when the item is
/// still `inactive`, a check once it is `active` — so the same row renders both the "off" and "on" states
/// of a protection (e.g. a VPN feature row). Built from `SubscriptionOnboardingCard` + `CardItem`.
struct SubscriptionOnboardingListItemView: View {
    private enum Metrics {
        static let iconSpacing: CGFloat = 16
    }

    /// Whether the listed item is active yet; drives the leading icon.
    enum Status {
        case inactive
        case active
    }

    private let text: String
    private let status: Status

    init(text: String, status: Status) {
        self.text = text
        self.status = status
    }

    var body: some View {
        SubscriptionOnboardingCard(
            CardItem(
                icon: CardItemIcon(position: .leadingColumn, visual: .image(status.icon), size: .size24, spacing: Metrics.iconSpacing),
                title: CardItemText(text, font: .subheadRegular)),
            style: .borderless)
        .accessibilityElement(children: .combine)
    }
}

private extension SubscriptionOnboardingListItemView.Status {
    var icon: Image {
        switch self {
        case .inactive: Image(.onboardingAlertInactive24)
        case .active: Image(uiImage: DesignSystemImages.Color.Size24.check)
        }
    }
}

#if DEBUG

private struct SubscriptionOnboardingListItemViewPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SubscriptionOnboardingListItemView(text: "Shielding your online activity", status: .inactive)
                SubscriptionOnboardingListItemView(text: "Hiding your location & IP address", status: .inactive)
                SubscriptionOnboardingListItemView(text: "Blocking harmful sites", status: .inactive)

                SubscriptionOnboardingListItemView(text: "Shielding your online activity", status: .active)
                SubscriptionOnboardingListItemView(text: "Hiding your location & IP address", status: .active)
                SubscriptionOnboardingListItemView(text: "Blocking harmful sites", status: .active)
            }
            .padding()
        }
        .background(Color(designSystemColor: .surfaceTertiary).ignoresSafeArea())
    }
}

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingListItemViewPreview()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingListItemViewPreview()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingListItemViewPreview()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
