//
//  SubscriptionOnboardingVPNInfoView.swift
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

/// The VPN "Learn More" info sheet: a scrollable list of the VPN's features under a hero header, with a
/// close button that returns to the VPN activation screen. Reached from the "Learn More" link on the
/// activation screen and presented as a sheet.
struct SubscriptionOnboardingVPNInfoView: View {
    let onClose: () -> Void

    private enum Metrics {
        static let cardSpacing: CGFloat = 12
        static let cardInset: CGFloat = 16
        static let iconSpacing: CGFloat = 8
    }

    var body: some View {
        SubscriptionOnboardingView(
            navigationButton: .close(onClose),
            header: SubscriptionOnboardingHeaderView(
                visual: .image(Image(.onboardingVPN56)),
                title: UserText.subscriptionOnboardingVPNInfoTitle,
                explanation: UserText.subscriptionOnboardingVPNInfoExplanation)) {
            featureCards
        }
    }

    private var featureCards: some View {
        VStack(spacing: Metrics.cardSpacing) {
            ForEach(VPNInfoFeature.allCases, id: \.self) { feature in
                card(for: feature)
            }
        }
    }

    private func card(for feature: VPNInfoFeature) -> some View {
        SubscriptionOnboardingCard(
            CardItem(
                icon: CardItemIcon(position: .topLeading, visual: .image(feature.icon), size: .size24, spacing: Metrics.iconSpacing),
                title: CardItemText(feature.title, font: .headline),
                text: CardItemText(feature.body, font: .subheadRegular)),
            style: .borderless,
            contentInset: .init(horizontal: Metrics.cardInset, vertical: Metrics.cardInset))
        .accessibilityElement(children: .combine)
    }
}

/// The VPN features listed on the info sheet.
private enum VPNInfoFeature: CaseIterable {
    case devices
    case noLogging
    case easyToUse
    case fastAndReliable
    case dataLeakPrevention
    case secureDNS
    case alwaysOn
    case wireGuard

    var title: String {
        switch self {
        case .devices: UserText.subscriptionOnboardingVPNInfoDevicesTitle
        case .noLogging: UserText.subscriptionOnboardingVPNInfoNoLoggingTitle
        case .easyToUse: UserText.subscriptionOnboardingVPNInfoEasyToUseTitle
        case .fastAndReliable: UserText.subscriptionOnboardingVPNInfoFastReliableTitle
        case .dataLeakPrevention: UserText.subscriptionOnboardingVPNInfoDataLeakTitle
        case .secureDNS: UserText.subscriptionOnboardingVPNInfoSecureDNSTitle
        case .alwaysOn: UserText.subscriptionOnboardingVPNInfoAlwaysOnTitle
        case .wireGuard: UserText.subscriptionOnboardingVPNInfoWireGuardTitle
        }
    }

    var body: String {
        switch self {
        case .devices: UserText.subscriptionOnboardingVPNInfoDevicesBody
        case .noLogging: UserText.subscriptionOnboardingVPNInfoNoLoggingBody
        case .easyToUse: UserText.subscriptionOnboardingVPNInfoEasyToUseBody
        case .fastAndReliable: UserText.subscriptionOnboardingVPNInfoFastReliableBody
        case .dataLeakPrevention: UserText.subscriptionOnboardingVPNInfoDataLeakBody
        case .secureDNS: UserText.subscriptionOnboardingVPNInfoSecureDNSBody
        case .alwaysOn: UserText.subscriptionOnboardingVPNInfoAlwaysOnBody
        case .wireGuard: UserText.subscriptionOnboardingVPNInfoWireGuardBody
        }
    }

    // TODO: replace placeholder SF Symbols with the design-system glyphs from the spec.
    var icon: Image {
        switch self {
        case .devices: Image(systemName: "laptopcomputer.and.iphone")
        case .noLogging: Image(systemName: "hand.raised.fill")
        case .easyToUse: Image(systemName: "hand.tap.fill")
        case .fastAndReliable: Image(systemName: "globe")
        case .dataLeakPrevention: Image(systemName: "drop.triangle.fill")
        case .secureDNS: Image(systemName: "lock.shield.fill")
        case .alwaysOn: Image(systemName: "checkmark.circle")
        case .wireGuard: Image(systemName: "lock.fill")
        }
    }
}

#if DEBUG

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingVPNInfoView(onClose: {})
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingVPNInfoView(onClose: {})
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingVPNInfoView(onClose: {})
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
