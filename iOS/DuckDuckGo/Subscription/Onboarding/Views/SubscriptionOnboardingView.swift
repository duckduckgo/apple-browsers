//
//  SubscriptionOnboardingView.swift
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
import DuckUI

private enum Metrics {
    static let horizontalPadding: CGFloat = 24
    static let topBarHorizontalPadding: CGFloat = 16
    static let navigationButtonSize: CGFloat = 44
    static let navigationGlyphSize: CGFloat = navigationButtonSize - CloseButtonStyle.Constant.padding * 2
    static let navigationButtonBottomSpacing: CGFloat = 10
    /// The button is centered, so this spacing sits above and below it
    static let topBarHeight: CGFloat = navigationButtonSize + navigationButtonBottomSpacing * 2
    static let contentVerticalPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    static let footerSpacing: CGFloat = 8
}

/// The top bar's leading button: either a back button or a close button. Both render as a circular
/// shaded button and carry their own glyph and VoiceOver label.
enum SubscriptionOnboardingNavigationButton {
    case back(() -> Void)
    case close(() -> Void)

    var action: () -> Void {
        switch self {
        case .back(let action), .close(let action):
            return action
        }
    }

    var glyph: UIImage {
        switch self {
        case .back:
            return DesignSystemImages.Glyphs.Size24.chevronLeft
        case .close:
            return DesignSystemImages.Glyphs.Size24.close
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .back:
            return UserText.subscriptionOnboardingBackButtonAccessibilityLabel
        case .close:
            return UserText.subscriptionOnboardingCloseButtonAccessibilityLabel
        }
    }
}

/// A footer button: a title and a tap action.
struct SubscriptionOnboardingFooterButton {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
}

/// The page's bottom-pinned footer: a single primary button, or a primary button above a secondary one.
/// Pass `nil` (the default) for no footer.
enum SubscriptionOnboardingFooter {
    case single(SubscriptionOnboardingFooterButton)
    case double(primary: SubscriptionOnboardingFooterButton, secondary: SubscriptionOnboardingFooterButton)
}

/// A generic, high-level page for the post-subscription onboarding flow: a top bar (an optional leading
/// back/close button and an optional centered title), an optional ``SubscriptionOnboardingHeaderView``,
/// a caller-supplied body, and an optional bottom-pinned footer of one or two buttons. The flow presents
/// it in a `.fullScreenCover`; each concrete section (VPN, Duck.ai, …) supplies its own title, header,
/// body and footer.
struct SubscriptionOnboardingView<Content: View>: View {

    private let title: String?
    private let navigationButton: SubscriptionOnboardingNavigationButton?
    private let header: SubscriptionOnboardingHeaderView?
    private let footer: SubscriptionOnboardingFooter?
    private let content: Content

    init(title: String? = nil,
         navigationButton: SubscriptionOnboardingNavigationButton? = nil,
         header: SubscriptionOnboardingHeaderView? = nil,
         footer: SubscriptionOnboardingFooter? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.navigationButton = navigationButton
        self.header = header
        self.footer = footer
        self.content = content()
    }

    private var pageBackgroundColor: Color {
        Color(designSystemColor: .surfaceTertiary)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(spacing: Metrics.sectionSpacing) {
                    header
                    content
                }
                .padding(.vertical, Metrics.contentVerticalPadding)
                .padding(.horizontal, Metrics.horizontalPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pageBackgroundColor.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { footerView }
    }
}

// MARK: - Top bar

private extension SubscriptionOnboardingView {
    var topBar: some View {
        ZStack {
            if let title {
                Text(title)
                    .daxSubheadSemibold()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
            HStack {
                if let navigationButton {
                    Button(action: navigationButton.action) {
                        Image(uiImage: navigationButton.glyph)
                            .frame(width: Metrics.navigationGlyphSize, height: Metrics.navigationGlyphSize)
                    }
                    .buttonStyle(CloseButtonStyle())
                    .padding(-CloseButtonStyle.Constant.padding)
                    .accessibilityLabel(navigationButton.accessibilityLabel)
                }
                Spacer()
            }
        }
        .frame(height: Metrics.topBarHeight)
        .padding(.horizontal, Metrics.topBarHorizontalPadding)
    }
}

// MARK: - Footer

private extension SubscriptionOnboardingView {
    @ViewBuilder
    var footerView: some View {
        if let footer {
            switch footer {
            case .single(let button):
                footerContainer {
                    primaryButton(button)
                }
            case .double(let primary, let secondary):
                footerContainer {
                    VStack(spacing: Metrics.footerSpacing) {
                        primaryButton(primary)
                        secondaryButton(secondary)
                    }
                }
            }
        }
    }

