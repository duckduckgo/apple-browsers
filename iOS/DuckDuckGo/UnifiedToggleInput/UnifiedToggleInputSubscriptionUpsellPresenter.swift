//
//  UnifiedToggleInputSubscriptionUpsellPresenter.swift
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

import AIChat
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI
import UIKit

@MainActor
final class UnifiedToggleInputSubscriptionUpsellPresenter {
    private weak var presentedViewController: UIViewController?

    func present(
        from presentingViewController: UIViewController,
        onSubscribe: @escaping () -> Void,
        onHaveSubscription: @escaping () -> Void
    ) {
        guard presentedViewController == nil else { return }

        let rootView = UnifiedToggleInputSubscriptionUpsellView(
            onSubscribe: { [weak self] in
                self?.dismiss(completion: onSubscribe)
            },
            onHaveSubscription: { [weak self] in
                self?.dismiss(completion: onHaveSubscription)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.modalTransitionStyle = .crossDissolve

        presentingViewController.present(hostingController, animated: true)
        presentedViewController = hostingController
    }

    private func dismiss(completion: (() -> Void)? = nil) {
        guard let presentedViewController else {
            completion?()
            return
        }

        self.presentedViewController = nil
        presentedViewController.dismiss(animated: true, completion: completion)
    }
}

struct UnifiedToggleInputSubscriptionUpsellView: View {
    let onSubscribe: () -> Void
    let onHaveSubscription: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color(designSystemColor: .decorationTertiary)
                .ignoresSafeArea()

            alertCard
                .padding(.horizontal, Metrics.screenHorizontalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var alertCard: some View {
        if #available(iOS 26.0, *) {
            alertContent
                .frame(maxWidth: Metrics.cardWidth)
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                )
        } else {
            alertContent
                .frame(maxWidth: Metrics.cardWidth)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                )
        }
    }

    private var alertContent: some View {
        VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
            VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
                Image(uiImage: DesignSystemImages.Color.Size96.duckAISubscription)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(x: -1, y: 1)
                    .frame(width: Metrics.imageSize, height: Metrics.imageSize)
                    .accessibilityHidden(true)

                Text(verbatim: "Upgrade Duck.ai with a DuckDuckGo subscription")
                    .daxHeadline()
                    .foregroundStyle(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: """
                    Get access to advanced AI models in Duck.ai by subscribing to DuckDuckGo, \
                    which also includes our VPN and other premium privacy protections.
                    """)
                    .daxBodyRegular()
                    .foregroundStyle(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Metrics.textHorizontalPadding)
            .padding(.top, Metrics.textTopPadding)
            .padding(.bottom, Metrics.textBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: Metrics.contentSpacing) {
                Button(action: onSubscribe) {
                    Text(verbatim: "Subscribe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SubscriptionUpsellButtonStyle(appearance: .primary))
                .accessibilityIdentifier("SubscriptionUpsellSubscribeButton")

                Button(action: onHaveSubscription) {
                    Text(verbatim: "I Have a Subscription")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SubscriptionUpsellButtonStyle(appearance: .secondary))
                .accessibilityIdentifier("SubscriptionUpsellHaveSubscriptionButton")

                Button(action: onDismiss) {
                    Text(verbatim: "Not Now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SubscriptionUpsellButtonStyle(appearance: .cancel))
                .accessibilityIdentifier("SubscriptionUpsellNotNowButton")
            }
        }
        .padding(Metrics.cardPadding)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("SubscriptionUpsellAlert")
    }
}

private extension UnifiedToggleInputSubscriptionUpsellView {
    enum Metrics {
        static let cardWidth: CGFloat = 338
        static let cardCornerRadius: CGFloat = 34
        static let cardPadding: CGFloat = 14
        static let screenHorizontalPadding: CGFloat = 32
        static let contentSpacing: CGFloat = 10
        static let textHorizontalPadding: CGFloat = 8
        static let textTopPadding: CGFloat = 8
        static let textBottomPadding: CGFloat = 24
        static let imageSize: CGFloat = 72
    }
}

private struct SubscriptionUpsellButtonStyle: ButtonStyle {
    enum Appearance {
        case primary
        case secondary
        case cancel
    }

    let appearance: Appearance

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.height)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(Capsule())
            .contentShape(Capsule())
    }

    private var foregroundColor: Color {
        switch appearance {
        case .primary:
            return Color(designSystemColor: .accentContentPrimary)
        case .secondary, .cancel:
            return Color(designSystemColor: .textPrimary)
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch appearance {
        case .primary:
            return Color(designSystemColor: isPressed ? .accentTertiary : .accentPrimary)
        case .secondary:
            return Color(designSystemColor: isPressed ? .controlsFillTertiary : .controlsFillSecondary)
        case .cancel:
            return Color(designSystemColor: isPressed ? .decorationTertiary : .decorationSecondary)
        }
    }
}

private extension SubscriptionUpsellButtonStyle {
    enum Metrics {
        static let height: CGFloat = 48
    }
}
