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

/// Builds screens by index (not section), since `.progress` appears twice with different chrome.
@MainActor
struct SubscriptionOnboardingViewFactory {

    private let flow: SubscriptionOnboardingFlowViewModel
    private let prefetcher: SubscriptionOnboardingPrefetcher
    /// PIR screen provider, supplied by the host.
    private let pirDestination: () -> AnyView

    init(flow: SubscriptionOnboardingFlowViewModel,
         prefetcher: SubscriptionOnboardingPrefetcher,
         pirDestination: @escaping () -> AnyView) {
        self.flow = flow
        self.prefetcher = prefetcher
        self.pirDestination = pirDestination
    }

    func screen(at index: Int) -> AnyView {
        guard let section = flow.section(at: index) else { return AnyView(EmptyView()) }

        let title = flow.title(at: index)
        let navigationButton = flow.navigationButton(at: index)

        switch section {
        case .orderConfirmation:
            return AnyView(SubscriptionOnboardingOrderConfirmationView(
                viewModel: SubscriptionOnboardingOrderConfirmationViewModel(delegate: flow),
                navigationButton: navigationButton))

        case .welcome:
            return AnyView(SubscriptionOnboardingWelcomeView(
                navigationButton: navigationButton,
                onNext: { flow.proceed() }))

        case .vpnActivation:
            return AnyView(SubscriptionOnboardingVPNActivationView(
                viewModel: SubscriptionOnboardingVPNActivationViewModel(prefetcher: prefetcher, delegate: flow),
                title: title,
                navigationButton: navigationButton))

        case .vpnWidget:
            return AnyView(SubscriptionOnboardingVPNWidgetEducationView(
                title: title,
                navigationButton: navigationButton,
                onWidgetStepDone: { flow.markComplete(.widget) },
                onDone: { flow.proceed() }))

        case .idtr:
            return AnyView(SubscriptionOnboardingIDTRView(
                title: title,
                navigationButton: navigationButton,
                onNext: { flow.proceed() })
                .onAppear { flow.markComplete(.idtr) })

        case .duckAI:
            return AnyView(SubscriptionOnboardingDuckAIView(
                viewModel: SubscriptionOnboardingDuckAIViewModel(prefetcher: prefetcher, delegate: flow),
                title: title,
                navigationButton: navigationButton,
                progress: { .init(percentage: flow.completionPercentage,
                                  items: flow.checklist,
                                  completedItems: flow.completedItems) }))

        case .progress:
            return AnyView(SubscriptionOnboardingProgressView(
                variant: flow.progressVariant,
                percentage: flow.completionPercentage,
                items: flow.checklist,
                completedItems: flow.completedItems,
                navigationButton: navigationButton,
                onSelectItem: { item in
                    guard item == .pir else { return }
                    flow.isPresentingPIR = true
                },
                onDone: { flow.proceed() }))

        case .pir:
            return AnyView(SubscriptionOnboardingPIRView(
                title: title,
                navigationButton: navigationButton,
                push: pirDestination()))
        }
    }
}
