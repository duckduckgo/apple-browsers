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
        static let disclaimerTopSpacing: CGFloat = 24
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
        VStack(spacing: Metrics.disclaimerTopSpacing) {
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

            if let disclaimer = content.disclaimer {
                disclaimerView(disclaimer)
            }
        }
    }

    /// The disclaimer renders Markdown, so its `[label](url)` becomes a tappable link that opens in the
    /// system URL handler (e.g. the Summary of Benefits PDF).
    private func disclaimerView(_ disclaimer: String) -> some View {
        Text(LocalizedStringKey(disclaimer))
            .daxFootnoteRegular()
            .multilineTextAlignment(.leading)
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .tintIfAvailable(Color(designSystemColor: .textSecondary))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Presentation

extension View {
    /// Presents a fixed protection's "Learn More" info sheet — a ``SubscriptionOnboardingInfoView`` wrapped in
    /// the shared navigation container — bound to `isPresented`. Used by the VPN and Duck.ai screens.
    func subscriptionOnboardingInfoSheet(_ content: SubscriptionOnboardingInfoContent,
                                         isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) {
            SubscriptionOnboardingInfoView(content: content, onClose: { isPresented.wrappedValue = false })
                .subscriptionOnboardingNavigationContainer()
        }
    }

    /// Presents the "Learn More" info sheet for whichever checklist `item` is selected (`nil` = dismissed).
    /// Used by the welcome list, where the presented protection varies with the tapped row.
    func subscriptionOnboardingInfoSheet(item: Binding<SubscriptionOnboardingChecklistItem?>) -> some View {
        sheet(item: item) { selected in
            SubscriptionOnboardingInfoView(content: .content(for: selected), onClose: { item.wrappedValue = nil })
                .subscriptionOnboardingNavigationContainer()
        }
    }
}

// MARK: - Content

/// The data backing a ``SubscriptionOnboardingInfoView``: the hero header plus the feature cards to list.
/// One value is built per ``SubscriptionOnboardingChecklistItem`` via ``content(for:)``.
struct SubscriptionOnboardingInfoContent {
    /// A single feature card on the info sheet.
    struct Feature: Identifiable {
        var id: String { title }
        let icon: Image
        let title: String
        let body: String
        var platforms: [SubscriptionOnboardingPlatformGrid.Platform]?
    }

    let visual: Graphic
    let title: String
    let explanation: String?
    let features: [Feature]
    var disclaimer: String?
}

extension SubscriptionOnboardingInfoContent {
    /// The info-sheet content for a checklist item. Total over the fixed set of items, so it's non-optional.
    static func content(for item: SubscriptionOnboardingChecklistItem) -> SubscriptionOnboardingInfoContent {
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
        features: VPNInfoFeature.allCases.map(\.feature))

    /// The IDTR "Learn More" content.
    static let idtr = SubscriptionOnboardingInfoContent(
        visual: .image(Image(.onboardingIDTR128)),
        title: UserText.subscriptionOnboardingIDTRInfoTitle,
        explanation: UserText.subscriptionOnboardingIDTRInfoExplanation,
        features: IDTRInfoFeature.allCases.map(\.feature),
        disclaimer: UserText.subscriptionOnboardingIDTRInfoDisclaimer)

    /// The Duck.ai "Learn More" content.
    static let duckAI = SubscriptionOnboardingInfoContent(
        visual: .image(Image(.onboardingDuckAI128)),
        title: UserText.subscriptionOnboardingDuckAIInfoTitle,
        explanation: UserText.subscriptionOnboardingDuckAIInfoExplanation,
        features: DuckAIInfoFeature.allCases.map(\.feature))

    /// The PIR "Learn More" content.
    static let pir = SubscriptionOnboardingInfoContent(
        visual: .image(Image(.personalInformationRemover128)),
        title: UserText.subscriptionOnboardingPIRInfoTitle,
        explanation: UserText.subscriptionOnboardingPIRInfoExplanation,
        features: PIRInfoFeature.allCases.map(\.feature))
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

    var feature: SubscriptionOnboardingInfoContent.Feature {
        switch self {
        case .devices:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.deviceAll),
                  title: UserText.subscriptionOnboardingVPNInfoDevicesTitle,
                  body: UserText.subscriptionOnboardingVPNInfoDevicesBody,
                  platforms: SubscriptionOnboardingPlatformGrid.Platform.allCases)
        case .noLogging:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.shield),
                  title: UserText.subscriptionOnboardingVPNInfoNoLoggingTitle,
                  body: UserText.subscriptionOnboardingVPNInfoNoLoggingBody)
        case .easyToUse:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.heart),
                  title: UserText.subscriptionOnboardingVPNInfoEasyToUseTitle,
                  body: UserText.subscriptionOnboardingVPNInfoEasyToUseBody)
        case .fastAndReliable:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.globe),
                  title: UserText.subscriptionOnboardingVPNInfoFastReliableTitle,
                  body: UserText.subscriptionOnboardingVPNInfoFastReliableBody)
        case .dataLeakPrevention:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.profileLock),
                  title: UserText.subscriptionOnboardingVPNInfoDataLeakTitle,
                  body: UserText.subscriptionOnboardingVPNInfoDataLeakBody)
        case .secureDNS:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.deviceLaptopLock),
                  title: UserText.subscriptionOnboardingVPNInfoSecureDNSTitle,
                  body: UserText.subscriptionOnboardingVPNInfoSecureDNSBody)
        case .alwaysOn:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.checkCircle),
                  title: UserText.subscriptionOnboardingVPNInfoAlwaysOnTitle,
                  body: UserText.subscriptionOnboardingVPNInfoAlwaysOnBody)
        case .wireGuard:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.lock),
                  title: UserText.subscriptionOnboardingVPNInfoWireGuardTitle,
                  body: UserText.subscriptionOnboardingVPNInfoWireGuardBody)
        }
    }
}

