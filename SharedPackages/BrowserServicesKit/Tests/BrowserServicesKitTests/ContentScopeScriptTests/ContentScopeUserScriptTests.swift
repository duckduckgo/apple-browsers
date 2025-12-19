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

import PrivacyConfig
import PrivacyConfigTestsUtils
import WebKit
import XCTest
@testable import BrowserServicesKit
@testable import UserScript

final class ContentScopeUserScriptTests: XCTestCase {

    let generatorConfig = "generatorConfig"
    let managerConfig = "managerConfig"
    var properties: ContentScopeProperties!
    var configGenerator: MockCSSPrivacyConfigGenerator!
    var mockPrivacyConfigurationManager: MockPrivacyConfigurationManager!
    let mockMessageBody: [String: Any] = [
        "featureName": "ContentScopeScript",
        "context": "mainFrame",
        "method": "debugFlag",
        "params": [
            "flag": "debug-flag-enabled"
        ]
    ]
    let experimentData = ContentScopeExperimentData(feature: "parentExperiment", subfeature: "experiment", cohort: "aCohort")
    var experimentManager: MockContentScopeExperimentManager!

    func mockMessageBody(featureName: String) -> [String: Any] {
        let result: [String: Any] = [
            "featureName": featureName,
            "context": "mainFrame",
            "method": "debugFlag",
            "params": [
                "flag": "debug-flag-enabled"
            ]
        ]
        return result
    }

    override func setUp() {
        super.setUp()
        properties = ContentScopeProperties(gpcEnabled: false, sessionKey: "", messageSecret: "", featureToggles: ContentScopeFeatureToggles(emailProtection: false, emailProtectionIncontextSignup: false, credentialsAutofill: false, identitiesAutofill: false, creditCardsAutofill: false, credentialsSaving: false, passwordGeneration: false, inlineIconCredentials: false, thirdPartyCredentialsProvider: false, unknownUsernameCategorization: false, partialFormSaves: false, passwordVariantCategorization: true, inputFocusApi: false, autocompleteAttributeSupport: false), currentCohorts: [experimentData])
        configGenerator = MockCSSPrivacyConfigGenerator()
        mockPrivacyConfigurationManager = MockPrivacyConfigurationManager(privacyConfig: MockPrivacyConfiguration(),
                                                                          internalUserDecider: DefaultInternalUserDecider(store: MockInternalUserStoring()))
        mockPrivacyConfigurationManager.currentConfigString = managerConfig
    }

    override func tearDown() {
        configGenerator = nil
        mockPrivacyConfigurationManager = nil
        super.tearDown()
    }

    func testPrivacyConfigurationJSONGeneratorIsUsed() throws {
        // GIVEN
        configGenerator.config = generatorConfig

        // WHEN
        let source = try ContentScopeUserScript.generateSource(
            mockPrivacyConfigurationManager,
            properties: properties,
            scriptContext: .contentScope,
            config: WebkitMessagingConfig(webkitMessageHandlerNames: [], secret: "", hasModernWebkitAPI: true),
            privacyConfigurationJSONGenerator: configGenerator
        )

        // THEN
        XCTAssertTrue(source.contains(generatorConfig))
    }

    func testFallbackToPrivacyConfigurationManagerWhenGeneratorIsNil() throws {
        // GIVEN
        configGenerator.config = nil

        // WHEN
        let source = try ContentScopeUserScript.generateSource(
            mockPrivacyConfigurationManager,
            properties: properties,
            scriptContext: .contentScope,
            config: WebkitMessagingConfig(webkitMessageHandlerNames: [], secret: "", hasModernWebkitAPI: true),
            privacyConfigurationJSONGenerator: configGenerator
        )

        // THEN
        XCTAssertFalse(source.contains(generatorConfig))
    }

    func testThatForIsolatedContext_debugFlagsAreCaptured_and_messageIsRoutedToTheBroker() async throws {
        // GIVEN
        let contentScopeScript = try ContentScopeUserScript(
            mockPrivacyConfigurationManager,
            properties: properties,
            scriptContext: .contentScopeIsolated,
            privacyConfigurationJSONGenerator: configGenerator
        )
        let capturingContentScopeUserScriptDelegate = CapturingContentScopeUserScriptDelegate()
        contentScopeScript.delegate = capturingContentScopeUserScriptDelegate
        let message = await MockWKScriptMessage(name: ContentScopeScriptContext.contentScopeIsolated.messagingContextName, body: mockMessageBody)

        // WHEN
        let result = await contentScopeScript.userContentController(WKUserContentController(),
                                    didReceive: message)

        // THEN
        XCTAssertEqual(capturingContentScopeUserScriptDelegate.debugFlagReceived, "debug-flag-enabled")
        // If an error is thrown means the message has been passed to the broker
        XCTAssertNotNil(result.1)
    }

