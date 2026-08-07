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

/// Progress screen wrapping ``SubscriptionOnboardingProgressCardView``. Ends in complete or summary state, and briefly shows before Duck.ai chat opens.
struct SubscriptionOnboardingProgressView: View {

    /// Where in the flow the screen is being shown, which fixes its hero, copy, footer and celebration.
    enum Variant {
        /// Every step is done. Always at 100%, and the only variant that celebrates.
        case completion
        /// The end of the flow with steps still outstanding — the common case, since the flow itself tops
        /// out at 80% (PIR is a checklist item but not a step).
        case summary
        /// Shown before handing over to a Duck.ai chat, telling the customer how to come back and finish.
        case duckAIInterstitial
    }

    private enum Metrics {
        /// Lottie played by the hero when everything is done.
        static let completeHeroAnimation = "subscription-hero"
    }

    private let variant: Variant
    private let items: [SubscriptionOnboardingChecklistItem]
    /// Re-read on appear rather than fixed at construction: PIR is completed in Data Broker Protection, so
    /// coming back from it has to show the customer the state they just earned.
    private let readProgress: () -> (percentage: Int, completedItems: Set<SubscriptionOnboardingChecklistItem>)

    @State private var percentage: Int
    @State private var completedItems: Set<SubscriptionOnboardingChecklistItem>
    private let title: String?
    private let navigationButton: SubscriptionOnboardingNavigationButton?
    private let onSelectItem: ((SubscriptionOnboardingChecklistItem) -> Void)?
    private let onDone: () -> Void

    /// Latches on the first appearance that qualifies, so the burst plays once and isn't re-triggered by a
    /// body re-evaluation or by returning to the screen.
    @State private var didTriggerConfetti = false

    init(variant: Variant = .summary,
         percentage: Int,
         items: [SubscriptionOnboardingChecklistItem] = SubscriptionOnboardingChecklistItem.allCases,
         completedItems: Set<SubscriptionOnboardingChecklistItem>,
         title: String? = nil,
         navigationButton: SubscriptionOnboardingNavigationButton? = nil,
         onSelectItem: ((SubscriptionOnboardingChecklistItem) -> Void)? = nil,
         readProgress: (() -> (percentage: Int, completedItems: Set<SubscriptionOnboardingChecklistItem>))? = nil,
         onDone: @escaping () -> Void) {
        self.variant = variant
        self.items = items
        let initialProgress = (percentage: percentage, completedItems: completedItems)
        self.readProgress = readProgress ?? { initialProgress }
        _percentage = State(initialValue: percentage)
        _completedItems = State(initialValue: completedItems)
        self.title = title
        self.navigationButton = navigationButton
        self.onSelectItem = onSelectItem
        self.onDone = onDone
    }

    var body: some View {
        SubscriptionOnboardingBaseView(
            title: title,
            navigationButton: navigationButton,
            header: header,
            footer: footer,
            // The Duck.ai hand-off renders this page as an overlay on the picker, which owns the bar.
            declaresNavigationChrome: variant != .duckAIInterstitial) {
            SubscriptionOnboardingProgressCardView(percentage: percentage,
                                                   items: items,
                                                   completedItems: completedItems,
                                                   onSelect: onSelectItem)
        }
        .overlay {
            if didTriggerConfetti {
                ConfettiView()
            }
        }
        .onAppear {
            let progress = readProgress()
            percentage = progress.percentage
            completedItems = progress.completedItems

            guard shouldCelebrate, !didTriggerConfetti else { return }
            didTriggerConfetti = true
        }
    }
}

// MARK: - Copy

private extension SubscriptionOnboardingProgressView {

    /// Only a fully complete flow celebrates. Driven by the live percentage, not the variant fixed at
    /// construction, so completing PIR and coming back still earns the burst.
    var shouldCelebrate: Bool {
        variant != .duckAIInterstitial && percentage >= 100
    }

    var header: SubscriptionOnboardingHeaderView {
        SubscriptionOnboardingHeaderView(visual: headerVisual, title: headerTitle, explanation: headerExplanation)
    }

    /// The Duck.ai hand-off has no footer — it is on its way into a chat, so there is nothing to dismiss.
    var footer: SubscriptionOnboardingFooter? {
        switch variant {
        case .duckAIInterstitial:
            return nil
        case .completion, .summary:
            return .single(.init(UserText.subscriptionOnboardingProgressDoneButton, action: onDone))
        }
    }

    /// Complete state shows the animated hero (as a reward); Duck.ai hand-off shows Duck.ai's mark. The host must inject a `graphicLottieRenderer`.
    var headerVisual: Graphic {
        switch variant {
        case .completion, .summary:
            return shouldCelebrate ? .lottie(name: Metrics.completeHeroAnimation) : .image(Image(.subscriptionCheckFeature128))
        case .duckAIInterstitial: return .image(Image(.onboardingDuckAI128))
        }
    }

    var headerTitle: String {
        switch variant {
        case .completion, .summary:
            return shouldCelebrate ? UserText.subscriptionOnboardingProgressCompleteTitle : UserText.subscriptionOnboardingProgressTitle
        case .duckAIInterstitial: return UserText.subscriptionOnboardingProgressTitle
        }
    }

    /// `nil` for the complete state — its title stands alone, and the header omits an absent explanation
    /// rather than leaving a gap.
    var headerExplanation: String? {
        switch variant {
        case .completion, .summary: return shouldCelebrate ? nil : UserText.subscriptionOnboardingProgressExplanation
        case .duckAIInterstitial: return UserText.subscriptionOnboardingProgressDuckAIExplanation
        }
    }
}

#if DEBUG

private struct SubscriptionOnboardingProgressViewPreview: View {
    let variant: SubscriptionOnboardingProgressView.Variant
    let percentage: Int
    let completedItems: Set<SubscriptionOnboardingChecklistItem>

    var body: some View {
        SubscriptionOnboardingProgressView(
            variant: variant,
            percentage: percentage,
            completedItems: completedItems,
            navigationButton: .close({}),
            onSelectItem: { _ in },
            onDone: {})
            .subscriptionOnboardingNavigationContainer()
            .graphicLottieRenderer(SubscriptionOnboardingLottieRenderer.shared)
    }
}

#Preview("Completion — 100%") {
    RebrandedPreview {
        SubscriptionOnboardingProgressViewPreview(variant: .completion,
                                                  percentage: 100,
                                                  completedItems: Set(SubscriptionOnboardingChecklistItem.allCases))
    }
}

// 80% is the most the flow itself reaches: every step but PIR, which is started from the checklist.
#Preview("Summary — 80%") {
    RebrandedPreview {
        SubscriptionOnboardingProgressViewPreview(variant: .summary,
                                                  percentage: 80,
                                                  completedItems: [.vpn, .widget, .idtr, .duckAI])
    }
}

#Preview("Duck.ai interstitial") {
    RebrandedPreview {
        SubscriptionOnboardingProgressViewPreview(variant: .duckAIInterstitial,
                                                  percentage: 80,
                                                  completedItems: [.vpn, .widget, .idtr, .duckAI])
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingProgressViewPreview(variant: .completion,
                                                  percentage: 100,
                                                  completedItems: Set(SubscriptionOnboardingChecklistItem.allCases))
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingProgressViewPreview(variant: .summary,
                                                  percentage: 60,
                                                  completedItems: [.vpn, .idtr, .duckAI])
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