    func footerContainer<Buttons: View>(@ViewBuilder _ buttons: () -> Buttons) -> some View {
        buttons()
            .padding(.top, Metrics.footerSpacing)
            .padding(.horizontal, Metrics.horizontalPadding)
    }

    func primaryButton(_ button: SubscriptionOnboardingFooterButton) -> some View {
        Button(button.title, action: button.action)
            .buttonStyle(PrimaryButtonStyle())
    }

    /// Backs the design system's translucent secondary fill with an opaque page-color capsule so content
    /// scrolling behind the floating footer doesn't show through the button.
    func secondaryButton(_ button: SubscriptionOnboardingFooterButton) -> some View {
        Button(button.title, action: button.action)
            .buttonStyle(SecondaryFillButtonStyle())
            .background(pageBackgroundColor)
            .clipShape(Capsule())
    }
}

#if DEBUG

private func onboardingPreviewHeader() -> SubscriptionOnboardingHeaderView {
    SubscriptionOnboardingHeaderView(
        visual: .image(Image(systemName: "checkmark.shield.fill")),
        title: "Turn on the VPN",
        explanation: "Secure your connection any time you're online.")
}

private func onboardingPreviewBody() -> some View {
    VStack(spacing: 12) {
        SubscriptionOnboardingListItemView(text: "Shielding your online activity", status: .inactive)
        SubscriptionOnboardingListItemView(text: "Hiding your location & IP address", status: .inactive)
        SubscriptionOnboardingListItemView(text: "Blocking harmful sites", status: .inactive)
    }
}

private func onboardingPreviewLongBody() -> some View {
    VStack(spacing: 16) {
        SubscriptionOnboardingShowcaseCard(
            visual: .image(Image(systemName: "bolt.shield.fill")),
            title: "No data or speed caps",
            text: "Stream, download, and game with as much data as you want. We only throttle connections to prevent abuse or network errors.")
        SubscriptionOnboardingShowcaseCard(
            visual: .image(Image(systemName: "network")),
            title: "All VPNs affect internet speeds",
            text: "Routing traffic through a VPN can cause speed differences. DuckDuckGo VPN is designed to keep them imperceptible for most browsing.")
        SubscriptionOnboardingShowcaseCard(
            visual: .image(Image(systemName: "hand.raised.fill")),
            title: "Some sites & apps block VPNs",
            text: "No matter which VPN you use, you'll need to turn it off to use certain sites and apps. Banking apps, for example, may block VPNs to help prevent fraud.")
        SubscriptionOnboardingShowcaseCard(
            visual: .image(Image(systemName: "lock.fill")),
            title: "Secure every connection",
            text: "Your traffic is encrypted end to end, so no one on the network can see the sites you visit or the data you send.")
        SubscriptionOnboardingShowcaseCard(
            visual: .image(Image(systemName: "eye.slash.fill")),
            title: "Hide your location & IP",
            text: "Sites see the VPN's IP address instead of yours, making it harder to track your location and identity across the web.")
    }
}

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingView(
            title: "Step 2 of 4",
            navigationButton: .back({}),
            header: onboardingPreviewHeader(),
            footer: .double(primary: .init("Turn on VPN", action: {}),
                            secondary: .init("Maybe Later", action: {}))) {
            onboardingPreviewBody()
        }
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingView(
            title: "Step 2 of 4",
            navigationButton: .back({}),
            header: onboardingPreviewHeader(),
            footer: .double(primary: .init("Turn on VPN", action: {}),
                            secondary: .init("Maybe Later", action: {}))) {
            onboardingPreviewBody()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Carousel, single primary") {
    RebrandedPreview {
        SubscriptionOnboardingView(
            title: "Step 1 of 4",
            navigationButton: .close({}),
            header: onboardingPreviewHeader(),
            footer: .single(.init("Continue", action: {}))) {
            SubscriptionOnboardingVPNTipsCarousel()
        }
    }
}

#Preview("Long content") {
    RebrandedPreview {
        SubscriptionOnboardingView(
            title: "Step 3 of 4",
            navigationButton: .back({}),
            header: onboardingPreviewHeader(),
            footer: .double(primary: .init("Turn on VPN", action: {}),
                            secondary: .init("Maybe Later", action: {}))) {
            onboardingPreviewLongBody()
        }
    }
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingView(
            title: "Step 2 of 4",
            navigationButton: .back({}),
            header: onboardingPreviewHeader(),
            footer: .single(.init("Turn on VPN", action: {}))) {
            onboardingPreviewBody()
        }
    }
    .dynamicTypeSize(.accessibility5)
}

#Preview("Back + step, no footer") {
    RebrandedPreview {
        SubscriptionOnboardingView(
            title: "Step 1 of 4",
            navigationButton: .back({}),
            header: onboardingPreviewHeader()) {
            onboardingPreviewBody()
        }
    }
}

#endif
