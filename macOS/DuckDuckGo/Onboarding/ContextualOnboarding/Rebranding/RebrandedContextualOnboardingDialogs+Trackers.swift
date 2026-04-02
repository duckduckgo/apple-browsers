//
//  RebrandedContextualOnboardingDialogs+Trackers.swift
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

// MARK: - Trackers Blocked

extension OnboardingRebranding {

    struct OnboardingTrackersBlockedDialog: View {
        let cta = UserText.ContextualOnboarding.onboardingGotItButton

        @State private var showNextScreen: Bool = false

        let shouldFollowUp: Bool
        let message: NSAttributedString
        let blockedTrackersCTAAction: () -> Void
        let viewModel: OnboardingFireButtonDialogViewModel
        let onManualDismiss: () -> Void

        var body: some View {
            DaxDialogView(logoPosition: .left, onManualDismiss: onManualDismiss) {
                VStack {
                    if showNextScreen {
                        OnboardingFireDialogContent(viewModel: viewModel)
                    } else {
                        Onboarding.ContextualDaxDialogContent(
                            orientation: .horizontalStack(alignment: .center),
                            message: message,
                            messageFont: OnboardingDialogsContants.messageFont,
                            customActionView: AnyView(
                                OnboardingPrimaryCTAButton(title: cta) {
                                    blockedTrackersCTAAction()
                                    if shouldFollowUp {
                                        withAnimation {
                                            showNextScreen = true
                                        }
                                    }
                                }
                            )
                        )
                    }
                }
            }
            .padding()
        }
    }

}
