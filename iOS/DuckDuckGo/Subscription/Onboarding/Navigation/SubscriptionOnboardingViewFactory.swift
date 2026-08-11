//
//  SubscriptionOnboardingViewFactory.swift
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

@MainActor
struct SubscriptionOnboardingViewFactory {

    private let flow: SubscriptionOnboardingFlowViewModel

    private var prefetcher: SubscriptionOnboardingPrefetcher { flow.prefetcher }

    init(flow: SubscriptionOnboardingFlowViewModel) {
        self.flow = flow
    }

    /// The PIR screen launched from the summary's checklist row.
    func pirLaunchScreen() -> AnyView {
        AnyView(
            SubscriptionOnboardingPIRView(
                title: String(format: UserText.subscriptionOnboardingStepIndicatorFormat,
                              SubscriptionOnboardingSection.indicatorStepCount,
                              SubscriptionOnboardingSection.indicatorStepCount),
                navigationButton: .close { flow.isPresentingPIR = false },
                push: flow.pirScreen())
                .subscriptionOnboardingNavigationContainer())
    }

    func screen(for section: SubscriptionOnboardingSection) -> AnyView {
        let title = flow.title(for: section)
        let navigationButton = flow.navigationButton(for: section)

        switch section {
        case .orderConfirmation:
            return AnyView(SubscriptionOnboardingOrderConfirmationView(
                viewModel: SubscriptionOnboardingOrderConfirmationViewModel(
                    onNext: { flow.sectionDidRequestAdvance() }),
                navigationButton: navigationButton))

        case .welcome:
            return AnyView(SubscriptionOnboardingWelcomeView(
                navigationButton: navigationButton,
                onNext: { flow.sectionDidRequestAdvance() }))

        case .vpnActivation:
            return AnyView(SubscriptionOnboardingVPNActivationView(
                viewModel: SubscriptionOnboardingVPNActivationViewModel(
                    prefetcher: prefetcher,
                    onComplete: { flow.sectionDidComplete(.vpnActivation) },
                    onNext: { flow.sectionDidRequestAdvance() }),
                title: title,
                navigationButton: navigationButton))

        case .vpnWidget:
            return AnyView(SubscriptionOnboardingVPNWidgetEducationView(
                title: title,
                navigationButton: navigationButton,
                onComplete: { flow.sectionDidComplete(.vpnWidget) },
                onNext: { flow.sectionDidRequestAdvance() }))

        case .idtr:
            return AnyView(SubscriptionOnboardingIDTRView(
                title: title,
                navigationButton: navigationButton,
                onNext: {
                    flow.sectionDidComplete(.idtr)
                    flow.sectionDidRequestAdvance()
                }))

        case .duckAI:
            return AnyView(SubscriptionOnboardingDuckAIView(
                viewModel: SubscriptionOnboardingDuckAIViewModel(
                    prefetcher: prefetcher,
                    onComplete: { flow.sectionDidComplete(.duckAI) },
                    onNext: { flow.sectionDidRequestAdvance() },
                    onRequestChat: { flow.sectionDidRequestDuckAIChat(modelID: $0) }),
                title: title,
                navigationButton: navigationButton,
                progress: flow.progress))

        case .progress:
            return AnyView(SubscriptionOnboardingProgressView(
                progress: flow.progress,
                pirLaunch: flow.pirLaunch,
                navigationButton: navigationButton,
                onSelectItem: { item in
                    guard item == .pir else { return }
                    flow.isPresentingPIR = true
                },
                onNext: { flow.finish() }))

        case .pir:
            return AnyView(EmptyView())
        }
    }
}
