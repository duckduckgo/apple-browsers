//
//  SubscriptionOnboardingIDTRView.swift
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

/// Identity Theft Restoration section screen. No "Learn More" link (this screen is the information) and no activation step (already active with subscription).
struct SubscriptionOnboardingIDTRView: View {
    private let title: String?
    private let navigationButton: SubscriptionOnboardingNavigationButton?
    private let onNext: () -> Void

    init(title: String? = nil,
         navigationButton: SubscriptionOnboardingNavigationButton? = nil,
         onNext: @escaping () -> Void) {
        self.title = title
        self.navigationButton = navigationButton
        self.onNext = onNext
    }

    var body: some View {
        SubscriptionOnboardingBaseView(
            title: title,
            navigationButton: navigationButton,
            header: SubscriptionOnboardingHeaderView(content: .idtr),
            footer: .single(.init(UserText.subscriptionOnboardingActivateButton, action: onNext))) {
            SubscriptionOnboardingInfoView(content: .idtr)
        }
    }
}

#if DEBUG

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingIDTRView(title: "Step 2 of 3", navigationButton: .back({}), onNext: {})
            .subscriptionOnboardingNavigationContainer()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingIDTRView(title: "Step 2 of 3", navigationButton: .back({}), onNext: {})
            .subscriptionOnboardingNavigationContainer()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingIDTRView(title: "Step 2 of 3", navigationButton: .back({}), onNext: {})
            .subscriptionOnboardingNavigationContainer()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
