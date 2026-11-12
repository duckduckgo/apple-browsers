//
//  MaliciousSiteProtectionManagerTests.swift
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

import Testing
import Foundation
import MaliciousSiteProtection
@_spi(Testing) import PixelKit
@testable import DuckDuckGo

@Suite("Malicious Site Protection - Manager")
final class MaliciousSiteProtectionManagerTests {
    private var sut: MaliciousSiteProtectionManager!
    private var mockDetector: MockMaliciousSiteDetector!
    private var dataFetcherMock: MockMaliciousSiteProtectionDataFetcher!
    private var dataManager: MaliciousSiteProtection.DataManager!
    private var preferencesManagerMock: MockMaliciousSiteProtectionPreferencesManager!
    private var featureFlaggerMock: MockMaliciousSiteProtectionFeatureFlags!
    private var scamProtectionSupported = false
    private var isInBackground = false
    private let dataLoadStateProvider = MockMaliciousSiteProtectionDataLoadStateProvider()
    private let pixelKit = PixelKitMock()

    init() {
        dataManager = MaliciousSiteProtection.DataManager(
            fileStore: MockMaliciousSiteFileStore(),
            embeddedDataProvider: nil,
            fileNameProvider: { _ in "file.json" }
        )
        mockDetector = MockMaliciousSiteDetector()
        dataFetcherMock = MockMaliciousSiteProtectionDataFetcher()
        preferencesManagerMock = MockMaliciousSiteProtectionPreferencesManager()
        featureFlaggerMock = MockMaliciousSiteProtectionFeatureFlags()
        sut = MaliciousSiteProtectionManager(
            dataFetcher: dataFetcherMock,
            api: MaliciousSiteProtectionAPI(),
            dataManager: dataManager,
            detector: mockDetector,
            preferencesManager: preferencesManagerMock,
            maliciousSiteProtectionFeatureFlagger: featureFlaggerMock,
            supportedThreatsProvider: {
                return self.scamProtectionSupported ? ThreatKind.allCases : ThreatKind.allCases.filter { $0 != .scam }
            },
            isInBackground: { self.isInBackground },
            dataLoadStateProvider: dataLoadStateProvider,
            pixelFiring: { [pixelKit] in pixelKit }
        )
    }

    @MainActor
    @Test("Start Fetching Datasets Asks DatasetsFetcher To Fetch Data")
    func whenStartFetchingDatasetsIsCalledThenItAsksDataFetcherToFetchData() {
        // GIVEN
        #expect(!dataFetcherMock.didCallStartFetching)

        // WHEN
        sut.startFetching()

        // THEN
        #expect(dataFetcherMock.didCallStartFetching)
    }

    @Test(
        "No Threat Detected when Feature is disabled",
        arguments: [
            "https://phishing.com",
            "https://malware.com",
            "https://scam.com"
        ]
    )
    func whenFeatureIsDisabledThenThreatIsNotDetected(path: String) async throws {
        // GIVEN
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = false
        let url = try #require(URL(string: path))

        // WHEN
        let result = await sut.evaluate(url)

        // THEN
        #expect(result == nil)
    }

    @Test(
        "No Threat Detected When Domain Should Not Be Checked",
        arguments: [
            "https://phishing.com",
            "https://malware.com",
            "https://scam.com"
        ]
    )
    func whenEvaluateURL_AndShouldNotDetectMaliciousThreatForDomain_ThenReturnNil(path: String) async throws {
        // GIVEN
        preferencesManagerMock.isMaliciousSiteProtectionOn = true
        featureFlaggerMock.shouldDetectMaliciousThreatForDomainResult = false
        let url = try #require(URL(string: path))

        // WHEN
        let result = await sut.evaluate(url)

        // THEN
        #expect(result == nil)
    }

    @Test(
        "No Threat Detected When Preferences is Disabled",
        arguments: [
            "https://phishing.com",
            "https://malware.com",
            "https://scam.com"
        ]
    )
    func whenEvaluateURL_AndPreferenceDisabled_ThenReturnNil(path: String) async throws {
        // GIVEN
        preferencesManagerMock.isMaliciousSiteProtectionOn = false
        featureFlaggerMock.isScamProtectionEnabled = true
        featureFlaggerMock.shouldDetectMaliciousThreatForDomainResult = true
        let url = try #require(URL(string: path))

        // WHEN
        let result = await sut.evaluate(url)

        // THEN
        #expect(result == nil)
    }

