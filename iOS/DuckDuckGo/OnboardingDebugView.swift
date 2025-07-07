//
//  OnboardingDebugView.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Core

struct OnboardingDebugView: View {

    @StateObject private var viewModel = OnboardingDebugViewModel()
    @State private var isShowingResetDaxDialogsAlert = false

    private let newOnboardingIntroStartAction: () -> Void

    init(onNewOnboardingIntroStartAction: @escaping () -> Void) {
        newOnboardingIntroStartAction = onNewOnboardingIntroStartAction
    }

    var body: some View {
        List {
            Section {
                Button(action: {
                    viewModel.resetDaxDialogs()
                    isShowingResetDaxDialogsAlert = true
                }, label: {
                    Text(verbatim: "Reset Dax Dialogs State")
                })
                .alert(isPresented: $isShowingResetDaxDialogsAlert, content: {
                    Alert(title: Text(verbatim: "Dax Dialogs reset"), dismissButton: .cancel(Text(verbatim: "Done")))
                })
            }

            Section {
                Picker(
                    selection: $viewModel.onboardingUserType,
                    content: {
                        ForEach(OnboardingUserType.allCases) { state in
                            Text(verbatim: state.description).tag(state)
                        }
                    },
                    label: {
                        Text(verbatim: "Type:")
                    }
                )
            } header: {
                Text(verbatim: "Onboarding User Type")
            }

            Section {
                Button(action: newOnboardingIntroStartAction, label: {
                    Text(verbatim: "Preview Onboarding Intro - \(viewModel.onboardingUserType.description)")
                })
            }
        }
    }
}

final class OnboardingDebugViewModel: ObservableObject {

    @Published var onboardingUserType: OnboardingUserType {
        didSet {
            manager.onboardingUserTypeDebugValue = onboardingUserType
        }
    }

    private let manager: OnboardingNewUserProviderDebugging
    private var settings: DaxDialogsSettings

    init(
        manager: OnboardingNewUserProviderDebugging = OnboardingManager(),
        settings: DaxDialogsSettings = DefaultDaxDialogsSettings()
    ) {
        self.manager = manager
        self.settings = settings
        onboardingUserType = manager.onboardingUserTypeDebugValue
    }

    func resetDaxDialogs() {
        // Remove a debug setting that internal users may have set in the past and could not remove:
        UserDefaults().removeObject(forKey: LaunchOptionsHandler.isOnboardingCompleted)

        settings.isDismissed = false
        settings.tryAnonymousSearchShown = false
        settings.tryVisitASiteShown = false
        settings.browsingAfterSearchShown = false
        settings.browsingWithTrackersShown = false
        settings.browsingWithoutTrackersShown = false
        settings.browsingMajorTrackingSiteShown = false
        settings.fireButtonEducationShownOrExpired = false
        settings.fireMessageExperimentShown = false
        settings.fireButtonPulseDateShown = nil
        settings.privacyButtonPulseShown = false
        settings.browsingFinalDialogShown = false
        settings.privacyProPromotionDialogShown = false
    }
}

#Preview {
    OnboardingDebugView(onNewOnboardingIntroStartAction: {})
}

extension OnboardingUserType: Identifiable {
    var id: OnboardingUserType {
        self
    }
}
