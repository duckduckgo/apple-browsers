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
/// of feature cards, with a close button that returns to the screen that presented it. The presenting
/// screen supplies the matching ``SubscriptionOnboardingInfoContent`` (`.vpn`, `.idtr`, `.duckAI`, `.pir`),
/// so the same view renders the VPN, IDTR, Duck.ai … info screens.
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
                if let platforms = feature.platforms {
                    SubscriptionOnboardingShowcaseCard(icon: feature.icon, title: feature.title, text: feature.body) {
                        SubscriptionOnboardingPlatformGrid(platforms: platforms)
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
        /// The platforms to show in the card's footer grid, or `nil` for no grid. Only the VPN "Devices"
        /// card and the PIR "Platforms" card show one; PIR passes a Mac/Windows-only subset.
        var platforms: [SubscriptionOnboardingPlatformGrid.Platform]?
    }

    let visual: Graphic
    let title: String
    let explanation: String?
    let features: [Feature]
}

extension SubscriptionOnboardingInfoContent {
    /// The info-sheet content for a checklist item.
    static func content(for item: SubscriptionOnboardingChecklistItem) -> SubscriptionOnboardingInfoContent? {
        switch item {
        case .vpn: return .vpn
        case .idtr: return .idtr
        case .duckAI: return .duckAI
        case .pir: return .pir
        }
    }

    /// The VPN "Learn More" content.
    static let vpn = SubscriptionOnboardingInfoContent(
        visual: .image(Image(.onboardingVPN128)),
        title: UserText.subscriptionOnboardingVPNInfoTitle,
        explanation: UserText.subscriptionOnboardingVPNInfoExplanation,
        features: VPNInfoFeature.allCases.map {
            Feature(icon: $0.icon, title: $0.title, body: $0.body,
                    platforms: $0 == .devices ? SubscriptionOnboardingPlatformGrid.Platform.allCases : nil)
        })

    /// The IDTR "Learn More" content.
    static let idtr = SubscriptionOnboardingInfoContent(
        visual: .image(Image(.onboardingIDTR128)),
        title: UserText.subscriptionOnboardingIDTRInfoTitle,
        explanation: UserText.subscriptionOnboardingIDTRInfoExplanation,
        features: IDTRInfoFeature.allCases.map {
            Feature(icon: $0.icon, title: $0.title, body: $0.body)
        })

    /// The Duck.ai "Learn More" content.
    static let duckAI = SubscriptionOnboardingInfoContent(
        visual: .image(Image(.onboardingDuckAI128)),
        title: UserText.subscriptionOnboardingDuckAIInfoTitle,
        explanation: UserText.subscriptionOnboardingDuckAIInfoExplanation,
        features: DuckAIInfoFeature.allCases.map {
            Feature(icon: $0.icon, title: $0.title, body: $0.body)
        })

