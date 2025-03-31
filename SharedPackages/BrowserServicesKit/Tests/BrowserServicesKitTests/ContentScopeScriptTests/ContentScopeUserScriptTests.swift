//
//  ContentScopeUserScriptTests.swift
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
@testable import BrowserServicesKit
@testable import UserScript

final class ContentScopeUserScriptTests: XCTestCase {

    let generatorConfig = "generatorConfig"
    let managerConfig = "managerConfig"
    let properties = ContentScopeProperties(gpcEnabled: false, sessionKey: "", messageSecret: "", featureToggles: ContentScopeFeatureToggles(emailProtection: false, emailProtectionIncontextSignup: false, credentialsAutofill: false, identitiesAutofill: false, creditCardsAutofill: false, credentialsSaving: false, passwordGeneration: false, inlineIconCredentials: false, thirdPartyCredentialsProvider: false, unknownUsernameCategorization: false, partialFormSaves: false))
    var configGenerator: MockCSSPrivacyConfigGenerator!
    var mockPrivacyConfigurationManager: MockPrivacyConfigurationManager!

    override func setUp() {
        super.setUp()
        configGenerator = MockCSSPrivacyConfigGenerator()
        mockPrivacyConfigurationManager = MockPrivacyConfigurationManager(privacyConfig: MockPrivacyConfiguration(), internalUserDecider: DefaultInternalUserDecider(mockedStore: MockInternalUserStoring()))
        mockPrivacyConfigurationManager.currentConfigString = managerConfig
    }

    override func tearDown() {
        configGenerator = nil
        mockPrivacyConfigurationManager = nil
        super.tearDown()
    }

    func testPrivacyConfigurationJSONGeneratorIsUsed() {
        // GIVEN
        configGenerator.config = generatorConfig

        // WHEN
        let source = ContentScopeUserScript.generateSource(mockPrivacyConfigurationManager, properties: properties, isolated: false, config: WebkitMessagingConfig(webkitMessageHandlerNames: [], secret: "", hasModernWebkitAPI: true), privacyConfigurationJSONGenerator: configGenerator)

        // THEN
        XCTAssertTrue(source.contains(generatorConfig))
    }

    func testFallbackToPrivacyConfigurationManagerWhenGeneratorIsNil() {
        // GIVEN
        configGenerator.config = nil

        // WHEN
        let source = ContentScopeUserScript.generateSource(mockPrivacyConfigurationManager, properties: properties, isolated: false, config: WebkitMessagingConfig(webkitMessageHandlerNames: [], secret: "", hasModernWebkitAPI: true), privacyConfigurationJSONGenerator: configGenerator)

        // THEN
        XCTAssertFalse(source.contains(generatorConfig))
    }
}

class MockCSSPrivacyConfigGenerator: CustomisedPrivacyConfigurationJSONGenerating {
    var config: String?
    var privacyConfiguration: Data? {
        config?.data(using: .utf8)
    }
}