/// The Duck.ai features listed on the Duck.ai info sheet.
private enum DuckAIInfoFeature: CaseIterable {
    case models
    case privacy
    case price
    case access

    var feature: SubscriptionOnboardingInfoContent.Feature {
        switch self {
        case .models:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.aiGeneral),
                  title: UserText.subscriptionOnboardingDuckAIInfoModelsTitle,
                  body: UserText.subscriptionOnboardingDuckAIInfoModelsBody)
        case .privacy:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.shield),
                  title: UserText.subscriptionOnboardingDuckAIInfoPrivacyTitle,
                  body: UserText.subscriptionOnboardingDuckAIInfoPrivacyBody)
        case .price:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.priceTag),
                  title: UserText.subscriptionOnboardingDuckAIInfoPriceTitle,
                  body: UserText.subscriptionOnboardingDuckAIInfoPriceBody)
        case .access:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.globe),
                  title: UserText.subscriptionOnboardingDuckAIInfoAccessTitle,
                  body: UserText.subscriptionOnboardingDuckAIInfoAccessBody)
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

    /// `walletItems` has no matching design-system glyph — a placeholder, flagged for a real icon.
    var feature: SubscriptionOnboardingInfoContent.Feature {
        switch self {
        case .financialLosses:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.currency),
                  title: UserText.subscriptionOnboardingIDTRInfoFinancialLossesTitle,
                  body: UserText.subscriptionOnboardingIDTRInfoFinancialLossesBody)
        case .creditReport:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.profileLock),
                  title: UserText.subscriptionOnboardingIDTRInfoCreditReportTitle,
                  body: UserText.subscriptionOnboardingIDTRInfoCreditReportBody)
        case .walletItems:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.card),
                  title: UserText.subscriptionOnboardingIDTRInfoWalletTitle,
                  body: UserText.subscriptionOnboardingIDTRInfoWalletBody)
        case .caseManager:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.support),
                  title: UserText.subscriptionOnboardingIDTRInfoCaseManagerTitle,
                  body: UserText.subscriptionOnboardingIDTRInfoCaseManagerBody)
        case .rapidResponse:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.clock),
                  title: UserText.subscriptionOnboardingIDTRInfoRapidResponseTitle,
                  body: UserText.subscriptionOnboardingIDTRInfoRapidResponseBody)
        case .emergencyCash:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.creditCard),
                  title: UserText.subscriptionOnboardingIDTRInfoEmergencyCashTitle,
                  body: UserText.subscriptionOnboardingIDTRInfoEmergencyCashBody)
        case .authorities:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.announce),
                  title: UserText.subscriptionOnboardingIDTRInfoAuthoritiesTitle,
                  body: UserText.subscriptionOnboardingIDTRInfoAuthoritiesBody)
        case .medical:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.profile),
                  title: UserText.subscriptionOnboardingIDTRInfoMedicalTitle,
                  body: UserText.subscriptionOnboardingIDTRInfoMedicalBody)
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

    var feature: SubscriptionOnboardingInfoContent.Feature {
        switch self {
        case .platforms:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.deviceAll),
                  title: UserText.subscriptionOnboardingPIRInfoPlatformsTitle,
                  body: UserText.subscriptionOnboardingPIRInfoPlatformsBody,
                  platforms: [.mac, .windows])
        case .repeatedScans:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.reload),
                  title: UserText.subscriptionOnboardingPIRInfoScansTitle,
                  body: UserText.subscriptionOnboardingPIRInfoScansBody)
        case .onDevice:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.deviceLaptopLock),
                  title: UserText.subscriptionOnboardingPIRInfoOnDeviceTitle,
                  body: UserText.subscriptionOnboardingPIRInfoOnDeviceBody)
        case .automated:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.formAutofill),
                  title: UserText.subscriptionOnboardingPIRInfoAutomatedTitle,
                  body: UserText.subscriptionOnboardingPIRInfoAutomatedBody)
        case .monitorProgress:
            .init(icon: Image(uiImage: DesignSystemImages.Glyphs.Size16.support),
                  title: UserText.subscriptionOnboardingPIRInfoMonitorTitle,
                  body: UserText.subscriptionOnboardingPIRInfoMonitorBody)
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
