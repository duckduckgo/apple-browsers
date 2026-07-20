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

/// The "Add DuckDuckGo VPN Widget to Your Home Screen" screen, reached from the VPN activation "Next" (or
/// the "Skip" shown after a declined permission prompt). Reuses `WidgetEducationContentView` (the shared
/// numbered steps extracted from `WidgetEducationView`) inside the onboarding page chrome, with a single
/// "Got it" button that continues to the VPN tips carousel.
struct SubscriptionOnboardingVPNWidgetEducationView: View {
    /// The "Step X of Y" indicator is owned by the flow (a later stage), so it is passed in; nil hides it.
    var title: String? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubscriptionOnboardingBaseView(
            title: title,
            navigationButton: .back({ dismiss() }),
            header: SubscriptionOnboardingHeaderView(title: UserText.subscriptionOnboardingVPNWidgetEducationTitle),
            footer: .single(.init(UserText.subscriptionOnboardingVPNWidgetEducationGotItButton,
                                           push: SubscriptionOnboardingVPNTipsView(title: title)))) {
            WidgetEducationContentView(
                thirdParagraphText: UserText.addVPNWidgetSettingsThirdParagraph,
                thirdParagraphDetail: .image(
                    Image(.widgetEducationVPNWidgetExample),
                    maxWidth: 164,
                    horizontalOffset: -7,
                    dropsShadow: true))
        }
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
