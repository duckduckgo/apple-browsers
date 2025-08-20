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
        APIRequest.Headers.setUserAgent(DefaultUserAgentManager.duckDuckGoUserAgent)

        onboardingConfiguration.migrateToNewOnboarding()
        clearTemporaryDirectory()
        try persistentStoresConfiguration.configure()
        migrateAIChatSettings()

        WidgetCenter.shared.reloadAllTimelines()
        PrivacyFeatures.httpsUpgrade.loadDataAsync()
    }

    /// Perform AI Chat settings migration, and needs to happen before AIChatSettings is created
    ///  and the widgets needs to be reloaded after.
    /// Moves settings from `UserDefaults.standard` to the shared container.
    private func migrateAIChatSettings() {
        AIChatSettingsMigration.migrate(from: UserDefaults.standard, to: {
            let sharedUserDefaults = UserDefaults(suiteName: Global.appConfigurationGroupName)
            if sharedUserDefaults == nil {
                Pixel.fire(pixel: .debugFailedToCreateAppConfigurationUserDefaultsInAIChatSettingsMigration)
            }
            return sharedUserDefaults ?? UserDefaults()
        })
    }

    private func clearTemporaryDirectory() {
        let tmp = FileManager.default.temporaryDirectory
        do {
            try FileManager.default.removeItem(at: tmp)
            Logger.general.info("🧹 Removed temp directory at: \(tmp.path)")
            // https://app.asana.com/1/137249556945/project/1201392122292466/task/1210925187026095?focus=true
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true, attributes: nil)
            Logger.general.info("📁 Recreated temp directory at: \(tmp.path)")
        } catch {
            Logger.general.error("❌ Failed to reset tmp dir: \(error.localizedDescription)")
        }
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
