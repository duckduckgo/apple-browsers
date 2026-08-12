//
//  SubscriptionOnboardingProgressView.swift
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

struct SubscriptionOnboardingProgressView: View {

    /// Where the screen is shown, not what state the customer is in
    enum Variant {
        /// The flow's own progress screen.
        case summary
        /// Shown before handing over to a Duck.ai chat.
        case duckAIInterstitial
    }

    private enum Metrics {
        static let completeHeroAnimation = "subscription-hero"
    }

    private let variant: Variant
    private let progress: SubscriptionOnboardingProgress
    private let title: String?
    private let navigationButton: SubscriptionOnboardingNavigationButton?
    private let onSelectItem: ((SubscriptionOnboardingChecklistItem) -> Void)?
    private let onPIRPresentationChanged: ((Bool) -> Void)?
    private let onNext: () -> Void

    @ObservedObject private var pirLaunch: SubscriptionOnboardingPIRLaunchState

    @State private var completedItems: Set<SubscriptionOnboardingChecklistItem>

    @State private var didTriggerConfetti = false

    @MainActor
    init(variant: Variant = .summary,
         progress: SubscriptionOnboardingProgress,
         pirLaunch: SubscriptionOnboardingPIRLaunchState? = nil,
         title: String? = nil,
         navigationButton: SubscriptionOnboardingNavigationButton? = nil,
         onSelectItem: ((SubscriptionOnboardingChecklistItem) -> Void)? = nil,
         onPIRPresentationChanged: ((Bool) -> Void)? = nil,
         onNext: @escaping () -> Void) {
        self.variant = variant
        self.progress = progress
        self.onPIRPresentationChanged = onPIRPresentationChanged
        _pirLaunch = ObservedObject(wrappedValue: pirLaunch ?? SubscriptionOnboardingPIRLaunchState())
        _completedItems = State(initialValue: progress.completedItems)
        self.title = title
        self.navigationButton = navigationButton
        self.onSelectItem = onSelectItem
        self.onNext = onNext
    }

    var body: some View {
        SubscriptionOnboardingBaseView(
            title: title,
            navigationButton: navigationButton,
            header: header,
            footer: footer,
            declaresNavigationChrome: variant != .duckAIInterstitial) {
            SubscriptionOnboardingProgressCardView(percentage: percentage,
                                                   items: progress.checklistItems,
                                                   completedItems: completedItems,
                                                   onSelect: onSelectItem)
        }
        .overlay {
            if didTriggerConfetti {
                ConfettiView()
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: pirLaunch.isPresentingPIR) { isPresenting in
            if !isPresenting {
                refresh()
            }
            onPIRPresentationChanged?(isPresenting)
        }
    }

    private var percentage: Int {
        SubscriptionOnboardingChecklistItem.completionPercentage(completed: completedItems,
                                                                checklist: progress.checklistItems)
    }

    private func refresh() {
        completedItems = progress.completedItems

        guard shouldCelebrate, !didTriggerConfetti else { return }
        didTriggerConfetti = true
    }
}

// MARK: - Copy

private extension SubscriptionOnboardingProgressView {

    /// Only a fully complete checklist celebrates
    var shouldCelebrate: Bool {
        variant != .duckAIInterstitial && percentage >= 100
    }

    var header: SubscriptionOnboardingHeaderView {
        SubscriptionOnboardingHeaderView(visual: headerVisual, title: headerTitle, explanation: headerExplanation)
    }

    /// The Duck.ai hand-off has no footer
    var footer: SubscriptionOnboardingFooter? {
        switch variant {
        case .duckAIInterstitial:
            return nil
        case .summary:
            return .single(.init(UserText.subscriptionOnboardingProgressDoneButton, action: onNext))
        }
    }

    /// Complete state shows the animated hero; Duck.ai hand-off shows Duck.ai's mark.
    var headerVisual: Graphic {
        switch variant {
        case .summary:
            return shouldCelebrate ? .lottie(name: Metrics.completeHeroAnimation) : .image(Image(.subscriptionCheckFeature128))
        case .duckAIInterstitial: return .image(Image(.onboardingDuckAI128))
        }
    }

    var headerTitle: String {
        switch variant {
        case .summary:
            return shouldCelebrate ? UserText.subscriptionOnboardingProgressCompleteTitle : UserText.subscriptionOnboardingProgressTitle
        case .duckAIInterstitial: return UserText.subscriptionOnboardingProgressTitle
        }
    }

    /// `nil` for the complete state
    var headerExplanation: String? {
        switch variant {
        case .summary: return shouldCelebrate ? nil : UserText.subscriptionOnboardingProgressExplanation
        case .duckAIInterstitial: return UserText.subscriptionOnboardingProgressDuckAIExplanation
        }
    }
}

#if DEBUG

private struct SubscriptionOnboardingProgressViewPreview: View {
    let variant: SubscriptionOnboardingProgressView.Variant
    let completedItems: Set<SubscriptionOnboardingChecklistItem>

    var body: some View {
        SubscriptionOnboardingProgressView(
            variant: variant,
            progress: SubscriptionOnboardingProgress(completedItems: completedItems),
            navigationButton: .close({}),
            onSelectItem: { _ in },
            onNext: {})
            .subscriptionOnboardingNavigationContainer()
            .graphicLottieRenderer(.app)
    }
}

#Preview("Completion — 100%") {
    RebrandedPreview {
        SubscriptionOnboardingProgressViewPreview(variant: .summary,
                                                  completedItems: Set(SubscriptionOnboardingChecklistItem.allCases))
    }
}

// 80% is the most the flow itself reaches: every step but PIR, which is started from the checklist.
#Preview("Summary — 80%") {
    RebrandedPreview {
        SubscriptionOnboardingProgressViewPreview(variant: .summary,
                                                  completedItems: [.vpn, .widget, .idtr, .duckAI])
    }
}

#Preview("Duck.ai interstitial") {
    RebrandedPreview {
        SubscriptionOnboardingProgressViewPreview(variant: .duckAIInterstitial,
                                                  completedItems: [.vpn, .widget, .idtr, .duckAI])
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingProgressViewPreview(variant: .summary,
                                                  completedItems: Set(SubscriptionOnboardingChecklistItem.allCases))
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingProgressViewPreview(variant: .summary,
                                                  completedItems: [.vpn, .idtr, .duckAI])
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
