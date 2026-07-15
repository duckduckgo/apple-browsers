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
import Onboarding
import Persistence

struct OnboardingDebugView: View {

    @StateObject private var viewModel = OnboardingDebugViewModel()
    @State private var isShowingResetDaxDialogsAlert = false
    @State private var isShowingResetOnboardingAlert = false
    @State private var isShowingSubscriptionPromoCooldownAlert = false
    @State private var isShowingExistingUserSubscriptionPromoCooldownAlert = false
    @State private var isShowingResetInstallDateAlert = false

    private let newOnboardingIntroStartAction: () -> Void

    init(onNewOnboardingIntroStartAction: @escaping @MainActor () -> Void) {
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

                Button(action: {
                    viewModel.markExistingUserSubscriptionPromoCooldownPassed()
                    isShowingExistingUserSubscriptionPromoCooldownAlert = true
                }, label: {
                    Text(verbatim: "Set Existing User Subscription Promo Cooldown Passed")
                })
                .alert(isPresented: $isShowingExistingUserSubscriptionPromoCooldownAlert, content: {
                    Alert(title: Text(verbatim: "Existing user subscription promo cooldown set"), dismissButton: .cancel(Text(verbatim: "Done")))
                })

                Button(action: {
                    viewModel.resetInstallDateToToday()
                    isShowingResetInstallDateAlert = true
                }, label: {
                    Text(verbatim: "Reset Install Date to Today (Cooldown Not Passed)")
                })
                .alert(isPresented: $isShowingResetInstallDateAlert, content: {
                    Alert(title: Text(verbatim: "Install date reset to today"), dismissButton: .cancel(Text(verbatim: "Done")))
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
                    selection: $viewModel.forcedOnboardingFlowType,
                    content: {
                        Text(verbatim: "Auto-detect (URL evaluator)").tag(Optional<OnboardingFlowType>.none)
                        Text(verbatim: "Default").tag(OnboardingFlowType.default)
                        Text(verbatim: "Duck.ai Tailored").tag(OnboardingFlowType.duckAI)
                    },
                    label: {
                        Text(verbatim: "Flow Type:")
                    }
                )
            } header: {
                Text(verbatim: "Force Onboarding Flow Type")
            } footer: {
                Text(verbatim: "Honoured on next launch by OnboardingManager.configureOnboardingFlow when no flow is already configured. Reset Onboarding above and kill+relaunch the app to apply.")
            }

            Section {
                Button(action: { newOnboardingIntroStartAction() }, label: {
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

    /// Debug override for the resolved onboarding flow type on next launch.
    /// `nil` means "no override — use the real evaluator (URL-based)."
    /// Honoured by `OnboardingManager.configureOnboardingFlow(from:)` only in DEBUG/ALPHA builds.
    @Published var forcedOnboardingFlowType: OnboardingFlowType? {
        didSet {
            appSettings.onboardingFlowType = forcedOnboardingFlowType
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
        forcedOnboardingFlowType = appSettings.onboardingFlowType
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

    func markExistingUserSubscriptionPromoCooldownPassed() {
        statisticsStore.installDate = Calendar.current.date(byAdding: .day,
                                                            value: -SubscriptionPromoExistingUserCoordinator.cooldownDays,
                                                            to: Date())
    }

    func resetInstallDateToToday() {
        statisticsStore.installDate = Date()
    }
}

extension OnboardingUserType: Identifiable {
    var id: OnboardingUserType {
        self
    }
}

#Preview {
    OnboardingDebugView(onNewOnboardingIntroStartAction: { })
}
