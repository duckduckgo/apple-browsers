//
//  SubscriptionOnboardingVPNInfoCard.swift
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

/// An IP-address info card for the post-subscription onboarding VPN step: a leading icon beside a labelled
/// IP address and its geolocation. The `state` selects the overline label and icon — the grayscale VPN icon
/// for the customer's real IP (`visibleIP` / `hiddenIP`) and the colour VPN icon for the new egress IP
/// (`newIP`) — while `ipAddress` and `location` carry the runtime values. Built from
/// `SubscriptionOnboardingCard` + a single `CardItem`.
struct SubscriptionOnboardingVPNInfoCard: View {

    /// Which IP the card describes; drives the overline label and the leading icon.
    enum IPState {
        case visibleIP
        case hiddenIP
        case newIP
    }

    private let state: IPState
    private let ipAddress: String
    private let location: String

    @State private var blurRadius: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let hiddenBlurRadius: CGFloat = 8

    init(state: IPState, ipAddress: String, location: String) {
        self.state = state
        self.ipAddress = ipAddress
        self.location = location
    }

    var body: some View {
        card
            .accessibilityElement(children: .combine)
            .onAppear {
                guard state.hidesValues, blurRadius == 0 else { return }
                if reduceMotion {
                    blurRadius = Self.hiddenBlurRadius
                } else {
                    withAnimation(.easeInOut(duration: 0.4)) { blurRadius = Self.hiddenBlurRadius }
                }
            }
    }

    private var card: some View {
        SubscriptionOnboardingCard(
            CardItem(
                icon: CardItemIcon(position: .leading, visual: .image(state.icon), size: .size24, spacing: 8),
                overline: CardItemText(state.overline, font: .footnoteRegular),
                title: CardItemText(ipAddress, font: .bodyRegular, modifier: blurModifier),
                text: CardItemText(location, font: .footnoteRegular, color: Color(designSystemColor: .textPrimary), modifier: blurModifier)),
            style: .borderless,
            contentInset: CardItemList.ContentInset(horizontal: 16, vertical: 14))
    }

    private var blurModifier: AnyViewModifier? {
        state.hidesValues ? AnyViewModifier(BlurEffect(radius: blurRadius)) : nil
    }
}

private extension SubscriptionOnboardingVPNInfoCard.IPState {
    var hidesValues: Bool {
        if case .hiddenIP = self { return true }
        return false
    }

    var overline: String {
        switch self {
        case .visibleIP: UserText.subscriptionOnboardingVPNInfoVisibleIP
        case .hiddenIP: UserText.subscriptionOnboardingVPNInfoHiddenIP
        case .newIP: UserText.subscriptionOnboardingVPNInfoNewIP
        }
    }

    var icon: Image {
        switch self {
        case .visibleIP, .hiddenIP: Image(.onboardingVPNLocation24)
        case .newIP: Image(.onboardingVPNLocationColored24)
        }
    }
}

private struct BlurEffect: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .accessibilityHidden(true)
    }
}

#if DEBUG

private struct SubscriptionOnboardingVPNInfoCardPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SubscriptionOnboardingVPNInfoCard(state: .visibleIP, ipAddress: "31.120.130.50", location: "🇪🇸 Madrid, Spain")
                SubscriptionOnboardingVPNInfoCard(state: .hiddenIP, ipAddress: "31.120.130.50", location: "🇪🇸 Madrid, Spain")
                SubscriptionOnboardingVPNInfoCard(state: .newIP, ipAddress: "45.623.728.96", location: "🇪🇸 Valencia, Spain (Nearest)")
            }
            .padding()
        }
        .background(Color(designSystemColor: .surfaceTertiary).ignoresSafeArea())
    }
}

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingVPNInfoCardPreview()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingVPNInfoCardPreview()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingVPNInfoCardPreview()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
