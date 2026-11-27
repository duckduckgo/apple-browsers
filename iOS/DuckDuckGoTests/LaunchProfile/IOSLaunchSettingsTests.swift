//
//  IOSLaunchSettingsTests.swift
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

import AIChat
import Configuration
import DDGSync
import Foundation
import Testing
import LaunchProfile
@_spi(Testing) import Persistence
import PrivacyConfig
@testable import Core
@testable import DuckDuckGo
@testable import FeatureFlags_iOS

/// Each test applies a profile and reads the result back the way the app reads it.
@MainActor
@Suite(.serialized)
final class IOSLaunchSettingsTests {

    nonisolated private static let suiteName = "testing_iOSLaunchSettings"
    nonisolated private static let appConfigurationSuiteName = "testing_iOSLaunchSettings_appConfiguration"
    private let internalUserStore = MockInternalUserStoring()
    private let tabsPersistence = TabsModelPersistence(normalStore: InMemoryThrowingKeyValueStore(),
                                                       fireStore: InMemoryThrowingKeyValueStore(),
                                                       legacyStore: UserDefaults(suiteName: suiteName)!)
    private let appSettings = AppSettingsMock()
    private let defaults = UserDefaults(suiteName: suiteName)!
    private let appConfigurationDefaults = UserDefaults(suiteName: appConfigurationSuiteName)!
    private var launchArguments: [String: String] = [:]

    deinit {
        [Self.suiteName, Self.appConfigurationSuiteName].forEach { UserDefaults(suiteName: $0)?.removePersistentDomain(forName: $0) }
    }

    private func apply(_ json: String, flagOverridesNeedInternalUser: Bool = true) throws -> LaunchProfileOutcome {
        let settings = IOSLaunchSettings.make(.init(
            internalUserStore: internalUserStore,
            flagOverridesNeedInternalUser: flagOverridesNeedInternalUser,
            setLaunchArgument: { [unowned self] value, key in launchArguments[key] = value },
            tabsPersistence: { [tabsPersistence] in tabsPersistence },
            isPad: false,
            appSettings: appSettings,
            appDefaults: defaults,
            appConfigurationDefaults: appConfigurationDefaults,
            aiChatDebugSettings: AIChatDebugSettings(userDefault: defaults),
            statistics: StatisticsUserDefaults(groupName: Self.suiteName)
        ))
        return settings.apply(try LaunchProfile(json: Data(json.utf8)))
    }

    private static var overridableFlag: FeatureFlag {
        FeatureFlag.allCases.first { $0.supportsLocalOverriding && $0.cohortType == nil }!
    }

