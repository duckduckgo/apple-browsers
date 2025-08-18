//
//  DefaultBrowserPromptDebugView.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Persistence
import Common
import Core
import BrowserServicesKit
import SetDefaultBrowserCore
import class UIKit.UIApplication

struct DefaultBrowserPromptDebugView: View {
    @ObservedObject private var model: DefaultBrowserPromptDebugViewModel

    init(model: DefaultBrowserPromptDebugViewModel) {
        self.model = model
    }

    var body: some View {
        if model.isFeatureEnabled {
            settingsView
        } else {
            Text(verbatim: "Feature Disabled. Ensure Internal user is On")
        }
    }

    @ViewBuilder
    private var settingsView: some View {
        List {
            Section {
                let log = model.debugLog
                VStack(alignment: .leading) {
                    Text(log.installation)
                    Text(log.activity)
                    Text(log.modal)
                    Text(log.numberOfModalShown)
                    Text(log.inactiveUserModalShown)
                }
            } header: {
                Text(verbatim: "Activity Log")
            }

            Section {
                Picker(
                    selection: $model.defaultBrowserPromptUserType,
                    content: {
                        ForEach(DefaultBrowserPromptUserType.allCases) { userType in
                            Text(verbatim: userType.rawValue).tag(userType)
                        }
                    },
                    label: {
                        Text(verbatim: "Type:")
                    }
                )
            } header: {
                Text(verbatim: "Default Browser Prompt User Type")
            }

            Section {
                DatePicker(selection: $model.currentDate, in: model.currentDate...) {
                    Text(verbatim: "Current Date: \(model.formattedCurrentDate)")
                }
                .datePickerStyle(.compact)
            } header: {
                Text(verbatim: "Simulate Today's Date")
            }

            Section {
                Text(verbatim: "Active Days Count: \(model.activeDaysCount)")
                Button(action: model.incrementActiveDaysCount) {
                    Text(verbatim: "Increment Number of Active Days")
                }
            } header: {
                Text(verbatim: "Number of Active Days")
            } footer: {
                Text(verbatim: "Active Days Will Reset Every Time The Default Browser Prompt Is Shown")
                    .foregroundColor(.red)
            }

            Section {
                Button(action: model.resetAllSettings) {
                    Text(verbatim: "Reset Prompts and Today's Date")
                }
            }
        }
        .disabled(!model.isFeatureEnabled)
        .navigationTitle("Default Browser Prompt")
    }
}

final class DefaultBrowserPromptDebugViewModel: ObservableObject {
    struct DebugLog {
        private(set) var installation: String = ""
        private(set) var activity: String = ""
        private(set) var modal: String = ""
        private(set) var numberOfModalShown: String = ""
        private(set) var inactiveUserModalShown: String = ""
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = .current
        return formatter
    }()

    @Published private(set) var isFeatureEnabled: Bool
    @Published private(set) var activeDaysCount: Int
    @Published private(set) var debugLog: DebugLog = .init()
    @Published var defaultBrowserPromptUserType: DefaultBrowserPromptUserType? {
        didSet {
            guard let defaultBrowserPromptUserType else { return }
            userTypeDebugStore.save(userType: defaultBrowserPromptUserType)
        }
    }
    @Published var currentDate: Date {
        didSet {
            currentDateDebugStore.simulatedTodayDate = currentDate.addingTimeInterval(.hours(1))
            formattedCurrentDate = Self.dateFormatter.string(from: currentDateDebugStore.simulatedTodayDate)
        }
    }
    @Published private(set) var formattedCurrentDate: String

    private let currentDateDebugStore = DefaultBrowserPromptDebugDateProvider()
    private let promptActivityStore: DefaultBrowserPromptActivityKeyValueFilesStore
    private let featureFlagger: DefaultBrowserPromptFeatureFlagAdapter
    private let userActivityStore: DefaultBrowserPromptUserActivityKeyValueFilesStore
    private let localStatisticsStore = StatisticsUserDefaults()
    private let userTypeDebugStore: DefaultBrowserPromptUserTypeStoring

    init(keyValueFilesStore: ThrowingKeyValueStoring, featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger, privacyConfigManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager) {
        userTypeDebugStore = DefaultBrowserPromptUserTypeStore(keyValueFilesStore: keyValueFilesStore)
        promptActivityStore = DefaultBrowserPromptActivityKeyValueFilesStore(keyValueFilesStore: keyValueFilesStore)
        self.featureFlagger = DefaultBrowserPromptFeatureFlagAdapter(featureFlagger: featureFlagger, privacyConfigurationManager: privacyConfigManager)
        userActivityStore = DefaultBrowserPromptUserActivityKeyValueFilesStore(keyValueFilesStore: keyValueFilesStore)

        defaultBrowserPromptUserType = userTypeDebugStore.userType()
        currentDate = currentDateDebugStore.simulatedTodayDate
        formattedCurrentDate = Self.dateFormatter.string(from: currentDateDebugStore.simulatedTodayDate)
        activeDaysCount = userActivityStore.currentActivity().numberOfActiveDays
        isFeatureEnabled = self.featureFlagger.isDefaultBrowserPromptsForActiveUsersFeatureEnabled
        makeDebugLog()
    }

