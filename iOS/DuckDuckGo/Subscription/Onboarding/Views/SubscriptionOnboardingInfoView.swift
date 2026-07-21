//
//  SubscriptionOnboardingInfoView.swift
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

/// A generic "Learn More" info sheet for a subscription protection: a hero header above a scrollable list
/// of feature cards, with a close button that returns to the section that presented it. The content is
/// supplied per ``SubscriptionOnboardingChecklistItem`` by ``SubscriptionOnboardingViewFactory``, so the
/// same view renders the VPN, IDTR, Duck.ai … info screens.
struct SubscriptionOnboardingInfoView: View {
    let content: SubscriptionOnboardingInfoContent
    let onClose: () -> Void

    private enum Metrics {
        static let cardSpacing: CGFloat = 16
        static let explanationTopSpacing: CGFloat = 24
    }

    var body: some View {
        SubscriptionOnboardingBaseView(
            navigationButton: .close(onClose),
            header: SubscriptionOnboardingHeaderView(
                visual: content.visual,
                title: content.title,
                explanation: content.explanation,
                explanationTopSpacing: Metrics.explanationTopSpacing)) {
            featureCards
        }
    }

    private var featureCards: some View {
        VStack(spacing: Metrics.cardSpacing) {
            ForEach(content.features) { feature in
                if feature.showsPlatformGrid {
                    SubscriptionOnboardingShowcaseCard(icon: feature.icon, title: feature.title, text: feature.body) {
                        SubscriptionOnboardingPlatformGrid()
                    }
                } else {
                    SubscriptionOnboardingShowcaseCard(icon: feature.icon, title: feature.title, text: feature.body)
                }
            }
        }
    }
}

// MARK: - Content

/// The data backing a ``SubscriptionOnboardingInfoView``: the hero header plus the feature cards to list.
/// One value is built per ``SubscriptionOnboardingChecklistItem`` via ``content(for:)``.
struct SubscriptionOnboardingInfoContent {
    /// A single feature card on the info sheet.
    struct Feature: Identifiable {
        let id = UUID()
        let icon: Image
        let title: String
        let body: String
        /// Whether the card shows the platform grid in its footer — only the VPN "Devices" card does.
        var showsPlatformGrid = false
    }

    let visual: Graphic
    let title: String
    let explanation: String?
    let features: [Feature]
}

extension SubscriptionOnboardingInfoContent {
    /// The info-sheet content for a checklist item, or `nil` for protections whose info screen has not been
    /// built yet (IDTR, Duck.ai, PIR — Stage 3).
    static func content(for item: SubscriptionOnboardingChecklistItem) -> SubscriptionOnboardingInfoContent? {
        switch item {
        case .vpn: return .vpn
        case .duckAI: return .duckAI
        case .idtr, .pir: return nil
        }
    }

    /// The VPN "Learn More" content.
    static let vpn = SubscriptionOnboardingInfoContent(
        visual: .image(Image(.onboardingVPN128)),
        title: UserText.subscriptionOnboardingVPNInfoTitle,
        explanation: UserText.subscriptionOnboardingVPNInfoExplanation,
        features: VPNInfoFeature.allCases.map {
            Feature(icon: $0.icon, title: $0.title, body: $0.body, showsPlatformGrid: $0 == .devices)
        })

    /// The Duck.ai "Learn More" content.
    static let duckAI = SubscriptionOnboardingInfoContent(
        visual: .image(Image(.onboardingDuckAI128)),
        title: UserText.subscriptionOnboardingDuckAIInfoTitle,
        explanation: UserText.subscriptionOnboardingDuckAIInfoExplanation,
        features: DuckAIInfoFeature.allCases.map {
            Feature(icon: $0.icon, title: $0.title, body: $0.body)
        })
}

/// The VPN features listed on the VPN info sheet.
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

    var icon: Image {
        switch self {
        case .devices: Image(uiImage: DesignSystemImages.Glyphs.Size16.deviceAll)
        case .noLogging: Image(uiImage: DesignSystemImages.Glyphs.Size16.shield)
        case .easyToUse: Image(uiImage: DesignSystemImages.Glyphs.Size16.heart)
        case .fastAndReliable: Image(uiImage: DesignSystemImages.Glyphs.Size16.globe)
        case .dataLeakPrevention: Image(uiImage: DesignSystemImages.Glyphs.Size16.profileLock)
        case .secureDNS: Image(uiImage: DesignSystemImages.Glyphs.Size16.deviceLaptopLock)
        case .alwaysOn: Image(uiImage: DesignSystemImages.Glyphs.Size16.checkCircle)
        case .wireGuard: Image(uiImage: DesignSystemImages.Glyphs.Size16.lock)
        }
    }
}

