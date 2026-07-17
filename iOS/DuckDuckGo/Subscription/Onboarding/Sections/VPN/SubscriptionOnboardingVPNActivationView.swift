//
//  SubscriptionOnboardingVPNActivationView.swift
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

/// The root of the VPN onboarding section, built by ``SubscriptionOnboardingViewFactory``. It owns the
/// activation view model and the section's internal navigation: the tips screen (presented after the VPN
/// is on) and the "Learn More" info sheet. `onBack` leads to the previous flow section (the welcome
/// screen, built in a later stage); it defaults to a no-op here.
struct SubscriptionOnboardingVPNSectionView: View {
    @StateObject private var viewModel: SubscriptionOnboardingVPNActivationViewModel
    private let onBack: () -> Void

    @State private var isShowingTips = false
    @State private var isShowingInfo = false

    init(viewModel: @autoclosure @escaping () -> SubscriptionOnboardingVPNActivationViewModel = SubscriptionOnboardingVPNActivationViewModel(),
         onBack: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.onBack = onBack
    }

    var body: some View {
        SubscriptionOnboardingVPNActivationView(
            viewModel: viewModel,
            onBack: onBack,
            onNext: { isShowingTips = true },
            onLearnMore: { isShowingInfo = true })
        .fullScreenCover(isPresented: $isShowingTips) {
            SubscriptionOnboardingVPNTipsView(onDismiss: { isShowingTips = false })
        }
        .sheet(isPresented: $isShowingInfo) {
            SubscriptionOnboardingVPNInfoView(onClose: { isShowingInfo = false })
        }
    }
}

/// The VPN activation screen: one screen with two states (off and on). Off shows the visible IP and the
/// still-inactive protections with a "Turn On VPN" button; on shows the hidden real IP, the new egress IP
/// and the now-active protections with a "Next" button. The header, body and footer all switch on the
/// view model's `connectionState`.
struct SubscriptionOnboardingVPNActivationView: View {
    @ObservedObject var viewModel: SubscriptionOnboardingVPNActivationViewModel

    let onBack: () -> Void
    let onNext: () -> Void
    let onLearnMore: () -> Void

    /// The "Step X of Y" indicator is owned by the flow (a later stage), so it is passed in; nil hides it.
    var stepTitle: String? = nil

    private enum Metrics {
        static let contentSpacing: CGFloat = 24
        static let cardSpacing: CGFloat = 8
        static let rowSpacing: CGFloat = 8
    }

    var body: some View {
        SubscriptionOnboardingView(
            title: stepTitle,
            navigationButton: .back(onBack),
            header: header,
            footer: footer) {
            content
        }
        .task { await viewModel.onAppear() }
        .task(id: viewModel.connectionState) {
            guard viewModel.connectionState == .on else { return }
            await viewModel.refreshVPNConnectionInfo()
        }
    }
}

// MARK: - Header

private extension SubscriptionOnboardingVPNActivationView {
    var header: SubscriptionOnboardingHeaderView {
        switch viewModel.connectionState {
        case .off:
            return SubscriptionOnboardingHeaderView(
                visual: .image(Image(.onboardingVPN56)),
                title: UserText.subscriptionOnboardingVPNActivationOffTitle,
                explanation: UserText.subscriptionOnboardingVPNActivationOffExplanation,
                onInfoLinkTap: onLearnMore)
        case .on:
            return SubscriptionOnboardingHeaderView(
                visual: .lottie(name: "vpn-v4"),
                title: UserText.subscriptionOnboardingVPNActivationOnTitle,
                explanation: UserText.subscriptionOnboardingVPNActivationOnExplanation,
                onInfoLinkTap: onLearnMore)
        }
    }
}

// MARK: - Body

private extension SubscriptionOnboardingVPNActivationView {
    @ViewBuilder
    var content: some View {
        switch viewModel.connectionState {
        case .off: offContent
        case .on: onContent
        }
    }

    var offContent: some View {
        VStack(spacing: Metrics.contentSpacing) {
            SubscriptionOnboardingVPNInfoCard(state: .visibleIP,
                                              ipAddress: viewModel.realIPText,
                                              location: viewModel.realLocationText)
            footnote(UserText.subscriptionOnboardingVPNActivationOffFootnote)
            featureRows(status: .inactive)
        }
    }

    var onContent: some View {
        VStack(spacing: Metrics.contentSpacing) {
            VStack(spacing: Metrics.cardSpacing) {
                SubscriptionOnboardingVPNInfoCard(state: .hiddenIP,
                                                  ipAddress: viewModel.realIPText,
                                                  location: viewModel.realLocationText)
                SubscriptionOnboardingVPNInfoCard(state: .newIP,
                                                  ipAddress: viewModel.vpnIPText,
                                                  location: viewModel.vpnLocationText)
            }
            footnote(UserText.subscriptionOnboardingVPNActivationOnFootnote)
            featureRows(status: .active)
        }
    }

