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
import Persistence

struct OnboardingDebugView: View {

    @StateObject private var viewModel = OnboardingDebugViewModel()
    @State private var isShowingResetDaxDialogsAlert = false
    @State private var isShowingResetOnboardingAlert = false
    @State private var isShowingSubscriptionPromoCooldownAlert = false

    private let newOnboardingIntroStartAction: (OnboardingDebugFlow) -> Void
    @State private var selectedFlow: OnboardingDebugFlow

    init(initialFlow: OnboardingDebugFlow, onNewOnboardingIntroStartAction: @escaping @MainActor (OnboardingDebugFlow) -> Void) {
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

                Toggle(
                    isOn: $viewModel.forceRestorePromptEligible,
                    label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "Force Restore Prompt Eligible")
                            Text(verbatim: "Sets Returning User and forces the .restoreData intro on next launch.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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

    @Published var forceRestorePromptEligible: Bool {
        didSet {
            appSettings.onboardingForceRestorePromptEligible = forceRestorePromptEligible
            // Restore prompt only shows for returning users — flip the picker so the
            // combination needed to reach Intro (.restoreData) is set from one toggle.
            if forceRestorePromptEligible, onboardingUserType != .returningUser {
                onboardingUserType = .returningUser
            }
        }
    }

    private let manager: OnboardingNewUserProviderDebugging
    private var settings: DaxDialogsSettings
    private let tutorialSettings: TutorialSettings
    private let statisticsStore: StatisticsUserDefaults
    private let userDefaults: UserDefaults
    private var appSettings: OnboardingDebugAppSettings

    /// Keys duplicated here (rather than exposed publicly) so production types don't grow
    /// a debug-only reset surface. Keep in sync with the originals:
    /// - `OnboardingPixelReporter.siteVisitedUserDefaultsKey`
    /// - `OnboardingSearchExperienceProvider` private `String` constants
    private static let siteVisitedUserDefaultsKey = "com.duckduckgo.ios.site-visited"
    private static let didEnableAIChatSearchInputDuringOnboardingKey = "com.duckduckgo.ios.onboarding.didEnableAIChatSearchInputDuringOnboarding"
    private static let didApplyOnboardingChoiceSettingsKey = "com.duckduckgo.ios.onboarding.didApplyOnboardingChoiceSettings"

    init(
        manager: OnboardingNewUserProviderDebugging = OnboardingManager(),
        settings: DaxDialogsSettings = DefaultDaxDialogsSettings(),
        tutorialSettings: TutorialSettings = DefaultTutorialSettings(),
        statisticsStore: StatisticsUserDefaults = StatisticsUserDefaults(),
        userDefaults: UserDefaults = .app,
        appSettings: OnboardingDebugAppSettings = AppDependencyProvider.shared.appSettings
    ) {
        self.manager = manager
        self.settings = settings
        self.tutorialSettings = tutorialSettings
        self.statisticsStore = statisticsStore
        self.userDefaults = userDefaults
        self.appSettings = appSettings
        onboardingUserType = manager.onboardingUserTypeDebugValue
        forceRestorePromptEligible = appSettings.onboardingForceRestorePromptEligible
    }

    func resetAllOnboarding() {
        tutorialSettings.hasSeenOnboarding = false
        // Clear the persisted flow type so the next launch re-evaluates default vs Duck.ai.
        tutorialSettings.onboardingFlowType = nil
        // Drop any resume-step checkpoint left over from a partial onboarding run, and
        // clear the onboarding pixel context (source/flow/variant) so it's re-recorded
        // when the next onboarding run begins. `KeyedStorage` is constructed directly
        // (rather than via `UserDefaults.app.keyedStoring()` whose opaque return type
        // would require iOS 16+ runtime support for parameterized existentials on iOS 15).
        OnboardingResumeCheckpointStore.clearAll(in: KeyedStorage<OnboardingStoringKeys>(storage: UserDefaults.app))
        let sharedPixelsStorage = KeyedStorage<OnboardingSharedPixelsKeys>(storage: UserDefaults.app)
        sharedPixelsStorage.onboardingSource = nil
        sharedPixelsStorage.onboardingFlow = nil
        sharedPixelsStorage.onboardingVariant = nil
        // Forget the Search-vs-Duck.ai choice and the post-onboarding settings flag.
        // `OnboardingSearchExperience` uses `UserDefaults.standard` for these keys.
        UserDefaults.standard.removeObject(forKey: Self.didEnableAIChatSearchInputDuringOnboardingKey)
        UserDefaults.standard.removeObject(forKey: Self.didApplyOnboardingChoiceSettingsKey)
        // Reset the "user already visited a second site" flag used by pixel reporting.
        userDefaults.removeObject(forKey: Self.siteVisitedUserDefaultsKey)
        // Clear the debug override that forces the restore prompt to be eligible.
        forceRestorePromptEligible = false
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
        settings.chatPathVisitSiteSeen = false
        settings.isChatFirstPath = false
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