    func testThatForNonIsolatedContentScopeContext_debugFlagsAreCaptured_and_messageIsNotRoutedToTheBroker() async throws {
        // GIVEN
        let contentScopeScript = try ContentScopeUserScript(
            mockPrivacyConfigurationManager,
            properties: properties,
            scriptContext: .contentScope,
            privacyConfigurationJSONGenerator: configGenerator
        )
        let capturingContentScopeUserScriptDelegate = CapturingContentScopeUserScriptDelegate()
        contentScopeScript.delegate = capturingContentScopeUserScriptDelegate
        let message = await MockWKScriptMessage(name: ContentScopeScriptContext.contentScope.messagingContextName, body: mockMessageBody)

        // WHEN
        let result = await contentScopeScript.userContentController(WKUserContentController(),
                                    didReceive: message)

        // THEN
        XCTAssertEqual(capturingContentScopeUserScriptDelegate.debugFlagReceived, "debug-flag-enabled")
        XCTAssertNil(result.0)
        XCTAssertNil(result.1)
    }

    func testThatForNonIsolatedContext_andNotContentScopeScriptContext_messageIsToTheBroker() async throws {
        // GIVEN
        let featureName = "dbpui"

        let contentScopeScript = try ContentScopeUserScript(mockPrivacyConfigurationManager,
                                                            properties: properties,
                                                            scriptContext: .contentScope,
                                                            allowedNonisolatedFeatures: [featureName],
                                                            privacyConfigurationJSONGenerator: configGenerator)
        let capturingContentScopeUserScriptDelegate = CapturingContentScopeUserScriptDelegate()
        contentScopeScript.delegate = capturingContentScopeUserScriptDelegate
        let message = await MockWKScriptMessage(name: featureName, body: mockMessageBody(featureName: featureName))

        // WHEN
        let result = await contentScopeScript.userContentController(WKUserContentController(),
                                    didReceive: message)

        // THEN
        XCTAssertNotNil(result.1)
    }

    func testSourceContainsExperimentProperties() throws {
        let source = try ContentScopeUserScript.generateSource(
            mockPrivacyConfigurationManager,
            properties: properties,
            scriptContext: .contentScope,
            config: WebkitMessagingConfig(webkitMessageHandlerNames: [], secret: "", hasModernWebkitAPI: true),
            privacyConfigurationJSONGenerator: configGenerator
        )

        XCTAssertTrue(source.contains("currentCohorts"))
        XCTAssertTrue(source.contains(experimentData.cohort))
        XCTAssertTrue(source.contains(experimentData.feature))
        XCTAssertTrue(source.contains(experimentData.subfeature))
    }

    // MARK: - ContentScopeScriptContext Tests

    func testWhenAIChatDataClearingContextThenFileNameIsDuckAiDataClearing() {
        // GIVEN
        let context = ContentScopeScriptContext.aiChatDataClearing

        // THEN
        XCTAssertEqual(context.fileName, "duckAiDataClearing")
    }

    func testWhenAIChatDataClearingContextThenMessagingContextNameIsDuckAiDataClearing() {
        // GIVEN
        let context = ContentScopeScriptContext.aiChatDataClearing

        // THEN
        XCTAssertEqual(context.messagingContextName, "duckAiDataClearing")
    }

    func testWhenAIChatDataClearingContextThenIsIsolatedReturnsFalse() {
        // GIVEN
        let context = ContentScopeScriptContext.aiChatDataClearing

        // THEN
        XCTAssertFalse(context.isIsolated)
    }

    func testWhenContentScopeContextThenFileNameIsContentScope() {
        // GIVEN
        let context = ContentScopeScriptContext.contentScope

        // THEN
        XCTAssertEqual(context.fileName, "contentScope")
    }

    func testWhenContentScopeContextThenMessagingContextNameIsContentScopeScripts() {
        // GIVEN
        let context = ContentScopeScriptContext.contentScope

        // THEN
        XCTAssertEqual(context.messagingContextName, "contentScopeScripts")
    }

    func testWhenContentScopeContextThenIsIsolatedReturnsFalse() {
        // GIVEN
        let context = ContentScopeScriptContext.contentScope

        // THEN
        XCTAssertFalse(context.isIsolated)
    }

    func testWhenContentScopeIsolatedContextThenFileNameIsContentScopeIsolated() {
        // GIVEN
        let context = ContentScopeScriptContext.contentScopeIsolated

        // THEN
        XCTAssertEqual(context.fileName, "contentScopeIsolated")
    }

