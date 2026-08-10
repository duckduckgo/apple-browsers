//
//  SubscriptionOnboardingVPNWidgetEducationView.swift
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

/// The widget education screen, reached from the VPN activation "Next" or the "Skip" shown after a denial.
struct SubscriptionOnboardingVPNWidgetEducationView: View {

    var title: String?
    var navigationButton: SubscriptionOnboardingNavigationButton?
    /// Reported when the customer taps "Got it", which is what finishes the widget step.
    var onComplete: () -> Void = {}
    /// Passed through to the tips screen, which is where this section finishes.
    var onNext: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    /// Local because tips is a second level of *this* section rather than a section of its own, so it stays
    /// out of the flow's navigation path. Set only by the "Got it" tap.
    @State private var isShowingTips = false

    /// Forked because "push while this is true" is a different API per OS version, and the iOS 15 one is
    /// unsupported inside a `NavigationStack` — Apple replaced `NavigationLink(isActive:)` with
    /// `navigationDestination(isPresented:)`, and the old form can silently fail to push there.
    @ViewBuilder
    var body: some View {
        if #available(iOS 16.0, *) {
            page.navigationDestination(isPresented: $isShowingTips) { tipsScreen }
        } else {
            // Link beside the page rather than behind it, so a rebuilt page cannot take it down with it.
            ZStack {
                NavigationLink(isActive: $isShowingTips) { tipsScreen } label: { EmptyView() }
                page
            }
        }
    }

    private var page: some View {
        SubscriptionOnboardingBaseView(
            title: title,
            navigationButton: navigationButton ?? .back({ dismiss() }),
            header: SubscriptionOnboardingHeaderView(title: UserText.subscriptionOnboardingVPNWidgetEducationTitle),
            // One tap, two jobs: it finishes the widget step and opens the tips screen. Deliberately not a
            // `push:` footer button — that renders a `NavigationLink`, which gives no tap to hang the
            // completion on and would put it back on the tips screen appearing.
            footer: .single(.init(UserText.subscriptionOnboardingVPNWidgetEducationGotItButton, action: {
                onComplete()
                isShowingTips = true
            }))) {
            WidgetEducationContentView(
                thirdParagraphText: UserText.addVPNWidgetSettingsThirdParagraph,
                thirdParagraphDetail: .image(
                    Image(.widgetEducationVPNWidgetExample),
                    maxWidth: 164,
                    horizontalOffset: -7,
                    dropsShadow: true))
        }
    }

    private var tipsScreen: some View {
        SubscriptionOnboardingVPNTipsView(title: title, onNext: onNext)
    }
}

#if DEBUG

private func widgetEducationPreview() -> some View {
    SubscriptionOnboardingVPNWidgetEducationView(
        title: String(format: UserText.subscriptionOnboardingStepIndicatorFormat, 1, 4))
    .subscriptionOnboardingNavigationContainer()
}

#Preview("Widget education - Light") {
    RebrandedPreview {
        widgetEducationPreview()
    }
}

#Preview("Widget education - Dark") {
    RebrandedPreview {
        widgetEducationPreview()
    }
    .preferredColorScheme(.dark)
}

#Preview("Widget education - Large Text") {
    RebrandedPreview {
        widgetEducationPreview()
    }
    .dynamicTypeSize(.accessibility3)
}

#endif