    @Test(
        "Evaluate URL returns Right Threat",
        arguments: [
            (path: "https://phishing.com", threat: ThreatKind.phishing),
            (path: "https://malware.com", threat: .malware),
            (path: "https://scam.com", threat: .scam),
            (path: "https://trusted.com", threat: nil)
        ]
    )
    func urlReturnsRightThreat(threatInfo: (path: String, threat: ThreatKind?)) async throws {
        // GIVEN
        preferencesManagerMock.isMaliciousSiteProtectionOn = true
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        featureFlaggerMock.isScamProtectionEnabled = true
        featureFlaggerMock.shouldDetectMaliciousThreatForDomainResult = true
        let url = try #require(URL(string: threatInfo.path))

        // WHEN
        let result = await sut.evaluate(url)

        // THEN
        #expect(result == threatInfo.threat)
    }

    // MARK: - Check Pixel

    private func enableChecks() {
        preferencesManagerMock.isMaliciousSiteProtectionOn = true
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        featureFlaggerMock.shouldDetectMaliciousThreatForDomainResult = true
    }

    @available(iOS 16, *)
    @Test(
        "Background check fires a daily and count pixel for its data state",
        .timeLimit(.minutes(1)),
        arguments: [
            (isCached: true, name: "m_debug_malicious-site-protection_url-check_background_cached"),
            (isCached: false, name: "m_debug_malicious-site-protection_url-check_background_disk")
        ]
    )
    func backgroundCheckFiresPixel(state: (isCached: Bool, name: String)) async throws {
        // GIVEN
        isInBackground = true

        // WHEN
        await sut.fireBackgroundURLCheckPixel(isCached: state.isCached).value

        // THEN
        #expect(pixelKit.actualFireCalls.map(\.pixel.name) == [state.name])
        #expect(pixelKit.actualFireCalls.map(\.frequency) == [.dailyAndCount])
    }

    @available(iOS 16, *)
    @Test("Foreground check fires nothing, whether or not the hash prefixes are in memory", .timeLimit(.minutes(1)), arguments: [true, false])
    func foregroundCheckFiresNothing(isCached: Bool) async throws {
        // GIVEN
        isInBackground = false

        // WHEN
        await sut.fireBackgroundURLCheckPixel(isCached: isCached).value

        // THEN
        #expect(pixelKit.actualFireCalls.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Check asks whether the hash prefixes of every supported threat are in memory", .timeLimit(.minutes(1)), arguments: [false, true])
    func checkAsksForSupportedThreatHashPrefixes(isScamSupported: Bool) async throws {
        // GIVEN
        enableChecks()
        scamProtectionSupported = isScamSupported

        // WHEN
        _ = await sut.evaluate(try #require(URL(string: "https://example.com")))

        // THEN
        #expect(dataLoadStateProvider.capturedKind == .hashPrefixSet)
        #expect(dataLoadStateProvider.capturedThreatKinds == (isScamSupported ? ThreatKind.allCases : [.phishing, .malware]))
    }

    /// The pixel's task starts only after the data state is read, so a check that never reads it fires nothing.
    @available(iOS 16, *)
    @Test("No check when the feature is off", .timeLimit(.minutes(1)))
    func noCheckWhenFeatureIsOff() async throws {
        // GIVEN
        enableChecks()
        featureFlaggerMock.shouldDetectMaliciousThreatForDomainResult = false

        // WHEN
        _ = await sut.evaluate(try #require(URL(string: "https://example.com")))

        // THEN
        #expect(dataLoadStateProvider.capturedKind == nil)
    }

    /// The pixel's task starts only after the data state is read, so a check that never reads it fires nothing.
    @available(iOS 16, *)
    @Test("No check when the setting is off", .timeLimit(.minutes(1)))
    func noCheckWhenSettingIsOff() async throws {
        // GIVEN
        enableChecks()
        preferencesManagerMock.isMaliciousSiteProtectionOn = false

        // WHEN
        _ = await sut.evaluate(try #require(URL(string: "https://example.com")))

        // THEN
        #expect(dataLoadStateProvider.capturedKind == nil)
    }
}
