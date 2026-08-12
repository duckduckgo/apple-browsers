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
    var onComplete: () -> Void = {}
    var onNext: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var isShowingTips = false

    // (TODO|Post-iOS15-Drop): drop the fork and keep the `navigationDestination` branch.
    @ViewBuilder
    var body: some View {
        if #available(iOS 16.0, *) {
            page.navigationDestination(isPresented: $isShowingTips) { tipsScreen }
        } else {
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
        SubscriptionOnboardingVPNTipsView(title: title, onNext: advanceFromTips)
    }

    // (TODO|Post-iOS15-Drop): drop the reset — `NavigationStack` tolerates the overlap.
    /// Deactivates the local tips link *before* the flow pushes its own sibling link: two simultaneously
    /// active `NavigationLink`s in one iOS 15 `NavigationView` break the push.
    private func advanceFromTips() {
        isShowingTips = false
        onNext()
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
