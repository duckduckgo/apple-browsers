//
//  SubscriptionOnboardingProtectionOverviewView.swift
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

/// A protection's overview step: its hero, its info content, and one "Activate" CTA.
///
/// IDTR and PIR are this screen with different content. Only the CTA differs: IDTR advances the flow, PIR
/// pushes the Data Broker Protection screen.
struct SubscriptionOnboardingProtectionOverviewView: View {
    private let content: SubscriptionOnboardingInfoContent
    private let title: String?
    private let navigationButton: SubscriptionOnboardingNavigationButton?
    private let activateButton: SubscriptionOnboardingFooterButton

    init(content: SubscriptionOnboardingInfoContent,
         title: String? = nil,
         navigationButton: SubscriptionOnboardingNavigationButton? = nil,
         onNext: @escaping () -> Void) {
        self.content = content
        self.title = title
        self.navigationButton = navigationButton
        self.activateButton = .init(UserText.subscriptionOnboardingActivateButton, action: onNext)
    }

    /// Pushes `onLaunch` on a separate stack rather than advancing the flow.
    init<Destination: View>(content: SubscriptionOnboardingInfoContent,
                            title: String? = nil,
                            navigationButton: SubscriptionOnboardingNavigationButton? = nil,
                            onLaunch destination: Destination) {
        self.content = content
        self.title = title
        self.navigationButton = navigationButton
        self.activateButton = .init(UserText.subscriptionOnboardingActivateButton, push: destination)
    }

    var body: some View {
        SubscriptionOnboardingBaseView(
            title: title,
            navigationButton: navigationButton,
            header: SubscriptionOnboardingHeaderView(content: content),
            footer: .single(activateButton),
            footerBlur: true) {
            SubscriptionOnboardingInfoView(content: content)
        }
    }
}

#if DEBUG

#Preview("IDTR Light") {
    RebrandedPreview {
        SubscriptionOnboardingProtectionOverviewView(content: .idtr,
                                                     title: "Step 2 of 3",
                                                     navigationButton: .back({}),
                                                     onNext: {})
            .subscriptionOnboardingNavigationContainer()
    }
}

#Preview("IDTR Dark") {
    RebrandedPreview {
        SubscriptionOnboardingProtectionOverviewView(content: .idtr,
                                                     title: "Step 2 of 3",
                                                     navigationButton: .back({}),
                                                     onNext: {})
            .subscriptionOnboardingNavigationContainer()
    }
    .preferredColorScheme(.dark)
}

#Preview("IDTR Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingProtectionOverviewView(content: .idtr,
                                                     title: "Step 2 of 3",
                                                     navigationButton: .back({}),
                                                     onNext: {})
            .subscriptionOnboardingNavigationContainer()
    }
    .dynamicTypeSize(.accessibility5)
}

#Preview("PIR Light") {
    RebrandedPreview {
        SubscriptionOnboardingProtectionOverviewView(content: .pir,
                                                     navigationButton: .back({}),
                                                     onNext: {})
            .subscriptionOnboardingNavigationContainer()
    }
}

#Preview("PIR Dark") {
    RebrandedPreview {
        SubscriptionOnboardingProtectionOverviewView(content: .pir,
                                                     navigationButton: .back({}),
                                                     onNext: {})
            .subscriptionOnboardingNavigationContainer()
    }
    .preferredColorScheme(.dark)
}

#Preview("PIR Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingProtectionOverviewView(content: .pir,
                                                     navigationButton: .back({}),
                                                     onNext: {})
            .subscriptionOnboardingNavigationContainer()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
