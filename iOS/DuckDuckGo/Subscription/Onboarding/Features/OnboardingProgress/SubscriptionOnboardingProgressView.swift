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

/// Supplies the checklist this screen renders. Implemented by ``SubscriptionOnboardingFlowViewModel``, so the
/// screen reads progress for itself on appear instead of showing whatever its builder captured — PIR
/// completes in Data Broker Protection, and coming back has to show the state the customer just earned.
@MainActor
protocol SubscriptionOnboardingProgressProviding {
    var checklist: [SubscriptionOnboardingChecklistItem] { get }
    var completedItems: Set<SubscriptionOnboardingChecklistItem> { get }
}

struct SubscriptionOnboardingProgressView: View {

    /// Where the screen is shown, not what state the customer is in — that's read from `percentage`.
    enum Variant {
        /// The flow's own progress screen.
        case summary
        /// Shown before handing over to a Duck.ai chat.
        case duckAIInterstitial
    }

    /// Checklist state; `percentage` is derived so it never contradicts the shown items.
    struct Progress {
        /// This customer's checklist, four items if PIR is unreachable, to prevent showing an impossible fifth row.
        var items: [SubscriptionOnboardingChecklistItem] = SubscriptionOnboardingChecklistItem.allCases
        var completedItems: Set<SubscriptionOnboardingChecklistItem>

        var percentage: Int {
            SubscriptionOnboardingChecklistItem.completionPercentage(completed: completedItems, checklist: items)
        }

        static let none = Progress(completedItems: [])
    }

    private enum Metrics {
        static let completeHeroAnimation = "subscription-hero"
    }

    private let variant: Variant
    /// Present when the screen can read progress for itself; `nil` for a fixed `progress` value.
    private let source: SubscriptionOnboardingProgressProviding?

    @State private var progress: Progress
    private let title: String?
    private let navigationButton: SubscriptionOnboardingNavigationButton?
    private let onSelectItem: ((SubscriptionOnboardingChecklistItem) -> Void)?
    private let onNext: () -> Void

    @State private var didTriggerConfetti = false

    /// Seeded from `source` rather than left to `onAppear`, so the first frame is never a stale 0%.
    @MainActor
    init(variant: Variant = .summary,
         progress: Progress = .none,
         source: SubscriptionOnboardingProgressProviding? = nil,
         title: String? = nil,
         navigationButton: SubscriptionOnboardingNavigationButton? = nil,
         onSelectItem: ((SubscriptionOnboardingChecklistItem) -> Void)? = nil,
         onNext: @escaping () -> Void) {
        self.variant = variant
        self.source = source
        _progress = State(initialValue: Self.progress(from: source) ?? progress)
        self.title = title
        self.navigationButton = navigationButton
        self.onSelectItem = onSelectItem
        self.onNext = onNext
    }

    @MainActor
    private static func progress(from source: SubscriptionOnboardingProgressProviding?) -> Progress? {
        source.map { Progress(items: $0.checklist, completedItems: $0.completedItems) }
    }

    var body: some View {
        SubscriptionOnboardingBaseView(
            title: title,
            navigationButton: navigationButton,
            header: header,
            footer: footer,
            // The Duck.ai hand-off renders this page as an overlay on the picker, which owns the bar.
            declaresNavigationChrome: variant != .duckAIInterstitial) {
            SubscriptionOnboardingProgressCardView(percentage: progress.percentage,
                                                   items: progress.items,
                                                   completedItems: progress.completedItems,
                                                   onSelect: onSelectItem)
        }
        .overlay {
            if didTriggerConfetti {
                ConfettiView()
            }
        }
        .onAppear {
            if let read = Self.progress(from: source) {
                progress = read
            }

            guard shouldCelebrate, !didTriggerConfetti else { return }
            didTriggerConfetti = true
        }
    }
}

// MARK: - Copy

private extension SubscriptionOnboardingProgressView {

    /// Only a fully complete checklist celebrates, and it is read from the live percentage, so completing
    /// PIR and coming back still earns the burst.
    var shouldCelebrate: Bool {
        variant != .duckAIInterstitial && progress.percentage >= 100
    }

    var header: SubscriptionOnboardingHeaderView {
        SubscriptionOnboardingHeaderView(visual: headerVisual, title: headerTitle, explanation: headerExplanation)
    }

    /// The Duck.ai hand-off has no footer — it is on its way into a chat, so there is nothing to dismiss.
    var footer: SubscriptionOnboardingFooter? {
        switch variant {
        case .duckAIInterstitial:
            return nil
        case .summary:
            return .single(.init(UserText.subscriptionOnboardingProgressDoneButton, action: onNext))
        }
    }

    /// Complete state shows the animated hero (as a reward); Duck.ai hand-off shows Duck.ai's mark. The host must inject a `graphicLottieRenderer`.
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

    /// `nil` for the complete state — its title stands alone, and the header omits an absent explanation
    /// rather than leaving a gap.
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
            progress: .init(completedItems: completedItems),
            navigationButton: .close({}),
            onSelectItem: { _ in },
            onNext: {})
            .subscriptionOnboardingNavigationContainer()
            .graphicLottieRenderer(SubscriptionOnboardingLottieRenderer.shared)
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
