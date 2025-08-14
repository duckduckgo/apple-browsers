//
//  UserScriptsTests.swift
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


import XCTest
import BrowserServicesKit
import Combine
@testable import DuckDuckGo

final class UserScriptsTests: XCTestCase {

    var userScripts: UserScripts!
    var mockFeatureFlagger: MockFeatureFlagger!
    var mockSourceProvider: DefaultScriptSourceProvider!
    var mockFireproofing: MockFireproofing!
    var mockExperimentManager: MockContentScopeExperimentManager!

    override func setUpWithError() throws {
        mockFeatureFlagger = MockFeatureFlagger()
        mockFireproofing = MockFireproofing()
        mockExperimentManager = MockContentScopeExperimentManager()
        
        mockSourceProvider = DefaultScriptSourceProvider(
            appSettings: AppSettingsMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            contentBlockingManager: MockContentBlockerRulesManagerProtocol(),
            fireproofing: mockFireproofing,
            contentScopeExperimentsManager: mockExperimentManager
        )
    }

    override func tearDownWithError() throws {
        userScripts = nil
        mockFeatureFlagger = nil
        mockSourceProvider = nil
        mockFireproofing = nil
        mockExperimentManager = nil
    }

    // MARK: - Dax Easter Egg User Script Feature Flag Tests

    @MainActor
    func testUserScripts_WhenDaxEasterEggLogosFeatureFlagEnabled_IncludesDaxEasterEggScript() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.daxEasterEggLogos]
        
        // When
        userScripts = UserScripts(with: mockSourceProvider, featureFlagger: mockFeatureFlagger)
        
        // Then
        let scriptArray = userScripts.userScripts
        let daxEasterEggScriptExists = scriptArray.contains { $0 is DaxEasterEggUserScript }
        XCTAssertTrue(daxEasterEggScriptExists, "DaxEasterEggUserScript should be included when feature flag is enabled")
    }
    
    @MainActor
    func testUserScripts_WhenDaxEasterEggLogosFeatureFlagDisabled_ExcludesDaxEasterEggScript() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [] // Feature flag disabled
        
        // When
        userScripts = UserScripts(with: mockSourceProvider, featureFlagger: mockFeatureFlagger)
        
        // Then
        let scriptArray = userScripts.userScripts
        let daxEasterEggScriptExists = scriptArray.contains { $0 is DaxEasterEggUserScript }
        XCTAssertFalse(daxEasterEggScriptExists, "DaxEasterEggUserScript should not be included when feature flag is disabled")
    }

    @MainActor
    func testUserScripts_WhenFeatureFlagDisabled_OtherScriptsStillIncluded() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [] // All feature flags disabled
        
        // When
        userScripts = UserScripts(with: mockSourceProvider, featureFlagger: mockFeatureFlagger)
        
        // Then
        let scriptArray = userScripts.userScripts
        
        // Verify some scripts are still included
        let hasFaviconScript = scriptArray.contains { $0 is FaviconUserScript }
        let hasFindInPageScript = scriptArray.contains { $0 is FindInPageUserScript }
        
        XCTAssertTrue(hasFaviconScript, "FaviconUserScript should always be included")
        XCTAssertTrue(hasFindInPageScript, "FindInPageUserScript should always be included")
        
        // But no DaxEasterEggUserScript
        let hasDaxEasterEggScript = scriptArray.contains { $0 is DaxEasterEggUserScript }
        XCTAssertFalse(hasDaxEasterEggScript, "DaxEasterEggUserScript should not be included when feature flag is disabled")
    }

    @MainActor
    func testUserScripts_LazyEvaluationOfUserScriptsArray() {
        // Given - UserScripts instance is created and userScripts array accessed
        mockFeatureFlagger.enabledFeatureFlags = [.daxEasterEggLogos]
        userScripts = UserScripts(with: mockSourceProvider, featureFlagger: mockFeatureFlagger)
        
        // When - Change feature flag after initialization (this wouldn't affect lazy property)
        mockFeatureFlagger.enabledFeatureFlags = []
        
        // Then - First access should still use the original flag state
        let scriptArray = userScripts.userScripts
        let daxEasterEggScriptExists = scriptArray.contains { $0 is DaxEasterEggUserScript }
        XCTAssertTrue(daxEasterEggScriptExists, "DaxEasterEggUserScript should be included based on flag state at first access")
        
        // Verify that subsequent accesses return the same cached result
        let secondAccessArray = userScripts.userScripts
        XCTAssertEqual(scriptArray.count, secondAccessArray.count, "Subsequent accesses should return the same cached array")
    }
}

// MARK: - Mock Classes

class MockContentBlockerRulesManagerProtocol: ContentBlockerRulesManagerProtocol {
    var updatesPublisher: AnyPublisher<ContentBlockerRulesManager.UpdateEvent, Never> = Empty<ContentBlockerRulesManager.UpdateEvent, Never>(completeImmediately: false).eraseToAnyPublisher()

    var currentRules: [BrowserServicesKit.ContentBlockerRulesManager.Rules] = []

    var currentMainRules: ContentBlockerRulesManager.Rules?

    var currentAttributionRules: ContentBlockerRulesManager.Rules?
}
