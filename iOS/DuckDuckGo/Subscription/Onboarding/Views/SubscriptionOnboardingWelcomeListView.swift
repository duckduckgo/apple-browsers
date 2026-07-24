//
//  SubscriptionOnboardingWelcomeListView.swift
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

/// The feature list on the post-subscription onboarding welcome screen: a single card listing the
/// premium protections — VPN, Identity Theft Restoration, Advanced AI Models and Personal Information
/// Removal — one selectable row each, with a trailing chevron affordance. `onSelect` receives the tapped
/// feature; the caller maps it to the matching "Learn More" info sheet.
struct SubscriptionOnboardingWelcomeListView: View {
    private enum Metrics {
        static let iconTextSpacing: CGFloat = 8
        static let contentInsetHorizontal: CGFloat = 16
        static let contentInsetVertical: CGFloat = 14
    }

    private let features = SubscriptionOnboardingChecklistItem.allCases
    private let onSelect: (SubscriptionOnboardingChecklistItem) -> Void

    init(onSelect: @escaping (SubscriptionOnboardingChecklistItem) -> Void) {
        self.onSelect = onSelect
    }

    var body: some View {
        SubscriptionOnboardingCard(
            features.map { Self.row(for: $0) },
            style: .borderless,
            padding: 0,
            contentInset: .init(horizontal: Metrics.contentInsetHorizontal, vertical: Metrics.contentInsetVertical),
            onSelect: CardItemList.selectAction(over: features) { onSelect($0) })
    }
}

private extension SubscriptionOnboardingWelcomeListView {
    static func row(for feature: SubscriptionOnboardingChecklistItem) -> CardItem {
        CardItem(
            icon: CardItemIcon(position: .leading, visual: visual(for: feature), spacing: Metrics.iconTextSpacing),
            title: CardItemText(title(for: feature), font: .bodyRegular),
            text: CardItemText(bodyText(for: feature), font: .footnoteRegular),
            trailing: .chevron(Color(designSystemColor: .iconsTertiary)))
    }

    static func visual(for feature: SubscriptionOnboardingChecklistItem) -> Graphic {
        switch feature {
        case .vpn: colorIcon(DesignSystemImages.Color.Size24.vpn)
        case .idtr: colorIcon(DesignSystemImages.Color.Size24.identityTheftRestoration)
        case .duckAI: colorIcon(DesignSystemImages.Color.Size24.aiGeneral)
        case .pir: .image(Image(.onboardingPIRBlocked24))
        }
    }

    static func colorIcon(_ uiImage: UIImage) -> Graphic {
        .image(Image(uiImage: uiImage))
    }

    static func title(for feature: SubscriptionOnboardingChecklistItem) -> String {
        switch feature {
        case .vpn: UserText.subscriptionOnboardingWelcomeVPNTitle
        case .idtr: UserText.subscriptionOnboardingWelcomeIDTRTitle
        case .duckAI: UserText.subscriptionOnboardingWelcomeDuckAITitle
        case .pir: UserText.subscriptionOnboardingWelcomePIRTitle
        }
    }

    static func bodyText(for feature: SubscriptionOnboardingChecklistItem) -> String {
        switch feature {
        case .vpn: UserText.subscriptionOnboardingWelcomeVPNBody
        case .idtr: UserText.subscriptionOnboardingWelcomeIDTRBody
        case .duckAI: UserText.subscriptionOnboardingWelcomeDuckAIBody
        case .pir: UserText.subscriptionOnboardingWelcomePIRBody
        }
    }
}

#if DEBUG

private struct SubscriptionOnboardingWelcomeListViewPreview: View {
    var body: some View {
        ScrollView {
            SubscriptionOnboardingWelcomeListView(onSelect: { _ in })
                .padding()
        }
        .background(Color(designSystemColor: .surfaceTertiary).ignoresSafeArea())
    }
}

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingWelcomeListViewPreview()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingWelcomeListViewPreview()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingWelcomeListViewPreview()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
