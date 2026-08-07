//
//  SubscriptionOnboardingPIRView.swift
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

/// Personal Information Removal section screen.
struct SubscriptionOnboardingPIRView: View {
    private let title: String?
    private let navigationButton: SubscriptionOnboardingNavigationButton?
    private let activateButton: SubscriptionOnboardingFooterButton

    init(title: String? = nil,
         navigationButton: SubscriptionOnboardingNavigationButton? = nil,
         onStart: @escaping () -> Void) {
        self.title = title
        self.navigationButton = navigationButton
        self.activateButton = .init(UserText.subscriptionOnboardingActivateButton, action: onStart)
    }

    /// Pushes `destination` so PIR opens on its own stack.
    init<Destination: View>(title: String? = nil,
                            navigationButton: SubscriptionOnboardingNavigationButton? = nil,
                            push destination: Destination) {
        self.title = title
        self.navigationButton = navigationButton
        self.activateButton = .init(UserText.subscriptionOnboardingActivateButton, push: destination)
    }

    var body: some View {
        SubscriptionOnboardingBaseView(
            title: title,
            navigationButton: navigationButton,
            header: SubscriptionOnboardingHeaderView(content: .pir),
            footer: footer) {
            SubscriptionOnboardingInfoView(content: .pir)
        }
    }

    private var footer: SubscriptionOnboardingFooter {
        .single(activateButton)
    }
}

#if DEBUG

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingPIRView(navigationButton: .back({}), onStart: {})
            .subscriptionOnboardingNavigationContainer()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingPIRView(navigationButton: .back({}), onStart: {})
            .subscriptionOnboardingNavigationContainer()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingPIRView(navigationButton: .back({}), onStart: {})
            .subscriptionOnboardingNavigationContainer()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
