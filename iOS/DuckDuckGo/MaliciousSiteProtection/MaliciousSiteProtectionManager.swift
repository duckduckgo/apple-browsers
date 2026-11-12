//
//  MaliciousSiteProtectionManager.swift
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

import Foundation
import MaliciousSiteProtection
import Common
import FoundationExtensions
import Core
import PixelKit
import UIKit

typealias MaliciousSiteProtectionManaging = MaliciousSiteDetecting & MaliciousSiteProtectionDatasetsFetching

/// Says whether datasets are in memory, without loading them.
protocol MaliciousSiteProtectionDataLoadStateProviding {
    func isLoaded(_ kind: MaliciousSiteProtection.DataManager.StoredDataType.Kind, for threatKinds: [ThreatKind]) async -> Bool
}

extension MaliciousSiteProtection.DataManager: MaliciousSiteProtectionDataLoadStateProviding {}

final class MaliciousSiteProtectionManager {
    private let detector: MaliciousSiteDetecting
    private let dataFetcher: MaliciousSiteProtectionDatasetsFetching
    private let preferencesManager: MaliciousSiteProtectionPreferencesReading
    private let maliciousSiteProtectionFeatureFlagger: MaliciousSiteProtectionFeatureFlagger
    private let dataLoadStateProvider: MaliciousSiteProtectionDataLoadStateProviding
    private let isInBackground: @MainActor () -> Bool
    private let supportedThreatsProvider: SupportedThreatsProvider
    private let pixelFiring: () -> PixelFiring?

    init(
        dataFetcher: MaliciousSiteProtectionDatasetsFetching,
        api: MaliciousSiteProtectionAPI,
        dataManager: MaliciousSiteProtection.DataManager,
        detector: MaliciousSiteProtection.MaliciousSiteDetecting? = nil,
        preferencesManager: MaliciousSiteProtectionPreferencesReading,
        maliciousSiteProtectionFeatureFlagger: MaliciousSiteProtectionFeatureFlagger,
        supportedThreatsProvider: @escaping SupportedThreatsProvider,
        isInBackground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .background },
        dataLoadStateProvider: MaliciousSiteProtectionDataLoadStateProviding? = nil,
        pixelFiring: @escaping () -> PixelFiring? = { PixelKit.shared }
    ) {
        self.dataFetcher = dataFetcher
        self.preferencesManager = preferencesManager
        self.maliciousSiteProtectionFeatureFlagger = maliciousSiteProtectionFeatureFlagger
        self.dataLoadStateProvider = dataLoadStateProvider ?? dataManager
        self.isInBackground = isInBackground
        self.supportedThreatsProvider = supportedThreatsProvider
        self.pixelFiring = pixelFiring
        self.detector = detector ?? MaliciousSiteDetector(
            apiEnvironment: api.environment,
            service: api.service,
            dataManager: dataManager,
            eventMapping: MaliciousSiteProtectionEventMapper.debugEvents(),
            supportedThreatsProvider: supportedThreatsProvider
        )
    }
}

// MARK: - MaliciousSiteProtectionDatasetsFetching

extension MaliciousSiteProtectionManager: MaliciousSiteProtectionDatasetsFetching {

    @MainActor
    @discardableResult
    func startFetching() -> Task<Void, Never> {
        dataFetcher.startFetching()
    }
    
}

// MARK: - MaliciousSiteDetecting

extension MaliciousSiteProtectionManager: MaliciousSiteDetecting {

    func evaluate(_ url: URL) async -> ThreatKind? {
        guard
            maliciousSiteProtectionFeatureFlagger.shouldDetectMaliciousThreat(forDomain: url.host),
            preferencesManager.isMaliciousSiteProtectionOn
        else {
            return .none
        }

        // Read before the detector runs, because the detector loads the hash prefixes.
        let isCached = await dataLoadStateProvider.isLoaded(.hashPrefixSet, for: supportedThreatsProvider())
        fireBackgroundURLCheckPixel(isCached: isCached)

        return await detector.evaluate(url)
    }

    /// Counts checks that run in the background, by whether the hash prefixes were in memory or read from disk.
    /// Filter sets aren't counted: they're only read after a hash prefix match.
    /// Runs in its own task so detection doesn't wait for the main thread.
    @discardableResult
    func fireBackgroundURLCheckPixel(isCached: Bool) -> Task<Void, Never> {
        Task { [isInBackground, pixelFiring] in
            // `applicationState` can only be read on the main thread.
            guard await isInBackground() else { return }

            pixelFiring()?.fire(MaliciousSiteProtectionDebugPixel.backgroundURLCheck(dataState: isCached ? .cached : .disk), frequency: .dailyAndCount)
        }
    }

}

// MARK: - Configuration

extension MaliciousSiteProtectionManager {
    
    static func fileName(for dataType: MaliciousSiteProtection.DataManager.StoredDataType) -> String {
        switch (dataType, dataType.threatKind) {
        case (.hashPrefixSet, .phishing): "phishingHashPrefixes.json"
        case (.filterSet, .phishing): "phishingFilterSet.json"
        case (.hashPrefixSet, .malware): "malwareHashPrefixes.json"
        case (.filterSet, .malware): "malwareFilterSet.json"
        case (.hashPrefixSet, .scam): "scamHashPrefixes.json"
        case (.filterSet, .scam): "scamFilterSet.json"
        }
    }
    
}