    /// The PIR "Learn More" content.
    static let pir = SubscriptionOnboardingInfoContent(
        visual: .image(Image(.personalInformationRemover128)),
        title: UserText.subscriptionOnboardingPIRInfoTitle,
        explanation: UserText.subscriptionOnboardingPIRInfoExplanation,
        features: PIRInfoFeature.allCases.map {
            Feature(icon: $0.icon, title: $0.title, body: $0.body,
                    platforms: $0 == .platforms ? [.mac, .windows] : nil)
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

/// The IDTR features listed on the IDTR info sheet.
private enum IDTRInfoFeature: CaseIterable {
    case financialLosses
    case creditReport
    case walletItems
    case caseManager
    case rapidResponse
    case emergencyCash
    case authorities
    case medical

    var title: String {
        switch self {
        case .financialLosses: UserText.subscriptionOnboardingIDTRInfoFinancialLossesTitle
        case .creditReport: UserText.subscriptionOnboardingIDTRInfoCreditReportTitle
        case .walletItems: UserText.subscriptionOnboardingIDTRInfoWalletTitle
        case .caseManager: UserText.subscriptionOnboardingIDTRInfoCaseManagerTitle
        case .rapidResponse: UserText.subscriptionOnboardingIDTRInfoRapidResponseTitle
        case .emergencyCash: UserText.subscriptionOnboardingIDTRInfoEmergencyCashTitle
        case .authorities: UserText.subscriptionOnboardingIDTRInfoAuthoritiesTitle
        case .medical: UserText.subscriptionOnboardingIDTRInfoMedicalTitle
        }
    }

    var body: String {
        switch self {
        case .financialLosses: UserText.subscriptionOnboardingIDTRInfoFinancialLossesBody
        case .creditReport: UserText.subscriptionOnboardingIDTRInfoCreditReportBody
        case .walletItems: UserText.subscriptionOnboardingIDTRInfoWalletBody
        case .caseManager: UserText.subscriptionOnboardingIDTRInfoCaseManagerBody
        case .rapidResponse: UserText.subscriptionOnboardingIDTRInfoRapidResponseBody
        case .emergencyCash: UserText.subscriptionOnboardingIDTRInfoEmergencyCashBody
        case .authorities: UserText.subscriptionOnboardingIDTRInfoAuthoritiesBody
        case .medical: UserText.subscriptionOnboardingIDTRInfoMedicalBody
        }
    }

    /// `walletItems` has no matching design-system glyph — a placeholder, flagged for a real icon.
    var icon: Image {
        switch self {
        case .financialLosses: Image(uiImage: DesignSystemImages.Glyphs.Size16.currency)
        case .creditReport: Image(uiImage: DesignSystemImages.Glyphs.Size16.profileLock)
        case .walletItems: Image(uiImage: DesignSystemImages.Glyphs.Size16.card)
        case .caseManager: Image(uiImage: DesignSystemImages.Glyphs.Size16.support)
        case .rapidResponse: Image(uiImage: DesignSystemImages.Glyphs.Size16.clock)
        case .emergencyCash: Image(uiImage: DesignSystemImages.Glyphs.Size16.creditCard)
        case .authorities: Image(uiImage: DesignSystemImages.Glyphs.Size16.announce)
        case .medical: Image(uiImage: DesignSystemImages.Glyphs.Size16.profile)
        }
    }
}

/// The PIR features listed on the PIR info sheet.
private enum PIRInfoFeature: CaseIterable {
    case platforms
    case repeatedScans
    case onDevice
    case automated
    case monitorProgress

    var title: String {
        switch self {
        case .platforms: UserText.subscriptionOnboardingPIRInfoPlatformsTitle
        case .repeatedScans: UserText.subscriptionOnboardingPIRInfoScansTitle
        case .onDevice: UserText.subscriptionOnboardingPIRInfoOnDeviceTitle
        case .automated: UserText.subscriptionOnboardingPIRInfoAutomatedTitle
        case .monitorProgress: UserText.subscriptionOnboardingPIRInfoMonitorTitle
        }
    }

    var body: String {
        switch self {
        case .platforms: UserText.subscriptionOnboardingPIRInfoPlatformsBody
        case .repeatedScans: UserText.subscriptionOnboardingPIRInfoScansBody
        case .onDevice: UserText.subscriptionOnboardingPIRInfoOnDeviceBody
        case .automated: UserText.subscriptionOnboardingPIRInfoAutomatedBody
        case .monitorProgress: UserText.subscriptionOnboardingPIRInfoMonitorBody
        }
    }

    var icon: Image {
        switch self {
        case .platforms: Image(uiImage: DesignSystemImages.Glyphs.Size16.deviceAll)
        case .repeatedScans: Image(uiImage: DesignSystemImages.Glyphs.Size16.reload)
        case .onDevice: Image(uiImage: DesignSystemImages.Glyphs.Size16.deviceLaptopLock)
        case .automated: Image(uiImage: DesignSystemImages.Glyphs.Size16.formAutofill)
        case .monitorProgress: Image(uiImage: DesignSystemImages.Glyphs.Size16.support)
        }
    }
}

// MARK: - Platform grid

/// The 2-column platform grid shown in the footer of a "Platforms"/"Devices" info-sheet card (VPN, PIR):
/// one `CardItem` per platform (a leading platform glyph and its name).
struct SubscriptionOnboardingPlatformGrid: View {
    private enum Metrics {
        static let columnSpacing: CGFloat = 4
        static let rowSpacing: CGFloat = 12
        static let iconSpacing: CGFloat = 6
        static let topPadding: CGFloat = 8
        static let firstColumnMaxWidth: CGFloat = 80
        static let secondColumnMaxWidth: CGFloat = 121
    }

    private let platforms: [Platform]

    private let columns = [
        GridItem(.flexible(maximum: Metrics.firstColumnMaxWidth), spacing: Metrics.columnSpacing, alignment: .leading),
        GridItem(.flexible(maximum: Metrics.secondColumnMaxWidth), spacing: Metrics.columnSpacing, alignment: .leading)
    ]

    /// Defaults to all four platforms (the VPN "Devices" card); PIR is Mac/Windows-only and passes a subset.
    init(platforms: [Platform] = Platform.allCases) {
        self.platforms = platforms
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.rowSpacing) {
            ForEach(platforms, id: \.self) { platform in
                CardItem(
                    icon: CardItemIcon(position: .leadingColumn, visual: .image(platform.icon), size: .size24, spacing: Metrics.iconSpacing),
                    title: CardItemText(platform.name, font: .subheadRegular))
            }
        }
        .padding(.top, Metrics.topPadding)
    }

    /// The platforms selectable for a card's grid — VPN's "Devices" card shows all four; PIR's "Platforms"
    /// card shows only Mac and Windows.
    enum Platform: CaseIterable {
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

#Preview("IDTR") {
    RebrandedPreview {
        SubscriptionOnboardingInfoView(content: .idtr, onClose: {})
            .subscriptionOnboardingNavigationContainer()
    }
}

#Preview("PIR") {
    RebrandedPreview {
        SubscriptionOnboardingInfoView(content: .pir, onClose: {})
            .subscriptionOnboardingNavigationContainer()
    }
}

#endif