    func testWhenContentScopeIsolatedContextThenMessagingContextNameIsContentScopeScriptsIsolated() {
        // GIVEN
        let context = ContentScopeScriptContext.contentScopeIsolated

        // THEN
        XCTAssertEqual(context.messagingContextName, "contentScopeScriptsIsolated")
    }

    func testWhenContentScopeIsolatedContextThenIsIsolatedReturnsTrue() {
        // GIVEN
        let context = ContentScopeScriptContext.contentScopeIsolated

        // THEN
        XCTAssertTrue(context.isIsolated)
    }

    // MARK: - ContentScopeUserScript Integration Tests with aiChatDataClearing Context

    func testWhenAIChatDataClearingContextThenMessageNamesContainsDuckAiDataClearing() throws {
        // GIVEN
        let contentScopeScript = try ContentScopeUserScript(
            mockPrivacyConfigurationManager,
            properties: properties,
            scriptContext: .aiChatDataClearing,
            privacyConfigurationJSONGenerator: configGenerator
        )

        // THEN
        XCTAssertEqual(contentScopeScript.messageNames, ["duckAiDataClearing"])
    }

    func testWhenAIChatDataClearingContextThenRequiresRunInPageContentWorldIsTrue() throws {
        // GIVEN
        let contentScopeScript = try ContentScopeUserScript(
            mockPrivacyConfigurationManager,
            properties: properties,
            scriptContext: .aiChatDataClearing,
            privacyConfigurationJSONGenerator: configGenerator
        )

        // THEN
        XCTAssertTrue(contentScopeScript.requiresRunInPageContentWorld)
    }

    func testWhenAIChatDataClearingContextThenScriptContextIsAIChatDataClearing() throws {
        // GIVEN
        let contentScopeScript = try ContentScopeUserScript(
            mockPrivacyConfigurationManager,
            properties: properties,
            scriptContext: .aiChatDataClearing,
            privacyConfigurationJSONGenerator: configGenerator
        )

        // THEN
        XCTAssertEqual(contentScopeScript.scriptContext, .aiChatDataClearing)
    }

    func testWhenAIChatDataClearingContextWithAllowedFeaturesThenMessagesAreRoutedToBroker() async throws {
        // GIVEN
        let allowedFeature = "duckAiDataClearing"
        let contentScopeScript = try ContentScopeUserScript(
            mockPrivacyConfigurationManager,
            properties: properties,
            scriptContext: .aiChatDataClearing,
            allowedNonisolatedFeatures: [allowedFeature],
            privacyConfigurationJSONGenerator: configGenerator
        )

        let mockMessageBody: [String: Any] = [
            "featureName": allowedFeature,
            "context": "mainFrame",
            "method": "testMethod",
            "params": [:]
        ]
        let message = await MockWKScriptMessage(name: "duckAiDataClearing", body: mockMessageBody)

        // WHEN
        let result = await contentScopeScript.userContentController(WKUserContentController(), didReceive: message)

        // THEN
        // Message should be routed to broker (non-nil error indicates broker processed it)
        XCTAssertNotNil(result.1)
    }

    func testWhenAIChatDataClearingContextWithoutAllowedFeaturesThenMessagesAreNotRoutedToBroker() async throws {
        // GIVEN
        let contentScopeScript = try ContentScopeUserScript(
            mockPrivacyConfigurationManager,
            properties: properties,
            scriptContext: .aiChatDataClearing,
            allowedNonisolatedFeatures: [],
            privacyConfigurationJSONGenerator: configGenerator
        )

        let mockMessageBody: [String: Any] = [
            "featureName": "someOtherFeature",
            "context": "mainFrame",
            "method": "testMethod",
            "params": [:]
        ]
        let message = await MockWKScriptMessage(name: "duckAiDataClearing", body: mockMessageBody)

        // WHEN
        let result = await contentScopeScript.userContentController(WKUserContentController(), didReceive: message)

        // THEN
        // Message should NOT be routed to broker for non-isolated context without allowed features
        XCTAssertNil(result.0)
        XCTAssertNil(result.1)
    }
}

class MockCSSPrivacyConfigGenerator: CustomisedPrivacyConfigurationJSONGenerating {
    var config: String?
    var privacyConfiguration: Data? {
        config?.data(using: .utf8)
    }
}

class CapturingContentScopeUserScriptDelegate: ContentScopeUserScriptDelegate {
    var debugFlagReceived: String?

    func contentScopeUserScript(_ script: BrowserServicesKit.ContentScopeUserScript, didReceiveDebugFlag debugFlag: String) {
        debugFlagReceived = debugFlag
    }
}
