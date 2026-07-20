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
import UIKit
import DesignResourcesKit
import UIComponents

private enum Metrics {
    static let offContentSpacing: CGFloat = 33
    static let onContentSpacing: CGFloat = 22
    static let infoCardStackSpacing: CGFloat = 8
    static let onInfoCardsSpacing: CGFloat = 12
    static let featureRowSpacing: CGFloat = 10
}

/// The VPN activation screen, built by ``SubscriptionOnboardingViewFactory``. It owns the activation view
/// model and renders the activation screen (the same screen in two states: off and on) plus the section's
/// internal navigation: the widget-education and tips screens (pushed onto the navigation stack after the
/// VPN is on) and the "Learn More" info screen (presented as a page sheet). The header, body and footer all switch on
/// the view model's `connectionState`. The back button pops the navigation stack natively (via the
/// environment's `dismiss`), returning to the previous flow section once this section is pushed onto the
/// flow's stack (a later stage).
struct SubscriptionOnboardingVPNActivationView: View {
    @StateObject private var viewModel: SubscriptionOnboardingVPNActivationViewModel

    private let title: String?

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingInfoSheet = false
    @State private var tapAllowHint = TapAllowHintOverlayWindow()
    /// True from tapping "Turn On VPN" until `start()` resolves, so the scene going inactive is read as the
    /// system permission dialog appearing rather than an unrelated interruption.
    @State private var awaitingPermissionPrompt = false

    init(viewModel: @autoclosure @escaping () -> SubscriptionOnboardingVPNActivationViewModel = SubscriptionOnboardingVPNActivationViewModel(),
         title: String? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.title = title
    }

    var body: some View {
        SubscriptionOnboardingBaseView(
            title: title,
            navigationButton: .back({ dismiss() }),
            header: header,
            footer: footer) {
            content
        }
        .task { await viewModel.onAppear() }
        .sheet(isPresented: $isShowingInfoSheet) {
            SubscriptionOnboardingInfoView(content: .vpn, onClose: { isShowingInfoSheet = false })
                .subscriptionOnboardingNavigationContainer()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            guard awaitingPermissionPrompt else { return }
            tapAllowHint.show()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            guard awaitingPermissionPrompt else { return }
            tapAllowHint.hide()
        }
        // Safety net: tear the hint window down if the screen leaves while the dialog is still up.
        .onDisappear { tapAllowHint.hide() }
    }
}

// MARK: - Header

private extension SubscriptionOnboardingVPNActivationView {
    var header: SubscriptionOnboardingHeaderView {
        switch viewModel.connectionState {
        case .off:
            return SubscriptionOnboardingHeaderView(
                visual: .image(Image(.onboardingHeaderVPNDeactivated128)),
                title: UserText.subscriptionOnboardingVPNActivationOffTitle,
                explanation: UserText.subscriptionOnboardingVPNActivationOffExplanation,
                onInfoLinkTap: { isShowingInfoSheet = true })
        case .on:
            return SubscriptionOnboardingHeaderView(
                visual: .lottie(name: "vpn-v4"),
                title: UserText.subscriptionOnboardingVPNActivationOnTitle,
                explanation: UserText.subscriptionOnboardingVPNActivationOnExplanation,
                onInfoLinkTap: { isShowingInfoSheet = true })
        }
    }
}

// MARK: - Body

private extension SubscriptionOnboardingVPNActivationView {
    var content: some View {
        let isOn = viewModel.connectionState == .on
        return VStack(spacing: isOn ? Metrics.onContentSpacing : Metrics.offContentSpacing) {
            vpnInfoCards
            featureRows
        }
    }

