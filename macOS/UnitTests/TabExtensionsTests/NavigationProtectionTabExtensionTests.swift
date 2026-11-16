//
//  NavigationProtectionTabExtensionTests.swift
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

import FeatureFlags_macOS
import Foundation
import PrivacyConfig
import PrivacyConfigTestsUtils
import Testing

@testable import DuckDuckGo_Privacy_Browser

@MainActor
struct NavigationProtectionTabExtensionTests {

    /// `URLComponents` rewrites the `:00080` port to `:80`, and the fast filter keeps it as written,
    /// so the cleaned URL shows which path removed the tracking parameter.
    @available(macOS 13, *)
    @Test("fastTrackingParameterFilter picks the tracking parameter filter",
          .timeLimit(.minutes(1)),
          arguments: [(true, "https://www.example.com:00080/?a=1"), (false, "https://www.example.com:80/?a=1")])
    func fastTrackingParameterFilterPicksTheFilter(isFlagOn: Bool, expectedURL: String) async throws {
        let contentBlocking = ContentBlockingMock()
        let privacyConfig = try #require(contentBlocking.privacyConfigurationManager.privacyConfig as? MockPrivacyConfiguration)
        privacyConfig.isFeatureEnabledCheck = { feature, _ in feature == .trackingParameters }
        privacyConfig.featureSettings = ["parameters": ["utm_source"]]
        let tabExtension = NavigationProtectionTabExtension(
            contentBlocking: contentBlocking,
            webTrackingProtectionPreferences: WebTrackingProtectionPreferences(persistor: MockWebTrackingProtectionPreferencesPersistor(),
                                                                              windowControllersManager: WindowControllersManagerMock()),
            featureFlagger: MockFeatureFlagger(featuresStub: [FeatureFlag.fastTrackingParameterFilter.rawValue: isFlagOn])
        )
        let url = try #require(URL(string: "https://www.example.com:00080/?utm_source=x&a=1"))

        let cleanURL = await tabExtension.linkProtection.getCleanURL(from: url, onStartExtracting: {}, onFinishExtracting: {})

        #expect(cleanURL.absoluteString == expectedURL)
    }
}
