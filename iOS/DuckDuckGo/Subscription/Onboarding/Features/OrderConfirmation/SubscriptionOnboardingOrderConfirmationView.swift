//
//  SubscriptionOnboardingOrderConfirmationView.swift
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

/// The first screen after checkout: confirms the purchase and, when the customer is on a free trial, shows
/// where they are in it. The calendar card is omitted for a paid purchase, and while the subscription is
/// still resolving.
struct SubscriptionOnboardingOrderConfirmationView: View {
    private enum Metrics {
        static let contentSpacing: CGFloat = 24
        /// How much further than the page's own bottom inset the illustration is pulled down, so it also
        /// eats into the gap above the CTA. Tuned by eye.
        static let illustrationOverhang: CGFloat = 36
        /// The illustration's authored size (402x351) as a ratio, so its height follows the page width
        /// instead of whatever vertical space happens to be left over.
        static let illustrationAspectRatio: CGFloat = 402.0 / 351.0
    }

    @StateObject private var viewModel: SubscriptionOnboardingOrderConfirmationViewModel

    private let navigationButton: SubscriptionOnboardingNavigationButton?
    private let onNext: () -> Void

    init(viewModel: @autoclosure @escaping () -> SubscriptionOnboardingOrderConfirmationViewModel,
         navigationButton: SubscriptionOnboardingNavigationButton? = nil,
         onNext: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.navigationButton = navigationButton
        self.onNext = onNext
    }

    var body: some View {
        SubscriptionOnboardingBaseView(
            navigationButton: navigationButton,
            header: header,
            footer: .single(.init(UserText.subscriptionOnboardingOrderConfirmationNextButton, action: onNext)),
            scrollsContent: false) {
            content
        }
        .overlay { ConfettiView() }
        .task { await viewModel.load() }
    }
}

// MARK: - Header + content

private extension SubscriptionOnboardingOrderConfirmationView {

    var header: SubscriptionOnboardingHeaderView {
        SubscriptionOnboardingHeaderView(
            visual: .image(Image(.subscriptionCheckFeature128)),
            title: UserText.subscriptionOnboardingOrderConfirmationTitle,
            explanation: viewModel.explanation)
    }

    /// The illustration is a background (not stacked) so the card floats over it. The geometry reader supplies
    /// page width for sizing the artwork, since SwiftUI would otherwise constrain it to available height.
    var content: some View {
        GeometryReader { proxy in
            VStack(spacing: Metrics.contentSpacing) {
                if let freeTrialCard = viewModel.freeTrialCard {
                    SubscriptionOnboardingFreeTrialCalendarCard(model: freeTrialCard)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(alignment: .bottom) {
                illustration(pageWidth: proxy.size.width + SubscriptionOnboardingPageInsets.horizontal * 2)
            }
        }
    }

    /// Static image (not Lottie). Sized by width with height from the ratio. Negative paddings cancel the base view's page insets.
    func illustration(pageWidth: CGFloat) -> some View {
        Image(.daxThumbupStatic)
            .resizable()
            .scaledToFit()
            .frame(width: pageWidth, height: pageWidth / Metrics.illustrationAspectRatio)
            .padding(.horizontal, -SubscriptionOnboardingPageInsets.horizontal)
            .padding(.bottom, -(SubscriptionOnboardingPageInsets.vertical + Metrics.illustrationOverhang))
            .accessibilityHidden(true)
    }
}

#if DEBUG

#Preview("Free trial — day 1") {
    RebrandedPreview {
        SubscriptionOnboardingOrderConfirmationView(
            viewModel: .preview(state: .previewFreeTrial()),
            navigationButton: .close({}),
            onNext: {})
            .subscriptionOnboardingNavigationContainer()
    }
}

#Preview("Free trial — midway") {
    RebrandedPreview {
        SubscriptionOnboardingOrderConfirmationView(
            viewModel: .preview(state: .previewFreeTrial(dayOffset: 3)),
            navigationButton: .close({}),
            onNext: {})
            .subscriptionOnboardingNavigationContainer()
    }
}

#Preview("Paid") {
    RebrandedPreview {
        SubscriptionOnboardingOrderConfirmationView(
            viewModel: .preview(state: .paid),
            navigationButton: .close({}),
            onNext: {})
            .subscriptionOnboardingNavigationContainer()
    }
}

#Preview("Loading") {
    RebrandedPreview {
        SubscriptionOnboardingOrderConfirmationView(
            viewModel: .preview(state: .loading),
            navigationButton: .close({}),
            onNext: {})
            .subscriptionOnboardingNavigationContainer()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingOrderConfirmationView(
            viewModel: .preview(state: .previewFreeTrial()),
            navigationButton: .close({}),
            onNext: {})
            .subscriptionOnboardingNavigationContainer()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingOrderConfirmationView(
            viewModel: .preview(state: .previewFreeTrial()),
            navigationButton: .close({}),
            onNext: {})
            .subscriptionOnboardingNavigationContainer()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
