//
//  SubscriptionOnboardingSetupCard.swift
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
import DuckUI
import UIComponents
import Persistence

/// The Subscription Settings re-entry card, carrying the current setup `percentage` and a CTA to resume.
struct SubscriptionOnboardingSetupCard: View {
    private enum Metrics {
        static let iconSpacing: CGFloat = 12
        static let titleTextSpacing: CGFloat = 4
        static let buttonTopSpacing: CGFloat = 16
    }

    private let visual: Graphic
    private let progress: SubscriptionOnboardingProgress
    private let session: SubscriptionOnboardingSessionStating
    /// Whether the onboarding flow is on screen over this card.
    private let isPresentingFlow: Bool
    private let onContinue: () -> Void

    @State private var percentage: Int
    @State private var isShowing: Bool

    init(visual: Graphic,
         progress: SubscriptionOnboardingProgress,
         session: SubscriptionOnboardingSessionStating,
         isPresentingFlow: Bool = false,
         onContinue: @escaping () -> Void) {
        self.visual = visual
        self.progress = progress
        self.session = session
        self.isPresentingFlow = isPresentingFlow
        self.onContinue = onContinue

        var seed = progress
        _percentage = State(initialValue: seed.percentage)
        _isShowing = State(initialValue: seed.shouldShowSetupCard(now: Date(), session: session))
    }

    var body: some View {
        Group {
            if isShowing {
                card
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: isPresentingFlow) { isPresenting in
            guard !isPresenting else { return }
            refresh()
        }
    }

    private var card: some View {
        SubscriptionOnboardingCard(
            CardItem(
                icon: CardItemIcon(position: .leading, visual: visual, size: .size40, spacing: Metrics.iconSpacing),
                title: CardItemText(title, font: .headline),
                text: CardItemText(UserText.subscriptionOnboardingSetupCardBody, font: .bodyRegular),
                titleTextSpacing: Metrics.titleTextSpacing),
            style: .borderless) {
                Button(UserText.subscriptionOnboardingSetupCardButton, action: onContinue)
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .padding(.top, Metrics.buttonTopSpacing)
            }
    }

    private var title: String {
        String(format: UserText.subscriptionOnboardingSetupCardTitleFormat, percentage)
    }

    /// Reads progress and decides whether to show, on every appearance
    private func refresh() {
        var progress = self.progress
        percentage = progress.percentage
        isShowing = progress.shouldShowSetupCard(now: Date(), session: session)
    }
}

#if DEBUG

private struct SubscriptionOnboardingSetupCardPreview: View {
    var body: some View {
        ScrollView {
            // PIR unavailable, so the checklist is four items and these read 3/4 and 1/4.
            VStack(spacing: 24) {
                card(completed: [.vpn, .widget, .idtr])
                card(completed: [.vpn])
            }
            .padding()
        }
        .background(Color(designSystemColor: .surfaceTertiary).ignoresSafeArea())
    }

    private func card(completed: Set<SubscriptionOnboardingChecklistItem>) -> some View {
        SubscriptionOnboardingSetupCard(
            visual: .image(Image(.subscription56)),
            progress: SubscriptionOnboardingProgress(completedItems: completed, isPIRAvailable: false),
            session: SubscriptionOnboardingSessionState(),
            onContinue: {})
    }
}

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingSetupCardPreview()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingSetupCardPreview()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingSetupCardPreview()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