    func featureRows(status: SubscriptionOnboardingListItemView.Status) -> some View {
        VStack(spacing: Metrics.rowSpacing) {
            ForEach(VPNProtection.allCases, id: \.self) { protection in
                SubscriptionOnboardingListItemView(text: protection.text, status: status)
            }
        }
    }

    func footnote(_ text: String) -> some View {
        Text(text)
            .daxFootnoteRegular()
            .multilineTextAlignment(.center)
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Footer

private extension SubscriptionOnboardingVPNActivationView {
    var footer: SubscriptionOnboardingFooter {
        switch viewModel.connectionState {
        case .off:
            return .single(.init(UserText.subscriptionOnboardingVPNActivationTurnOnButton) {
                Task { await viewModel.turnOnVPN() }
            })
        case .on:
            return .single(.init(UserText.subscriptionOnboardingVPNActivationNextButton, action: onNext))
        }
    }
}

/// The three protections listed on the activation screen; they render inactive while off and active once on.
private enum VPNProtection: CaseIterable {
    case shielding
    case hidingLocation
    case blockingSites

    var text: String {
        switch self {
        case .shielding: UserText.subscriptionOnboardingVPNProtectionShielding
        case .hidingLocation: UserText.subscriptionOnboardingVPNProtectionHidingLocation
        case .blockingSites: UserText.subscriptionOnboardingVPNProtectionBlockingSites
        }
    }
}

// MARK: - Tips screen

/// The post-activation "What to know about using your VPN" screen: the shared tips carousel with a single
/// button that returns to the VPN activation screen.
struct SubscriptionOnboardingVPNTipsView: View {
    let onDismiss: () -> Void

    /// The "Step X of Y" indicator is owned by the flow (a later stage), so it is passed in; nil hides it.
    var stepTitle: String? = nil

    var body: some View {
        SubscriptionOnboardingView(
            title: stepTitle,
            navigationButton: .back(onDismiss),
            header: SubscriptionOnboardingHeaderView(title: UserText.subscriptionOnboardingVPNTipsTitle),
            footer: .single(.init(UserText.subscriptionOnboardingVPNTipsDoneButton, action: onDismiss))) {
            SubscriptionOnboardingVPNTipsCarousel()
        }
    }
}

#if DEBUG

import Lottie

private extension SubscriptionOnboardingConnectionInfo {
    static let madrid = SubscriptionOnboardingConnectionInfo(ip: "31.120.130.50", city: "Madrid", country: "ES")
    static let valencia = SubscriptionOnboardingConnectionInfo(ip: "45.132.71.9", city: "Valencia", country: "ES")
}

/// Renders the on-state check Lottie (`check-color`) in previews; at runtime the flow host injects its own
/// renderer, matching the convention in `SubscriptionOnboardingProgressView`.
private let previewLottieRenderer = GraphicLottieRenderer { name, _ in
    AnyView(
        Lottie.LottieView(animation: .named(name))
            .playbackMode(.playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce)))
    )
}

private func activationPreview(state: SubscriptionOnboardingVPNActivationViewModel.ConnectionState,
                               real: SubscriptionOnboardingConnectionInfo?,
                               vpn: SubscriptionOnboardingConnectionInfo? = nil) -> some View {
    SubscriptionOnboardingVPNActivationView(
        viewModel: .preview(state: state, realConnectionInfo: real, vpnConnectionInfo: vpn),
        onBack: {},
        onNext: {},
        onLearnMore: {},
        stepTitle: String(format: UserText.subscriptionOnboardingStepIndicatorFormat, 1, 4))
    .graphicLottieRenderer(previewLottieRenderer)
}

#Preview("Off - Light") {
    RebrandedPreview {
        activationPreview(state: .off, real: .madrid)
    }
}

#Preview("Off - loading") {
    RebrandedPreview {
        activationPreview(state: .off, real: nil)
    }
}

#Preview("On - Light") {
    RebrandedPreview {
        activationPreview(state: .on, real: .madrid, vpn: .valencia)
    }
}

#Preview("On - Dark") {
    RebrandedPreview {
        activationPreview(state: .on, real: .madrid, vpn: .valencia)
    }
    .preferredColorScheme(.dark)
}

#Preview("On - Large Text") {
    RebrandedPreview {
        activationPreview(state: .on, real: .madrid, vpn: .valencia)
    }
    .dynamicTypeSize(.accessibility5)
}

#Preview("Tips") {
    RebrandedPreview {
        SubscriptionOnboardingVPNTipsView(
            onDismiss: {},
            stepTitle: String(format: UserText.subscriptionOnboardingStepIndicatorFormat, 1, 4))
    }
}

#endif