    @ViewBuilder
    var vpnInfoCards: some View {
        if viewModel.connectionState == .off {
            VStack(spacing: Metrics.infoCardStackSpacing) {
                SubscriptionOnboardingVPNInfoCard(state: .visibleIP,
                                                  ipAddress: viewModel.realIPText,
                                                  location: viewModel.realLocationText)
                footnote(UserText.subscriptionOnboardingVPNActivationOffFootnote)
            }
        } else {
            VStack(spacing: Metrics.infoCardStackSpacing) {
                VStack(spacing: Metrics.onInfoCardsSpacing) {
                    SubscriptionOnboardingVPNInfoCard(state: .hiddenIP,
                                                      ipAddress: viewModel.realIPText,
                                                      location: viewModel.realLocationText)
                    SubscriptionOnboardingVPNInfoCard(state: .newIP,
                                                      ipAddress: viewModel.vpnIPText,
                                                      location: viewModel.vpnLocationText,
                                                      nearestIndicator: viewModel.vpnLocationNearestIndicator)
                }
                footnote(UserText.subscriptionOnboardingVPNActivationOnFootnote)
            }
        }
    }

    var featureRows: some View {
        VStack(spacing: Metrics.featureRowSpacing) {
            ForEach(VPNProtection.allCases, id: \.self) { protection in
                SubscriptionOnboardingListItemView(
                    text: protection.text,
                    status: viewModel.connectionState == .on ? .active : .inactive)
            }
        }
        .id(viewModel.connectionState)
        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .identity))
        .animation(.easeInOut(duration: 0.4), value: viewModel.connectionState)
    }

    func footnote(_ text: String) -> some View {
        Text(text)
            .daxFootnoteRegular()
            .multilineTextAlignment(.leading)
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Footer

private extension SubscriptionOnboardingVPNActivationView {
    var footer: SubscriptionOnboardingFooter {
        switch viewModel.connectionState {
        case .off:
            let startVPN: () -> Void = {
                Task {
                    if !(await viewModel.isVPNConfigured()) {
                        awaitingPermissionPrompt = true
                    }
                    await viewModel.turnOnVPN()
                    awaitingPermissionPrompt = false
                    tapAllowHint.hide()
                }
            }
            guard viewModel.didDenyVPNPermission else {
                return .single(.init(UserText.subscriptionOnboardingVPNActivationTurnOnButton, action: startVPN))
            }
            return .double(primary: .init(UserText.subscriptionOnboardingVPNActivationTryAgainButton, action: startVPN),
                           secondary: .init(UserText.subscriptionOnboardingVPNActivationSkipButton,
                                            push: SubscriptionOnboardingVPNWidgetEducationView(title: title)))
        case .on:
            return .single(.init(UserText.subscriptionOnboardingVPNActivationNextButton,
                                 push: SubscriptionOnboardingVPNWidgetEducationView(title: title)))
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

#if DEBUG

import Lottie

private extension SubscriptionOnboardingConnectionInfo {
    static let madrid = SubscriptionOnboardingConnectionInfo(ip: "31.120.130.50", city: "Madrid", country: "ES")
    static let valencia = SubscriptionOnboardingConnectionInfo(ip: "45.132.71.9", city: "Valencia", country: "ES")
}

/// Renders the on-state header Lottie in previews; at runtime the flow host injects its own renderer,
/// matching the convention in `SubscriptionOnboardingProgressView`.
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
        title: String(format: UserText.subscriptionOnboardingStepIndicatorFormat, 1, 4))
    .subscriptionOnboardingNavigationContainer()
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

#Preview("On - loading") {
    RebrandedPreview {
        activationPreview(state: .on, real: .madrid, vpn: nil)
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

/// Exercises the off→on reveal (and its slide-in) in the canvas: starts off, then turns the VPN on after a
/// beat so the on-state content slides in. Re-run the preview (⌥⌘P) to replay; in a Live Preview you can
/// also tap "Turn On VPN" to trigger it manually.
private struct VPNRevealPreview: View {
    @StateObject private var viewModel = SubscriptionOnboardingVPNActivationViewModel.previewReveal(
        real: .madrid, vpn: .valencia)

    var body: some View {
        SubscriptionOnboardingVPNActivationView(
            viewModel: viewModel,
            title: String(format: UserText.subscriptionOnboardingStepIndicatorFormat, 1, 4))
        .subscriptionOnboardingNavigationContainer()
        .graphicLottieRenderer(previewLottieRenderer)
        .task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await viewModel.turnOnVPN()
        }
    }
}

#Preview("On - reveal") {
    RebrandedPreview {
        VPNRevealPreview()
    }
}

#endif
