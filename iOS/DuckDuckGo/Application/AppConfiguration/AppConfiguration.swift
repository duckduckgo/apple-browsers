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

import AIChat
import BrowserServicesKit
import WidgetKit
import Core
import Networking
import Configuration
import Persistence
import UIKit
import PixelKit
#if canImport(DuckSansFont)
import DuckSansFont
#endif
import PrivacyConfig
import FeatureFlags_iOS

struct AppConfiguration {

    let atbAndVariantConfiguration = ATBAndVariantConfiguration()
    let persistentStoresConfiguration = PersistentStoresConfiguration()
    let onboardingConfiguration = OnboardingConfiguration()
    private let appKeyValueStore: ThrowingKeyValueStoring
    private let featureFlagger: FeatureFlagger

    init(appKeyValueStore: ThrowingKeyValueStoring, featureFlagger: FeatureFlagger) {
        self.appKeyValueStore = appKeyValueStore
        self.featureFlagger = featureFlagger
    }

    func start(isBookmarksDBFilePresent: Bool?) throws {
#if canImport(DuckSansFont)
        // Register DuckSans custom font
        DuckSansFont.registerFonts()
#endif

        KeyboardConfiguration.disableHardwareKeyboardForUITests()

        APIRequest.Headers.setUserAgent(DefaultUserAgentManager.duckDuckGoUserAgent)

        onboardingConfiguration.migrateToNewOnboarding()
        clearTemporaryDirectory()
        try persistentStoresConfiguration.configure(syncKeyValueStore: appKeyValueStore, isBookmarksDBFilePresent: isBookmarksDBFilePresent)
        migrateAIChatSettings()
        setDefaultOmnibarModeIfNeeded()
        migratePromptCooldown()

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
                PixelKit.fire(Pixel.Event.debugFailedToCreateAppConfigurationUserDefaultsInAIChatSettingsMigration)
            }
            return sharedUserDefaults ?? UserDefaults()
        })
    }

    /// Set the default omnibar mode for new users on first launch.
    /// Must run before ATB is assigned (in `finalize`) so `hasInstallStatistics` correctly
    /// distinguishes new installs (false) from existing users updating (true).
    private func setDefaultOmnibarModeIfNeeded() {
        let store = UserDefaults(suiteName: Global.appConfigurationGroupName) ?? UserDefaults()
        let key = LegacyAiChatUserDefaultsKeys.defaultOmnibarModeKey
        guard store.object(forKey: key) == nil else { return }

        guard featureFlagger.isFeatureOn(.aiChatOmnibarDefaultPosition) else {
            return
        }

        let isExistingUser = StatisticsUserDefaults().hasInstallStatistics
        let defaultMode: DefaultOmnibarMode = isExistingUser ? .search : .lastUsed
        store.set(defaultMode.rawValue, forKey: key)
    }

    /// Migrate Default Browser prompt cooldown to global modal prompt cooldown.
    /// One-time migration from the old Default Browser `lastModalShownDate` to the new global cooldown storage.
    private func migratePromptCooldown() {
        let migrator = PromptCooldownMigrator(keyValueStore: appKeyValueStore)
        migrator.migrateIfNeeded()
    }

    private func clearTemporaryDirectory() {
        let tmp = FileManager.default.temporaryDirectory
        removeTempDirectory(at: tmp)
        recreateTempDirectory(at: tmp)
        
        if !FileManager.default.fileExists(atPath: tmp.path) {
            let isBackground = UIApplication.shared.applicationState == .background
            
            Logger.general.error("💥 Temp directory still missing after recreation. Is background: \(isBackground)")
            PixelKit.fire(Pixel.Event.tmpDirStillMissingAfterRecreation, options: .parameters(["isBackground": String(isBackground)]))
        }
    }

    private func removeTempDirectory(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            Logger.general.info("ℹ️ Temp directory did not exist, nothing to remove")
            return
        }

        do {
            try FileManager.default.removeItem(at: url)
            Logger.general.info("🧹 Removed temp directory at: \(url.path)")
        } catch {
            Logger.general.error("⚠️ Failed to remove tmp dir: \(error.localizedDescription)")
            PixelKit.fire(Pixel.Event.failedToRemoveTmpDir.withError(error))
        }
    }

    private func recreateTempDirectory(at url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            Logger.general.info("ℹ️ Temp directory exists, skipping recreation")
            return
        }

        // Failures are in practice always out of disk space, which waiting does not fix,
        // so a single attempt avoids blocking launch on retries.
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            Logger.general.info("📁 Recreated temp directory at: \(url.path)")
        } catch {
            Logger.general.error("❌ Failed to recreate tmp dir: \(error.localizedDescription)")
        }
    }

    @MainActor
    func finalize(reportingService: ReportingService,
                  mainViewController: MainViewController,
                  launchTaskManager: LaunchTaskManager) -> AutomationServer? {
        atbAndVariantConfiguration.cleanUpATBAndAssignVariant {
            onVariantAssigned(reportingService: reportingService)
        }
        CrashHandlersConfiguration.handleCrashDuringCrashHandlersSetup()
        let automationServer = startAutomationServerIfNeeded(mainViewController: mainViewController)
        UserAgentConfiguration(
            store: appKeyValueStore,
            launchTaskManager: launchTaskManager
        ).configure() // Called at launch end to avoid IPC race when spawning WebView for content blocking.
        return automationServer
    }

    @MainActor
    private func startAutomationServerIfNeeded(mainViewController: MainViewController) -> AutomationServer? {
#if DEBUG || ALPHA
        let launchOptionsHandler = LaunchOptionsHandler()
        guard launchOptionsHandler.automationPort != nil else {
            return nil
        }
        return AutomationServer(main: mainViewController, port: launchOptionsHandler.automationPort)
#else
        return nil
#endif
    }

    // MARK: - Handle ATB and variant assigned logic here

    private func onVariantAssigned(reportingService: ReportingService) {
        onboardingConfiguration.adjustDialogsForUITesting()
        reportingService.setupStorageForMarketPlacePostback()
    }

}
