//
//  MaliciousSiteProtectionService.swift
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

import Foundation
import BrowserServicesKit
import MaliciousSiteProtection
import Core

// Container for Malicious Site Protection Feature.
final class MaliciousSiteProtectionService {

    let preferencesManager = MaliciousSiteProtectionPreferencesManager()
    let manager: MaliciousSiteProtectionManaging

    init(featureFlagger: FeatureFlagger) {
        let maliciousSiteProtectionAPI = MaliciousSiteProtectionAPI()

        // If Application Support directory is not available leave a trail in crash logs.
        guard let applicationSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not found Application Support directory for Malicious Site Protection")
        }

        let maliciousSiteProtectionDataManager = MaliciousSiteProtection.DataManager(
            fileStore: MaliciousSiteProtection.FileStore(
                dataStoreURL: applicationSupportDirectory
            ),
            embeddedDataProvider: nil,
            fileNameProvider: MaliciousSiteProtectionManager.fileName(for:)
        )

        let maliciousSiteProtectionFeatureFlagger = MaliciousSiteProtectionFeatureFlags(featureFlagger: featureFlagger)

        let remoteIntervalProvider: (MaliciousSiteProtection.DataManager.StoredDataType) -> TimeInterval = { dataKind in
            switch dataKind {
            case .hashPrefixSet: .minutes(maliciousSiteProtectionFeatureFlagger.hashPrefixUpdateFrequency)
            case .filterSet: .minutes(maliciousSiteProtectionFeatureFlagger.filterSetUpdateFrequency)
            }
        }
        let supportedThreatsProvider = {
            let isScamProtectionEnabled = featureFlagger.isFeatureOn(.scamSiteProtection)
            return isScamProtectionEnabled ? ThreatKind.allCases : ThreatKind.allCases.filter { $0 != .scam }
        }

        let shouldRemoveWWWInCanonicalization = {
            return featureFlagger.isFeatureOn(.removeWWWInCanonicalizationInThreatProtection)
        }

        let updateManager = MaliciousSiteProtection.UpdateManager(
            apiEnvironment: maliciousSiteProtectionAPI.environment,
            service: maliciousSiteProtectionAPI.service,
            dataManager: maliciousSiteProtectionDataManager,
            eventMapping: MaliciousSiteProtectionEventMapper.debugEvents,
            updateIntervalProvider: remoteIntervalProvider,
            supportedThreatsProvider: supportedThreatsProvider
        )

        let maliciousSiteProtectionDatasetsFetcher = MaliciousSiteProtectionDatasetsFetcher(
            updateManager: updateManager,
            featureFlagger: maliciousSiteProtectionFeatureFlagger,
            userPreferencesManager: preferencesManager
        )

        manager = MaliciousSiteProtectionManager(
            dataFetcher: maliciousSiteProtectionDatasetsFetcher,
            api: maliciousSiteProtectionAPI,
            dataManager: maliciousSiteProtectionDataManager,
            preferencesManager: preferencesManager,
            maliciousSiteProtectionFeatureFlagger: maliciousSiteProtectionFeatureFlagger,
            supportedThreatsProvider: supportedThreatsProvider,
            shouldRemoveWWWInCanonicalization: shouldRemoveWWWInCanonicalization
        )

        Task { @MainActor in
            maliciousSiteProtectionDatasetsFetcher.registerBackgroundRefreshTaskHandler()
        }
    }

    // MARK: - Resume

    @MainActor
    func resume() {
        manager.startFetching()
    }

}

// MARK: Malicious Site Protection Feature Flagger

extension MaliciousSiteProtectionFeatureFlags {

    init(
        featureFlagger: FeatureFlagger,
        privacyConfigManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager
    ) {
        self.init(
            privacyConfigManager: privacyConfigManager,
            isMaliciousSiteProtectionEnabled: {
                featureFlagger.isFeatureOn(.maliciousSiteProtection)
            }
        )
    }

}