/// The Duck.ai features listed on the Duck.ai info sheet.
private enum DuckAIInfoFeature: CaseIterable {
    case models
    case privacy
    case price
    case access

    var title: String {
        switch self {
        case .models: UserText.subscriptionOnboardingDuckAIInfoModelsTitle
        case .privacy: UserText.subscriptionOnboardingDuckAIInfoPrivacyTitle
        case .price: UserText.subscriptionOnboardingDuckAIInfoPriceTitle
        case .access: UserText.subscriptionOnboardingDuckAIInfoAccessTitle
        }
    }

    var body: String {
        switch self {
        case .models: UserText.subscriptionOnboardingDuckAIInfoModelsBody
        case .privacy: UserText.subscriptionOnboardingDuckAIInfoPrivacyBody
        case .price: UserText.subscriptionOnboardingDuckAIInfoPriceBody
        case .access: UserText.subscriptionOnboardingDuckAIInfoAccessBody
        }
    }

    var icon: Image {
        switch self {
        case .models: Image(uiImage: DesignSystemImages.Glyphs.Size16.aiGeneral)
        case .privacy: Image(uiImage: DesignSystemImages.Glyphs.Size16.shield)
        case .price: Image(uiImage: DesignSystemImages.Glyphs.Size16.priceTag)
        case .access: Image(uiImage: DesignSystemImages.Glyphs.Size16.globe)
        }
    }
}

// MARK: - Platform grid

/// The 2-column platform grid shown in the footer of the VPN info sheet's "Devices" card: one `CardItem`
/// per platform (a leading platform glyph and its name).
struct SubscriptionOnboardingPlatformGrid: View {
    private enum Metrics {
        static let columnSpacing: CGFloat = 4
        static let rowSpacing: CGFloat = 12
        static let iconSpacing: CGFloat = 6
        static let topPadding: CGFloat = 8
        static let firstColumnMaxWidth: CGFloat = 80
        static let secondColumnMaxWidth: CGFloat = 121
    }

    private let columns = [
        GridItem(.flexible(maximum: Metrics.firstColumnMaxWidth), spacing: Metrics.columnSpacing, alignment: .leading),
        GridItem(.flexible(maximum: Metrics.secondColumnMaxWidth), spacing: Metrics.columnSpacing, alignment: .leading)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.rowSpacing) {
            ForEach(Platform.allCases, id: \.self) { platform in
                CardItem(
                    icon: CardItemIcon(position: .leadingColumn, visual: .image(platform.icon), size: .size24, spacing: Metrics.iconSpacing),
                    title: CardItemText(platform.name, font: .subheadRegular))
            }
        }
        .padding(.top, Metrics.topPadding)
    }

    /// The four platforms shown in the Devices card, each with its design-system glyph and display name.
    private enum Platform: CaseIterable {
        case iOS
        case android
        case mac
        case windows

        var icon: Image {
            switch self {
            case .iOS: Image(uiImage: DesignSystemImages.Glyphs.Size24.platformApple)
            case .android: Image(uiImage: DesignSystemImages.Glyphs.Size24.platformAndroid)
            case .mac: Image(uiImage: DesignSystemImages.Glyphs.Size24.platformMacOS)
            case .windows: Image(uiImage: DesignSystemImages.Glyphs.Size24.platformWindows)
            }
        }

        var name: String {
            switch self {
            case .iOS: UserText.subscriptionOnboardingPlatformIOS
            case .android: UserText.subscriptionOnboardingPlatformAndroid
            case .mac: UserText.subscriptionOnboardingPlatformMac
            case .windows: UserText.subscriptionOnboardingPlatformWindows
            }
        }
    }
}

#if DEBUG

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingInfoView(content: .vpn, onClose: {})
            .subscriptionOnboardingNavigationContainer()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingInfoView(content: .vpn, onClose: {})
            .subscriptionOnboardingNavigationContainer()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingInfoView(content: .vpn, onClose: {})
            .subscriptionOnboardingNavigationContainer()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
