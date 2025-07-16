//
//  AppConfiguration.swift
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

import BrowserServicesKit
import WidgetKit
import Core
import Networking
import Configuration
import Persistence

struct AppConfiguration {

    @UserDefaultsWrapper(key: .privacyConfigCustomURL, defaultValue: nil)
    private var privacyConfigCustomURL: String?

    @UserDefaultsWrapper(key: .remoteMessagingConfigCustomURL, defaultValue: nil)
    private var remoteMessagingConfigCustomURL: String?

    private let featureFlagger = AppDependencyProvider.shared.featureFlagger

    let persistentStoresConfiguration = PersistentStoresConfiguration()
    let onboardingConfiguration = OnboardingConfiguration()
    let atbAndVariantConfiguration = ATBAndVariantConfiguration()
    let contentBlockingConfiguration = ContentBlockingConfiguration()

    func start() throws {
        KeyboardConfiguration.disableHardwareKeyboardForUITests()
        PixelConfiguration.configure(with: featureFlagger)
        NewTabPageIntroMessageConfiguration().disableIntroMessageForReturningUsers()

        contentBlockingConfiguration.prepareContentBlocking()
        configureAPIRequestUserAgent()
        onboardingConfiguration.migrateToNewOnboarding()
        try persistentStoresConfiguration.configure()
        setConfigurationURLProvider()

        WidgetCenter.shared.reloadAllTimelines()
        PrivacyFeatures.httpsUpgrade.loadDataAsync()
    }

    private func configureAPIRequestUserAgent() {
        APIRequest.Headers.setUserAgent(DefaultUserAgentManager.duckDuckGoUserAgent)
    }

    private func setConfigurationURLProvider() {
        // Never use the custom configuration by default when not DEBUG, but
        //  you can go to the debug menu and enabled it.
        if !isDebugBuild {
            Configuration.setURLProvider(AppConfigurationURLProvider())
            return
        }

        // Always use custom configuration in debug.
        //  Only the configurations editable in the debug menu are specified here.
        let privacyConfigURL = privacyConfigCustomURL.flatMap { URL(string: $0) }
        let remoteMessagingConfigURL = remoteMessagingConfigCustomURL.flatMap { URL(string: $0) }

        // This will default to normal values if the overrides are nil.
        Configuration.setURLProvider(CustomConfigurationURLProvider(
            customPrivacyConfigurationURL: privacyConfigURL,
            customRemoteMessagingConfigURL: remoteMessagingConfigURL
        ))
    }

    @MainActor
    func finalize(reportingService: ReportingService,
                  mainViewController: MainViewController,
                  launchTaskManager: LaunchTaskManager,
                  keyValueStore: ThrowingKeyValueStoring) {
        atbAndVariantConfiguration.cleanUpATBAndAssignVariant {
            onVariantAssigned(reportingService: reportingService)
        }
        CrashHandlersConfiguration.handleCrashDuringCrashHandlersSetup()
        startAutomationServerIfNeeded(mainViewController: mainViewController)
        UserAgentConfiguration(
            store: keyValueStore,
            launchTaskManager: launchTaskManager
        ).configure() // Called at launch end to avoid IPC race when spawning WebView for content blocking.
    }

    private func startAutomationServerIfNeeded(mainViewController: MainViewController) {
        let launchOptionsHandler = LaunchOptionsHandler()
        guard launchOptionsHandler.automationPort != nil else {
            return
        }
        Task { @MainActor in
            _ = AutomationServer(main: mainViewController, port: launchOptionsHandler.automationPort)
        }
    }

    // MARK: - Handle ATB and variant assigned logic here

    private func onVariantAssigned(reportingService: ReportingService) {
        onboardingConfiguration.adjustDialogsForUITesting()
        hideHistoryMessageForNewUsers()
        reportingService.setupStorageForMarketPlacePostback()
    }

    private func hideHistoryMessageForNewUsers() {
        HistoryMessageManager().dismiss()
    }

}
