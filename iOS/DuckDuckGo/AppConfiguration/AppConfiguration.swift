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
import WebKit

struct AppConfiguration {

    private let featureFlagger = AppDependencyProvider.shared.featureFlagger

    let persistentStoresConfiguration = PersistentStoresConfiguration()
    let onboardingConfiguration = OnboardingConfiguration()
    let atbAndVariantConfiguration = ATBAndVariantConfiguration()
    private let appKeyValueStore: ThrowingKeyValueStoring

    init(appKeyValueStore: ThrowingKeyValueStoring) {
        self.appKeyValueStore = appKeyValueStore
    }

    func start(isBookmarksDBFilePresent: Bool?) throws {
        KeyboardConfiguration.disableHardwareKeyboardForUITests()
        PixelConfiguration.configure(with: featureFlagger)

        APIRequest.Headers.setUserAgent(DefaultUserAgentManager.duckDuckGoUserAgent)

        onboardingConfiguration.migrateToNewOnboarding()
        clearTemporaryDirectory()
        try persistentStoresConfiguration.configure(syncKeyValueStore: appKeyValueStore, isBookmarksDBFilePresent: isBookmarksDBFilePresent)
        migrateAIChatSettings()
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
                Pixel.fire(pixel: .debugFailedToCreateAppConfigurationUserDefaultsInAIChatSettingsMigration)
            }
            return sharedUserDefaults ?? UserDefaults()
        })
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
            
            Logger.general.error("💥 Temp directory still missing after all recreation attempts. Is background: \(isBackground)")
            Pixel.fire(pixel: .tmpDirStillMissingAfterRecreation, withAdditionalParameters: ["isBackground": String(isBackground)])
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
            Pixel.fire(pixel: .failedToRemoveTmpDir, error: error)
        }
    }

    private func recreateTempDirectory(at url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            Logger.general.info("ℹ️ Temp directory exists, skipping recreation")
            return
        }

        let maxAttempts = 5
        let retryInterval: TimeInterval = 1.0
        
        for attempt in 0..<maxAttempts {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                Logger.general.info("📁 Recreated temp directory at: \(url.path)")
                
                if attempt > 0 {
                    Pixel.fire(pixel: .recreateTmpSuccessOnRetry(attempt: attempt))
                }
                return
            } catch {
                Logger.general.error("❌ Failed to recreate tmp dir (attempt \(attempt)): \(error.localizedDescription)")
                Pixel.fire(pixel: .recreateTmpAttemptFailed(attempt: attempt), error: error)

                let isLastAttempt = attempt == maxAttempts - 1
                if isLastAttempt {
                    attemptWebViewTempDirectoryFallback(at: url)
                    return
                } else {
                    Thread.sleep(forTimeInterval: retryInterval)
                }
            }
        }
    }
    
    private func attemptWebViewTempDirectoryFallback(at url: URL) {
        Logger.general.info("🌐 Attempting WKWebView fallback for temp directory recreation")
        // Create a minimal WKWebView to trigger temp directory creation
        // WebKit may have elevated privileges that could help with directory creation
        _ = WKWebView(frame: .zero)

        let fallbackSucceeded = FileManager.default.fileExists(atPath: url.path)
        if fallbackSucceeded {
            Logger.general.info("✅ WKWebView fallback successfully recreated temp directory")
            Pixel.fire(pixel: .recreateTmpWebViewFallbackSucceeded)
        } else {
            Logger.general.error("❌ WKWebView fallback failed to recreate temp directory")
            Pixel.fire(pixel: .recreateTmpWebViewFallbackFailed)
        }
    }

    @MainActor
    func finalize(reportingService: ReportingService,
                  mainViewController: MainViewController,
                  launchTaskManager: LaunchTaskManager) {
        atbAndVariantConfiguration.cleanUpATBAndAssignVariant {
            onVariantAssigned(reportingService: reportingService)
        }
        CrashHandlersConfiguration.handleCrashDuringCrashHandlersSetup()
        startAutomationServerIfNeeded(mainViewController: mainViewController)
        UserAgentConfiguration(
            store: appKeyValueStore,
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
