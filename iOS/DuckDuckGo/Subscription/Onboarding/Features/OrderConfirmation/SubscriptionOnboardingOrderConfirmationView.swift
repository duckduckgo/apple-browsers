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

struct SubscriptionOnboardingOrderConfirmationView: View {
    private enum Metrics {
        static let contentSpacing: CGFloat = 24
        static let illustrationOverhang: CGFloat = 36
    }

    @StateObject private var viewModel: SubscriptionOnboardingOrderConfirmationViewModel

    private let navigationButton: SubscriptionOnboardingNavigationButton?

    init(viewModel: @autoclosure @escaping () -> SubscriptionOnboardingOrderConfirmationViewModel,
         navigationButton: SubscriptionOnboardingNavigationButton? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.navigationButton = navigationButton
    }

    var body: some View {
        SubscriptionOnboardingBaseView(
            navigationButton: navigationButton,
            header: header,
            footer: .single(.init(UserText.subscriptionOnboardingOrderConfirmationNextButton) { viewModel.proceed() }),
            scrollsContent: false,
            pageBackground: { illustration }) {
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
            explanation: UserText.subscriptionOnboardingOrderConfirmationExplanation)
    }

    var content: some View {
        VStack(spacing: Metrics.contentSpacing) {
            // iPad's calendar card doesn't fit the layout
            // suppressed regardless of trial state.
            if let freeTrialCard = viewModel.freeTrialCard, UIDevice.current.userInterfaceIdiom != .pad {
                SubscriptionOnboardingFreeTrialCalendarCard(model: freeTrialCard)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var illustration: some View {
        GeometryReader { proxy in
            Image(.daxThumbupStatic)
                .resizable()
                .scaledToFit()
                .frame(width: proxy.size.width)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .offset(y: Metrics.illustrationOverhang)
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG

#Preview("Free trial — day 1") {
    RebrandedPreview {
        SubscriptionOnboardingOrderConfirmationView(
            viewModel: .preview(state: .previewFreeTrial()),
            navigationButton: .close({}))
            .subscriptionOnboardingNavigationContainer()
    }
}

#Preview("Free trial — midway") {
    RebrandedPreview {
        SubscriptionOnboardingOrderConfirmationView(
            viewModel: .preview(state: .previewFreeTrial(dayOffset: 3)),
            navigationButton: .close({}))
            .subscriptionOnboardingNavigationContainer()
    }
}

#Preview("Paid") {
    RebrandedPreview {
        SubscriptionOnboardingOrderConfirmationView(
            viewModel: .preview(state: .paid),
            navigationButton: .close({}))
            .subscriptionOnboardingNavigationContainer()
    }
}

#Preview("Loading") {
    RebrandedPreview {
        SubscriptionOnboardingOrderConfirmationView(
            viewModel: .preview(state: .loading),
            navigationButton: .close({}))
            .subscriptionOnboardingNavigationContainer()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingOrderConfirmationView(
            viewModel: .preview(state: .previewFreeTrial()),
            navigationButton: .close({}))
            .subscriptionOnboardingNavigationContainer()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingOrderConfirmationView(
            viewModel: .preview(state: .previewFreeTrial()),
            navigationButton: .close({}))
            .subscriptionOnboardingNavigationContainer()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