    private static var experimentFlag: FeatureFlag {
        FeatureFlag.allCases.first { $0.supportsLocalOverriding && $0.cohortType != nil }!
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func onboardingCompletedIsReadByLaunchOptionsHandler() throws {
        _ = try apply(#"{"onboardingCompleted": true}"#)

        #expect(launchArguments == [LaunchOptionsHandler.isOnboardingCompleted: "true"])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func featureFlagBecomesTheFFLaunchArgument() throws {
        let flag = Self.overridableFlag

        _ = try apply(#"{"internalUser": true, "featureFlags": {"\#(flag.rawValue)": true}}"#)

        #expect(launchArguments == ["ff.\(flag.rawValue)": "true"])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func featureFlagNeedsInternalUser() throws {
        let outcome = try apply(#"{"featureFlags": {"\#(Self.overridableFlag.rawValue)": true}}"#)

        #expect(!outcome.isSuccess)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func featureFlagWorksWithoutInternalUserWhenUITesting() throws {
        let flag = Self.overridableFlag

        let outcome = try apply(#"{"featureFlags": {"\#(flag.rawValue)": true}}"#, flagOverridesNeedInternalUser: false)

        #expect(outcome.isSuccess)
        #expect(launchArguments == ["ff.\(flag.rawValue)": "true"])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func experimentCohortBecomesTheLaunchArgumentOnlyWhenItExists() throws {
        let flag = Self.experimentFlag
        let cohortID = try #require(flag.cohortType.flatMap { Self.firstCohortID(of: $0) })

        let unknown = try apply(#"{"internalUser": true, "experiments": {"\#(flag.rawValue)": "not-a-cohort"}}"#)
        let known = try apply(#"{"internalUser": true, "experiments": {"\#(flag.rawValue)": "\#(cohortID)"}}"#)

        #expect(!unknown.isSuccess)
        #expect(known.isSuccess)
        #expect(launchArguments == ["experiment.\(flag.rawValue)": cohortID])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func privacyConfigURLBecomesTheLaunchArgument() throws {
        let invalid = try apply(#"{"internalUser": true, "privacyConfigURL": "file:///config.json"}"#)
        let valid = try apply(#"{"internalUser": true, "privacyConfigURL": "http://localhost:8080/ios-config.json"}"#)

        #expect(!invalid.isSuccess)
        #expect(valid.isSuccess)
        #expect(launchArguments == ["privacyConfigURL": "http://localhost:8080/ios-config.json"])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func tabsAreRestoredWithTheLastOneSelected() throws {
        _ = try tabsPersistence.saveSynchronously(model: TabsModel(desktop: false, mode: .fire), for: .fire).get()

        _ = try apply(#"{"tabs": ["https://example.com/", "https://duck.ai/"]}"#)

        let model = try #require(try tabsPersistence.getTabsModel(for: .normal))
        #expect(model.tabs.map(\.link?.url.absoluteString) == ["https://example.com/", "https://duck.ai/"])
        #expect(model.currentIndex == 1)
        #expect(try tabsPersistence.getTabsModel(for: .fire) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func tabsMustBeWebPages() throws {
        let outcome = try apply(#"{"tabs": ["example.com"]}"#)

        #expect(outcome == .rejected([LaunchProfileProblem(key: "tabs",
                                                           message: #""tabs" is invalid: use http or https URLs, like https://example.com."#)]))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func settingsScreenOptionsAreWrittenThroughAppSettings() throws {
        let outcome = try apply(#"""
        {"settings": {"addressBarPosition": "bottom", "theme": "dark", "textZoom": 120, "fireAnimation": "none",
                      "autoClear": {"options": ["tabs", "aiChats"], "timing": "delay30min"}}}
        """#)

        #expect(outcome.isSuccess)
        #expect(appSettings.currentAddressBarPosition == .bottom)
        #expect(appSettings.currentThemeStyle == .dark)
        #expect(appSettings.defaultTextZoomLevel == .percent120)
        #expect(appSettings.currentFireButtonAnimation == .none)
        #expect(appSettings.autoClearAction == [.tabs, .aiChats])
        #expect(appSettings.autoClearTiming == .delay30min)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func settingsMustNameAKnownOption() throws {
        let theme = try apply(#"{"settings.theme": "blue"}"#)
        let autoClear = try apply(#"{"settings.autoClear.options": ["tabs", "cookies"]}"#)

        #expect(theme == .rejected([LaunchProfileProblem(key: "settings.theme",
                                                         message: #""settings.theme" is invalid: use one of systemDefault, light, dark."#)]))
        #expect(autoClear == .rejected([LaunchProfileProblem(key: "settings.autoClear.options",
                                                             message: #""settings.autoClear.options" is invalid: use any of aiChats, data, tabs."#)]))
        #expect(appSettings.currentThemeStyle == .systemDefault)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func duckAISettingsAreReadBackByAIChatSettings() throws {
        let outcome = try apply(#"""
        {"duckAI": {"enabled": true, "addressBar": false, "searchInput": true, "tabSwitcher": false, "defaultOmnibarMode": "duckAI",
                   "pageSummariesModel": "appleIntelligence"}}
        """#)

        let aiChatSettings = AIChatSettings(privacyConfigurationManager: PrivacyConfigurationManagerMock(),
                                            debugSettings: MockAIChatDebugSettings(),
                                            keyValueStore: appConfigurationDefaults,
                                            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.aiChatOmnibarDefaultPosition]),
                                            pixelFiring: nil)
        #expect(outcome.isSuccess)
        #expect(aiChatSettings.isAIChatEnabled)
        #expect(!aiChatSettings.isAIChatAddressBarUserSettingsEnabled)
        #expect(aiChatSettings.isAIChatSearchInputUserSettingsEnabled)
        #expect(!aiChatSettings.isAIChatTabSwitcherUserSettingsEnabled)
        #expect(aiChatSettings.defaultOmnibarMode == .duckAI)
        #expect(aiChatSettings.pageSummariesModel == .appleIntelligence)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func duckAICanBeTurnedOff() throws {
        _ = try apply(#"{"duckAI.enabled": false}"#)

        let aiChatSettings = AIChatSettings(privacyConfigurationManager: PrivacyConfigurationManagerMock(),
                                            debugSettings: MockAIChatDebugSettings(),
                                            keyValueStore: appConfigurationDefaults,
                                            featureFlagger: MockFeatureFlagger(),
                                            pixelFiring: nil)
        #expect(!aiChatSettings.isAIChatEnabled)
        #expect(!aiChatSettings.isAIChatSearchInputUserSettingsEnabled)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func debugMenuOptionsAreReadBackByTheApp() throws {
        let outcome = try apply(#"""
        {"internalUser": true,
         "debug": {"onboarding": {"userType": "returningUser", "flowType": "duckAI"},
                   "duckAI": {"customURL": "http://localhost:8080/chat"},
                   "idleReturnThresholdSeconds": 5,
                   "syncEnvironment": "Development",
                   "daysSinceInstall": 8,
                   "configURLs": {"remoteMessagingConfig": "http://localhost:8080/rmf.json"}}}
        """#)

        #expect(outcome.isSuccess)
        #expect(appSettings.onboardingUserType == .returningUser)
        #expect(appSettings.onboardingFlowType == .duckAI)
        #expect(AIChatDebugSettings(userDefault: defaults).customURL == "http://localhost:8080/chat")
        let idleReturnOverrides: some KeyedStoring<IdleReturnDebugOverridesKeys> = defaults.keyedStoring()
        #expect(idleReturnOverrides.thresholdSecondsOverride == 5)
        #expect(ServerEnvironment(UserDefaultsWrapper(key: .syncEnvironment, defaultValue: "", container: defaults).wrappedValue) == .development)
        let installDate = try #require(StatisticsUserDefaults(groupName: Self.suiteName).installDate)
        #expect(Calendar.current.dateComponents([.day], from: installDate, to: Date()).day == 8)
        #expect(CustomConfigurationURLStorage(defaults: appConfigurationDefaults).customRemoteMessagingConfigURL == URL(string: "http://localhost:8080/rmf.json"))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func customConfigurationURLsNeedInternalUser() throws {
        let outcome = try apply(#"{"debug.configURLs.privacyConfiguration": "http://localhost:8080/config.json"}"#)

        #expect(outcome == .rejected([LaunchProfileProblem(
            key: "debug.configURLs.privacyConfiguration",
            message: #""debug.configURLs.privacyConfiguration" needs "internalUser": true in the same profile."#)]))
        #expect(CustomConfigurationURLStorage(defaults: appConfigurationDefaults).customPrivacyConfigurationURL == nil)
    }

    private static func firstCohortID<Cohort: FeatureFlagCohortDescribing>(of type: Cohort.Type) -> CohortID? {
        Cohort.allCases.first?.rawValue
    }
}
