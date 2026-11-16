//
//  WebExtensionManager+iOS.swift
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

import Combine
import Core
import DuckPlayer
import EventHub
import FeatureFlags_iOS
import PrivacyConfig
import UIKit
import WebExtensions
import WebKit

// MARK: - AutoconsentPreferencesProviding

final class AutoconsentPreferencesAdapter: AutoconsentPreferencesProviding {
    private let preferences: AutoconsentPreferences

    init(preferences: AutoconsentPreferences) {
        self.preferences = preferences
    }

    var cookiePopupPreference: CookiePopupPreference {
        preferences.cookiePopupPreference
    }
}

// MARK: - Factory

@available(iOS 18.4, *)
public enum WebExtensionManagerFactory {

    private static var extensionsDirectory: URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory not found")
        }
        return appSupport.appendingPathComponent("WebExtensions", isDirectory: true)
    }

    @MainActor
    static func makeManager(
        mainViewController: MainViewController,
        featureFlagger: FeatureFlagger,
        privacyConfigurationManager: PrivacyConfigurationManaging,
        autoconsentPreferences: AutoconsentPreferences,
        darkReaderExcludedDomainsProvider: DarkReaderExcludedDomainsProviding? = nil,
        searchTokenProvider: SearchTokenProviding? = nil,
        scriptletConfiguration: ScriptletConfiguration? = nil,
        eventHub: EventHubManaging
    ) -> WebExtensionManager {
        let preferencesAdapter = AutoconsentPreferencesAdapter(preferences: autoconsentPreferences)
        let pixelFiring = iOSWebExtensionPixelFiring()
        let cpmMessagingHealthMonitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring, isUnmeasuredPage: { $0.isDuckPlayer })
        return WebExtensionManager(
            configuration: WebExtensionConfigurationProvider(),
            windowTabProvider: WebExtensionWindowTabProvider(mainViewController: mainViewController),
            storageProvider: WebExtensionStorageProvider(extensionsDirectory: extensionsDirectory),
            pixelFiring: pixelFiring,
            cpmMessagingHealthMonitor: cpmMessagingHealthMonitor,
            isCPMNetworkProcessRecoveryEnabled: {
                featureFlagger.isFeatureOn(.cpmNetworkProcessRecovery)
            },
            cpmNetworkProcessRecoveryFeatureFlagUpdates: featureFlagger.updatesPublisher,
            isCPMBackgroundLoadRestartEnabled: {
                featureFlagger.isFeatureOn(.cpmBackgroundLoadRestart)
            },
            isApplicationInBackground: { UIApplication.shared.applicationState == .background },
            isCPMStableBaseURLEnabled: {
                featureFlagger.isFeatureOn(.cpmStableBaseURL)
            },
            isCPMUpgradeBeforeLoadEnabled: featureFlagger.isFeatureOn(.cpmUpgradeBeforeLoad),
            handlerProvider: WebExtensionHandlerProvider(
                privacyConfigurationManager: privacyConfigurationManager,
                autoconsentPreferences: preferencesAdapter,
                cpmMessagingHealthMonitor: cpmMessagingHealthMonitor,
                darkReaderExcludedDomainsProvider: darkReaderExcludedDomainsProvider,
                searchTokenProvider: searchTokenProvider,
                eventHub: eventHub
            ),
            scriptletConfiguration: scriptletConfiguration
        )
    }
}
