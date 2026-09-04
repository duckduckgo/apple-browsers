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
import DesignResourcesKitIcons

@MainActor
struct SubscriptionOnboardingViewFactory {

    private let flow: SubscriptionOnboardingFlowViewModel

    /// Debug-menu ONLY: forces `.orderConfirmation`'s free-trial card to this length, bypassing the real
    /// subscription fetch, so the Mock Flow can show any trial length without a matching real purchase.
    private let forcedTrialLengthDays: Int?

    private var prefetcher: SubscriptionOnboardingPrefetcher { flow.prefetcher }

    init(flow: SubscriptionOnboardingFlowViewModel) {
        self.flow = flow
        self.forcedTrialLengthDays = nil
    }

    /// The PIR screen launched from the summary's checklist row.
    func pirLaunchScreen() -> AnyView {
        AnyView(
            SubscriptionOnboardingProtectionOverviewView(
                content: .pir,
                title: flow.title(for: .pir),
                navigationButton: .close { flow.isPresentingPIR = false },
                onLaunch: PIRDestinationView(content: flow.pirScreen()))
                .subscriptionOnboardingNavigationContainer())
    }

    func screen(for section: SubscriptionOnboardingSection) -> AnyView {
        AnyView(content(for: section)
            .onFirstAppear { reportShown(section) })
    }

    /// `.vpnTips` is bundled with `.vpnWidget` and shares its pixel name — firing here too would
    /// double-count a single "vpn_widget shown" impression.
    func reportShown(_ section: SubscriptionOnboardingSection) {
        guard section != .vpnTips else { return }
        flow.instrumentation.stepShown(section)
    }

    private func content(for section: SubscriptionOnboardingSection) -> AnyView {
        let title = flow.title(for: section)
        let navigationButton = flow.navigationButton(for: section)

        switch section {
        case .orderConfirmation:
            let onNext = { flow.sectionDidRequestAdvance() }
            let viewModel: SubscriptionOnboardingOrderConfirmationViewModel
            if let forcedTrialLengthDays {
                viewModel = .forcingFreeTrial(lengthInDays: forcedTrialLengthDays, onNext: onNext)
            } else {
                viewModel = SubscriptionOnboardingOrderConfirmationViewModel(onNext: onNext)
            }
            return AnyView(SubscriptionOnboardingOrderConfirmationView(
                viewModel: viewModel,
                navigationButton: navigationButton))

        case .welcome:
            return AnyView(SubscriptionOnboardingWelcomeView(
                navigationButton: navigationButton,
                features: flow.progress.checklist,
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

        case .vpnTips:
            return AnyView(SubscriptionOnboardingVPNTipsView(
                title: title,
                navigationButton: navigationButton,
                onNext: {
                    flow.sectionDidComplete(.vpnTips)
                    flow.sectionDidRequestAdvance()
                }))

        case .idtr:
            return AnyView(SubscriptionOnboardingProtectionOverviewView(
                content: .idtr,
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
                onPIRPresentationChanged: { flow.reportPIRPresentation($0) },
                onNext: { flow.finish() }))

        case .pir:
            // `.pir` is excluded from `activationSections`, so it never enters `path` and this is unreachable.
            assertionFailure("`.pir` should not be pushed as a navigable section")
            return AnyView(EmptyView())
        }
    }
}

// MARK: - Debug Menu

extension SubscriptionOnboardingViewFactory {
    init(flow: SubscriptionOnboardingFlowViewModel, forcedTrialLengthDays: Int?) {
        self.flow = flow
        self.forcedTrialLengthDays = forcedTrialLengthDays
    }
}

// MARK: - PIR destination

/// The pushed PIR screen's default back button, with its icon swapped to an X.
private struct PIRDestinationView<Content: View>: View {
    let content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                    }
                    .accessibilityLabel(UserText.subscriptionOnboardingCloseButtonAccessibilityLabel)
                }
            }
    }
}