    func incrementActiveDaysCount() {
        let oldActivity = userActivityStore.currentActivity()
        let newActivity = DefaultBrowserPromptUserActivity(numberOfActiveDays: oldActivity.numberOfActiveDays + 1, lastActiveDate: oldActivity.lastActiveDate)
        userActivityStore.save(newActivity)
        activeDaysCount = userActivityStore.currentActivity().numberOfActiveDays
        makeDebugLog()
    }

    func resetAllSettings() {
        currentDateDebugStore.reset()
        promptActivityStore.isPromptPermanentlyDismissed = false
        promptActivityStore.lastModalShownDate = nil
        promptActivityStore.modalShownOccurrences = 0
        promptActivityStore.hasInactiveModalShown = false
        userActivityStore.save(DefaultBrowserPromptUserActivity(numberOfActiveDays: 0, lastActiveDate: currentDateDebugStore.simulatedTodayDate))
        updateUI()
    }

    private func updateUI() {
        defaultBrowserPromptUserType = userTypeDebugStore.userType()
        currentDate = currentDateDebugStore.simulatedTodayDate
        activeDaysCount = userActivityStore.currentActivity().numberOfActiveDays
        isFeatureEnabled = self.featureFlagger.isDefaultBrowserPromptsForActiveUsersFeatureEnabled
        makeDebugLog()
    }

    private func makeDebugLog() {

        func nextModalMessage() -> String {
            guard !promptActivityStore.isPromptPermanentlyDismissed else {
                return "Modal Permanently Dismissed. No More Modals Will Show."
            }

            let message: String
            if promptActivityStore.hasSeenFirstModal {
                if userTypeDebugStore.userType()?.isNewOrReturningUser == true && !promptActivityStore.hasSeenSecondModal {
                    let numberOfActiveDays = featureFlagger.defaultBrowserPromptFeatureSettings[DefaultBrowserPromptFeatureSettings.secondActiveModalDelayDays.rawValue] as? Int ?? DefaultBrowserPromptFeatureSettings.secondActiveModalDelayDays.defaultValue
                    message = "Next Modal Will Show After \(numberOfActiveDays) Active Days"
                } else if userTypeDebugStore.userType()?.isNewOrReturningUser == true && promptActivityStore.hasSeenSecondModal {
                    let numberOfActiveDays = featureFlagger.defaultBrowserPromptFeatureSettings[DefaultBrowserPromptFeatureSettings.subsequentActiveModalRepeatIntervalDays.rawValue] as? Int ?? DefaultBrowserPromptFeatureSettings.subsequentActiveModalRepeatIntervalDays.defaultValue
                    message = "Next Modal Will Show After \(numberOfActiveDays) Active Days"
                } else {
                    let numberOfActiveDays = featureFlagger.defaultBrowserPromptFeatureSettings[DefaultBrowserPromptFeatureSettings.subsequentActiveModalRepeatIntervalDays.rawValue] as? Int ?? DefaultBrowserPromptFeatureSettings.subsequentActiveModalRepeatIntervalDays.defaultValue
                    message = "Next Modal Will Show After \(numberOfActiveDays) Active Days"
                }
            } else {
                let setting = featureFlagger.defaultBrowserPromptFeatureSettings[DefaultBrowserPromptFeatureSettings.firstActiveModalDelayDays.rawValue] as? Int ?? DefaultBrowserPromptFeatureSettings.firstActiveModalDelayDays.defaultValue
                let firstModalWillShowDate = localStatisticsStore.installDate.flatMap { $0.addingTimeInterval(.days(setting)) }
                let formattedWillShowDate = firstModalWillShowDate.flatMap { Self.dateFormatter.string(from: $0) } ?? "N/A"
                message = "First Modal Will Show: \(formattedWillShowDate)"
            }

            return message + " If Browser Is Not The Default One"
        }

        func numberOfModalShownMessage() -> String {
            "Number of Modal Shown: \(promptActivityStore.modalShownOccurrences)"
        }

        func currentActivityMessage() -> String {
            let currentActivity = userActivityStore.currentActivity()
            let lastActiveDayString = currentActivity.lastActiveDate.flatMap { Self.dateFormatter.string(from: $0) } ?? "N/A"
            let activityMessage = "Number of Active Days: \(currentActivity.numberOfActiveDays)\nLast Active Day: \(lastActiveDayString)"
            return activityMessage
        }

        let installationMessage = "Installation Date: \(localStatisticsStore.installDate.flatMap { Self.dateFormatter.string(from: $0) } ?? "N/A")"
        let activityMessage = currentActivityMessage()
        let modalMessage = nextModalMessage()
        let numberOfModalShownMessage = numberOfModalShownMessage()
        let inactiveUserModalShown = "Inactive User Modal Shown: \(promptActivityStore.hasInactiveModalShown)"

        debugLog = DebugLog(
            installation: installationMessage,
            activity: activityMessage,
            modal: modalMessage,
            numberOfModalShown: numberOfModalShownMessage,
            inactiveUserModalShown: inactiveUserModalShown
        )
    }
}

extension DefaultBrowserPromptUserType: @retroactive Identifiable {
    public var id: DefaultBrowserPromptUserType {
        self
    }
}

final class DefaultBrowserPromptDebugDateProvider {
    @UserDefaultsWrapper(key: .debugDefaultBrowserPromptCurrentDateKey, defaultValue: Date())
    var simulatedTodayDate: Date

    func reset() {
        simulatedTodayDate = Date()
    }
}
