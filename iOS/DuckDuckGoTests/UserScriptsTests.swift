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

}

// MARK: - Mock Classes

class MockContentBlockerRulesManagerProtocol: ContentBlockerRulesManagerProtocol {
    var updatesPublisher: AnyPublisher<ContentBlockerRulesManager.UpdateEvent, Never> = Empty<ContentBlockerRulesManager.UpdateEvent, Never>(completeImmediately: false).eraseToAnyPublisher()

    var currentRules: [BrowserServicesKit.ContentBlockerRulesManager.Rules] = []

    var currentMainRules: ContentBlockerRulesManager.Rules?

    var currentAttributionRules: ContentBlockerRulesManager.Rules?
}
