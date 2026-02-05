//
//  RebrandedContextualOnboardingDialogs.swift
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
import Onboarding
import MetricBuilder

// MARK: - Try Anonymous Search

extension OnboardingRebranding {

    struct OnboardingTrySearchDialog: View {
        @Environment(\.verticalSizeClass) private var vSizeClass
        @Environment(\.horizontalSizeClass) private var hSizeClass

        var title = UserText.Onboarding.ContextualOnboarding.onboardingTryASearchTitle
        var message = UserText.Onboarding.ContextualOnboarding.onboardingTryASearchMessage
        let viewModel: OnboardingSearchSuggestionsViewModel
        let onManualDismiss: () -> Void

        var body: some View {
            ScrollView(.vertical, showsIndicators: false) {
                OnboardingBubbleView.withDismissButton(tailPosition: nil, onDismiss: onManualDismiss) {
                    OnboardingRebranding.ContextualDaxDialogContent(
                        orientation: DynamicMetrics.dialogOrientation.build(v: vSizeClass, h: hSizeClass),
                        title: title,
                        message: message.attributed
                    ) {
                        OnboardingRebranding.ContextualOnboardingListView(list: viewModel.itemsList, action: viewModel.listItemPressed)
                    }
                }
                .fixedSize()
                .padding()
            }
        }
    }

}

private extension OnboardingRebranding.OnboardingTrySearchDialog {

    enum DynamicMetrics {
        static let dialogOrientation: MetricBuilder = MetricBuilder<OnboardingRebranding.ContextualDaxDialogOrientation>(default: .verticalStack)
            .iPhone(portrait: .verticalStack, landscape: .horizontalStack(alignment: .top))
            .iPad(.horizontalStack(alignment: .top))
    }

}

// MARK: - Previews

#Preview("Onboarding TrySearchDialog - Light") {
    ZStack {
        Color.white.ignoresSafeArea()

        OnboardingRebranding.OnboardingTrySearchDialog(
            viewModel: .init(suggestedSearchesProvider: OnboardingSuggestedSearchesProvider()),
            onManualDismiss: {}
        )
        .padding()
        .applyOnboardingTheme(.rebranding2026, stepProgressTheme: .rebranding2026)
    }
    .preferredColorScheme(.light)
}

#Preview("Onboarding TrySearchDialog - Dark") {
    ZStack {
        Color(red: 43/255, green: 85/255, blue: 202/255).ignoresSafeArea()

        OnboardingRebranding.OnboardingTrySearchDialog(
            viewModel: .init(suggestedSearchesProvider: OnboardingSuggestedSearchesProvider()),
            onManualDismiss: {}
        )
        .padding()
        .applyOnboardingTheme(.rebranding2026, stepProgressTheme: .rebranding2026)
    }
    .preferredColorScheme(.dark)
}
