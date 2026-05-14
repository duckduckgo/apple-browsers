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
    @State private var isShowingResetOnboardingAlert = false
    @State private var isShowingSubscriptionPromoCooldownAlert = false

    private let newOnboardingIntroStartAction: (OnboardingDebugFlow) -> Void
    @State private var selectedFlow: OnboardingDebugFlow

    init(initialFlow: OnboardingDebugFlow, onNewOnboardingIntroStartAction: @escaping (OnboardingDebugFlow) -> Void) {
        newOnboardingIntroStartAction = onNewOnboardingIntroStartAction
        _selectedFlow = State(initialValue: initialFlow)
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

                Button(action: {
                    viewModel.resetAllOnboarding()
                    isShowingResetOnboardingAlert = true
                }, label: {
                    Text(verbatim: "Reset All Onboarding")
                })
                .alert(isPresented: $isShowingResetOnboardingAlert, content: {
                    Alert(title: Text(verbatim: "All onboarding reset"),
                          message: Text(verbatim: "Kill and relaunch the app to restart onboarding."),
                          dismissButton: .cancel(Text(verbatim: "Done")))
                })
            }

            Section {
                Button(action: {
                    viewModel.markSubscriptionPromoCooldownPassed()
                    isShowingSubscriptionPromoCooldownAlert = true
                }, label: {
                    Text(verbatim: "Set Subscription Promo Cooldown Passed")
                })
                .alert(isPresented: $isShowingSubscriptionPromoCooldownAlert, content: {
                    Alert(title: Text(verbatim: "Subscription promo cooldown set"), dismissButton: .cancel(Text(verbatim: "Done")))
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
                Picker(
                    selection: $selectedFlow,
                    content: {
                        ForEach(OnboardingDebugFlow.allCases) { flow in
                            Text(verbatim: flow.description).tag(flow)
                        }
                    },
                    label: {
                        Text(verbatim: "Flow:")
                    }
                )
            } header: {
                Text(verbatim: "Onboarding Flow")
            }

            Section {
                Button(action: { newOnboardingIntroStartAction(selectedFlow) }, label: {
                    Text(verbatim: "Preview Onboarding \(selectedFlow.description) Intro - \(viewModel.onboardingUserType.description)")
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
    private let tutorialSettings: TutorialSettings
    private let statisticsStore: StatisticsUserDefaults

    init(
        manager: OnboardingNewUserProviderDebugging = OnboardingManager(),
        settings: DaxDialogsSettings = DefaultDaxDialogsSettings(),
        tutorialSettings: TutorialSettings = DefaultTutorialSettings(),
        statisticsStore: StatisticsUserDefaults = StatisticsUserDefaults()
    ) {
        self.manager = manager
        self.settings = settings
        self.tutorialSettings = tutorialSettings
        self.statisticsStore = statisticsStore
        onboardingUserType = manager.onboardingUserTypeDebugValue
    }

    func resetAllOnboarding() {
        tutorialSettings.hasSeenOnboarding = false
        resetDaxDialogs()
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
        settings.subscriptionPromotionDialogShown = false
        tutorialSettings.hasSkippedOnboarding = false
    }

    func markSubscriptionPromoCooldownPassed() {
        statisticsStore.installDate = Calendar.current.date(byAdding: .day,
                                                            value: -SubscriptionPromoCoordinator.cooldownDays,
                                                            to: Date())
    }
}

extension OnboardingUserType: Identifiable {
    var id: OnboardingUserType {
        self
    }
}

enum OnboardingDebugFlow: String, CaseIterable, CustomStringConvertible, Identifiable {
    case rebranding
    case legacy

    var id: OnboardingDebugFlow { self }

    var description: String {
        switch self {
        case .rebranding:
            return "Rebranding"
        case .legacy:
            return "Original (Legacy)"
        }
    }

    var isRebranding: Bool {
        self == .rebranding
    }
}

#Preview {
    OnboardingDebugView(initialFlow: .legacy, onNewOnboardingIntroStartAction: { _ in })
}
