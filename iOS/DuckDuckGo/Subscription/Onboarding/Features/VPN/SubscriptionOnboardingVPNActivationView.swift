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

import Combine
import SwiftUI
import UIKit
import DesignResourcesKit
import UIComponents

/// The VPN activation screen. It owns the activation view
/// model and renders the activation screen. The header, body and footer all switch on
/// the view model's `connectionState`.
struct SubscriptionOnboardingVPNActivationView: View {
    private enum Metrics {
        static let offContentSpacing: CGFloat = 33
        static let onContentSpacing: CGFloat = 22
        static let infoCardStackSpacing: CGFloat = 8
        static let onInfoCardsSpacing: CGFloat = 12
        static let featureRowSpacing: CGFloat = 10
    }

    @StateObject private var viewModel: SubscriptionOnboardingVPNActivationViewModel

    private let title: String?

    @StateObject private var tapAllowHint = TapAllowHintCoordinator()

    @State private var isShowingInfoSheet = false
    @State private var tapAllowHintWindow = TapAllowHintOverlayWindow()

    init(viewModel: @autoclosure @escaping () -> SubscriptionOnboardingVPNActivationViewModel,
         title: String? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.title = title
    }

    var body: some View {
        SubscriptionOnboardingBaseView(
            title: title,
            navigationButton: .back({ viewModel.goBack() }),
            header: header,
            footer: footer) {
            content
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear {
            viewModel.onDisappear()
            // Safety net
            tapAllowHintWindow.hide()
            tapAllowHint.disappeared()
        }
        .subscriptionOnboardingInfoSheet(.vpn, isPresented: $isShowingInfoSheet)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            tapAllowHint.appWillResignActive(isVPNConfigured: viewModel.isVPNConfigured)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            tapAllowHint.appDidBecomeActive(isVPNConfigured: viewModel.isVPNConfigured)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            tapAllowHint.appDidEnterBackground()
        }
        .onReceive(viewModel.$didDenyVPNPermission) { didDeny in
            guard didDeny else { return }
            tapAllowHint.permissionDenied()
        }
        .onReceive(tapAllowHint.$shouldShowHint) { shouldShow in
            if shouldShow {
                tapAllowHintWindow.show()
            } else {
                tapAllowHintWindow.hide()
            }
        }
    }
}

// MARK: - Header

private extension SubscriptionOnboardingVPNActivationView {
    var header: SubscriptionOnboardingHeaderView {
        switch viewModel.connectionState {
        case .off:
            if viewModel.didFailActivation {
                return SubscriptionOnboardingHeaderView(
                    visual: .image(Image(.onboardingCriticalUpdate128)),
                    title: UserText.subscriptionOnboardingVPNActivationFailedTitle,
                    explanation: failureExplanation)
            }
            return SubscriptionOnboardingHeaderView(
                visual: .image(Image(.onboardingVPNDeactivated128)),
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

    var failureExplanation: String {
        viewModel.didDenyVPNPermission ? UserText.subscriptionOnboardingVPNActivationDeniedExplanation
                                       : UserText.vpnErrorConnectionFailed
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
                                                  ipAddress: viewModel.originalIPText,
                                                  location: viewModel.originalLocationText)
                footnote(UserText.subscriptionOnboardingVPNActivationOffFootnote)
            }
        } else {
            VStack(spacing: Metrics.infoCardStackSpacing) {
                VStack(spacing: Metrics.onInfoCardsSpacing) {
                    SubscriptionOnboardingVPNInfoCard(state: .hiddenIP,
                                                      ipAddress: viewModel.originalIPText,
                                                      location: viewModel.originalLocationText)
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
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Footer

private extension SubscriptionOnboardingVPNActivationView {
    var footer: SubscriptionOnboardingFooter {
        switch viewModel.connectionState {
        case .off:
            let startVPN: () -> Void = {
                tapAllowHint.startTapped()
                Task {
                    await viewModel.turnOnVPN()
                    tapAllowHint.turnOnFinished()
                }
            }
            guard viewModel.didFailActivation else {
                return .single(.init(UserText.subscriptionOnboardingVPNActivationTurnOnButton, action: startVPN))
            }
            return .double(primary: .init(UserText.subscriptionOnboardingVPNActivationTryAgainButton, action: startVPN),
                           secondary: .init(UserText.subscriptionOnboardingVPNActivationSkipButton,
                                            push: SubscriptionOnboardingVPNWidgetEducationView(title: title, onDone: { viewModel.advance() })))
        case .on:
            return .single(.init(UserText.subscriptionOnboardingVPNActivationNextButton,
                                 push: SubscriptionOnboardingVPNWidgetEducationView(title: title, onDone: { viewModel.advance() })))
        }
    }
}

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

private let previewLottieRenderer = GraphicLottieRenderer { name, _ in
    AnyView(
        Lottie.LottieView(animation: .named(name))
            .playbackMode(.playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce)))
    )
}

@MainActor
private func activationPreview(state: SubscriptionOnboardingVPNActivationViewModel.ConnectionState,
                               original: SubscriptionOnboardingConnectionInfo?,
                               vpn: SubscriptionOnboardingConnectionInfo? = nil,
                               didDeny: Bool = false,
                               didFailToStart: Bool = false) -> some View {
    SubscriptionOnboardingVPNActivationView(
        viewModel: .preview(state: state,
                            originalConnectionInfo: original,
                            vpnConnectionInfo: vpn,
                            didDenyVPNPermission: didDeny,
                            didFailToStartVPN: didFailToStart),
        title: String(format: UserText.subscriptionOnboardingStepIndicatorFormat, 1, 4))
    .subscriptionOnboardingNavigationContainer()
    .graphicLottieRenderer(previewLottieRenderer)
}

#Preview("Off - Light") {
    RebrandedPreview {
        activationPreview(state: .off, original: .madrid)
    }
}

#Preview("Off - loading") {
    RebrandedPreview {
        activationPreview(state: .off, original: nil)
    }
}

#Preview("Off - denied") {
    RebrandedPreview {
        activationPreview(state: .off, original: .madrid, didDeny: true)
    }
}

#Preview("Off - denied - Dark") {
    RebrandedPreview {
        activationPreview(state: .off, original: .madrid, didDeny: true)
    }
    .preferredColorScheme(.dark)
}

#Preview("Off - denied - Large Text") {
    RebrandedPreview {
        activationPreview(state: .off, original: .madrid, didDeny: true)
    }
    .dynamicTypeSize(.accessibility5)
}

#Preview("Off - start failed") {
    RebrandedPreview {
        activationPreview(state: .off, original: .madrid, didFailToStart: true)
    }
}

#Preview("On - Light") {
    RebrandedPreview {
        activationPreview(state: .on, original: .madrid, vpn: .valencia)
    }
}

#Preview("On - loading") {
    RebrandedPreview {
        activationPreview(state: .on, original: .madrid, vpn: nil)
    }
}

#Preview("On - no original IP") {
    RebrandedPreview {
        // Direct on-state entry: no original (pre-VPN) IP, so its card shows the placeholders.
        activationPreview(state: .on, original: nil, vpn: .valencia)
    }
}

#Preview("On - Dark") {
    RebrandedPreview {
        activationPreview(state: .on, original: .madrid, vpn: .valencia)
    }
    .preferredColorScheme(.dark)
}

#Preview("On - Large Text") {
    RebrandedPreview {
        activationPreview(state: .on, original: .madrid, vpn: .valencia)
    }
    .dynamicTypeSize(.accessibility5)
}

/// Exercises the off→on reveal (and its slide-in) in the canvas: starts off, then turns the VPN on after a
/// beat so the on-state content slides in. Re-run the preview (⌥⌘P) to replay; in a Live Preview you can
/// also tap "Turn On VPN" to trigger it manually.
private struct VPNRevealPreview: View {
    @StateObject private var viewModel = SubscriptionOnboardingVPNActivationViewModel.previewReveal(
        original: .madrid, vpn: .valencia)

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
