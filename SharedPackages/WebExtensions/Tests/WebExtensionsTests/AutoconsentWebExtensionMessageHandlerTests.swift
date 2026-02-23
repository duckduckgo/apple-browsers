//
//  AutoconsentWebExtensionMessageHandlerTests.swift
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

import XCTest
import PrivacyConfig
import PrivacyConfigTestsUtils
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class AutoconsentWebExtensionMessageHandlerTests: XCTestCase {

    var handler: AutoconsentWebExtensionMessageHandler!
    var mockPrivacyConfigurationManager: MockPrivacyConfigurationManager!
    var mockPrivacyConfiguration: MockPrivacyConfiguration!
    var mockAutoconsentPreferences: MockAutoconsentPreferences!

    override func setUp() {
        super.setUp()
        mockPrivacyConfiguration = MockPrivacyConfiguration()
        mockPrivacyConfigurationManager = MockPrivacyConfigurationManager(privacyConfig: mockPrivacyConfiguration)
        mockAutoconsentPreferences = MockAutoconsentPreferences()
        handler = AutoconsentWebExtensionMessageHandler(
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            autoconsentPreferences: mockAutoconsentPreferences
        )
    }

    override func tearDown() {
        handler = nil
        mockAutoconsentPreferences = nil
        mockPrivacyConfigurationManager = nil
        mockPrivacyConfiguration = nil
        super.tearDown()
    }

    // MARK: - Handler Properties

    func testHandledFeatureName() {
        XCTAssertEqual(handler.handledFeatureName, "autoconsent")
    }

    // MARK: - Unknown Method

    func testWhenUnknownMethodThenReturnsUnknownMethodError() async {
        let message = createMessage(method: "unknownMethod")

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .unknownMethod(let method) = handlerError {
                XCTAssertEqual(method, "unknownMethod")
            } else {
                XCTFail("Expected unknownMethod error")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    // MARK: - sendPixel (Not Implemented)

    func testWhenSendPixelThenReturnsNotImplementedError() async {
        let message = createMessage(method: "sendPixel", params: ["pixelName": "test", "type": "impression"])

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .unknownMethod(let method) = handlerError {
                XCTAssertEqual(method, "sendPixel")
            } else {
                XCTFail("Expected unknownMethod error for sendPixel")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    // MARK: - refreshCpmDashboardState (Not Implemented)

    func testWhenRefreshCpmDashboardStateThenReturnsNotImplementedError() async {
        let message = createMessage(method: "refreshCpmDashboardState")

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .unknownMethod(let method) = handlerError {
                XCTAssertEqual(method, "refreshCpmDashboardState")
            } else {
                XCTFail("Expected unknownMethod error")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    // MARK: - showCpmAnimation (Not Implemented)

    func testWhenShowCpmAnimationThenReturnsNotImplementedError() async {
        let message = createMessage(method: "showCpmAnimation")

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .unknownMethod(let method) = handlerError {
                XCTAssertEqual(method, "showCpmAnimation")
            } else {
                XCTFail("Expected unknownMethod error")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    // MARK: - cookiePopupHandled

    func testWhenCookiePopupHandledWithValidParamsThenReturnsSuccess() async {
        let msg: [String: Any] = [
            "url": "https://example.com/page",
            "cmp": "test-cmp",
            "result": true
        ]
        let message = createMessage(method: "cookiePopupHandled", params: ["msg": msg])

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: String]
            XCTAssertEqual(dict?["response"], "ok")
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenCookiePopupHandledWithMissingMsgThenReturnsMissingParameterError() async {
        let message = createMessage(method: "cookiePopupHandled", params: [:])

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .missingParameter(let parameter) = handlerError {
                XCTAssertTrue(parameter.contains("msg") || parameter.contains("url"))
            } else {
                XCTFail("Expected missingParameter error")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    func testWhenCookiePopupHandledWithMissingUrlInMsgThenReturnsMissingParameterError() async {
        let msg: [String: Any] = [
            "cmp": "test-cmp",
            "result": true
        ]
        let message = createMessage(method: "cookiePopupHandled", params: ["msg": msg])

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .missingParameter(let parameter) = handlerError {
                XCTAssertTrue(parameter.contains("url") || parameter.contains("msg"))
            } else {
                XCTFail("Expected missingParameter error")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    // MARK: - isFeatureEnabled

    func testWhenIsFeatureEnabledWithValidParametersThenReturnsEnabled() async {
        mockPrivacyConfiguration.isFeatureEnabledCheck = { _, _ in true }
        let message = createMessage(
            method: "isFeatureEnabled",
            params: ["featureName": "autoconsent", "url": "https://example.com"]
        )

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertEqual(dict?["enabled"], true)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenIsFeatureEnabledWithDisabledFeatureThenReturnsDisabled() async {
        mockPrivacyConfiguration.isFeatureEnabledCheck = { _, _ in false }
        let message = createMessage(
            method: "isFeatureEnabled",
            params: ["featureName": "autoconsent", "url": "https://example.com"]
        )

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertEqual(dict?["enabled"], false)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenIsFeatureEnabledWithUnknownFeatureNameThenReturnsDisabled() async {
        let message = createMessage(
            method: "isFeatureEnabled",
            params: ["featureName": "unknownFeature", "url": "https://example.com"]
        )

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertEqual(dict?["enabled"], false)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenIsFeatureEnabledWithMissingFeatureNameThenReturnsMissingParameterError() async {
        let message = createMessage(
            method: "isFeatureEnabled",
            params: ["url": "https://example.com"]
        )

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .missingParameter(let parameter) = handlerError {
                XCTAssertTrue(parameter.contains("featureName"))
            } else {
                XCTFail("Expected missingParameter error")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    func testWhenIsFeatureEnabledWithMissingURLThenReturnsMissingParameterError() async {
        let message = createMessage(
            method: "isFeatureEnabled",
            params: ["featureName": "autoconsent"]
        )

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .missingParameter(let parameter) = handlerError {
                XCTAssertTrue(parameter.contains("url"))
            } else {
                XCTFail("Expected missingParameter error")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    func testWhenIsFeatureEnabledWithInvalidURLFormatThenStillReturnsResult() async {
        mockPrivacyConfiguration.isFeatureEnabledCheck = { _, _ in true }
        let message = createMessage(
            method: "isFeatureEnabled",
            params: ["featureName": "autoconsent", "url": "not-a-valid-url"]
        )

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertNotNil(dict?["enabled"])
        } else {
            XCTFail("Expected success result")
        }
    }

    // MARK: - isSubFeatureEnabled

    func testWhenIsSubFeatureEnabledWithValidAutoconsentSubfeatureThenReturnsEnabled() async {
        mockPrivacyConfiguration.isSubfeatureEnabledCheck = { _, _ in true }
        let message = createMessage(
            method: "isSubFeatureEnabled",
            params: ["featureName": "autoconsent", "subfeatureName": "onByDefault"]
        )

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertEqual(dict?["enabled"], true)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenIsSubFeatureEnabledWithDisabledSubfeatureThenReturnsDisabled() async {
        mockPrivacyConfiguration.isSubfeatureEnabledCheck = { _, _ in false }
        let message = createMessage(
            method: "isSubFeatureEnabled",
            params: ["featureName": "autoconsent", "subfeatureName": "filterlist"]
        )

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertEqual(dict?["enabled"], false)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenIsSubFeatureEnabledWithHeuristicActionSubfeatureThenReturnsCorrectly() async {
        mockPrivacyConfiguration.isSubfeatureEnabledCheck = { _, _ in true }
        let message = createMessage(
            method: "isSubFeatureEnabled",
            params: ["featureName": "autoconsent", "subfeatureName": "heuristicAction"]
        )

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertEqual(dict?["enabled"], true)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenIsSubFeatureEnabledWithUnknownFeatureNameThenReturnsDisabled() async {
        let message = createMessage(
            method: "isSubFeatureEnabled",
            params: ["featureName": "unknownFeature", "subfeatureName": "onByDefault"]
        )

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertEqual(dict?["enabled"], false)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenIsSubFeatureEnabledWithNonAutoconsentFeatureThenReturnsDisabled() async {
        let message = createMessage(
            method: "isSubFeatureEnabled",
            params: ["featureName": "duckPlayer", "subfeatureName": "pip"]
        )

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertEqual(dict?["enabled"], false)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenIsSubFeatureEnabledWithUnknownSubfeatureThenReturnsDisabled() async {
        let message = createMessage(
            method: "isSubFeatureEnabled",
            params: ["featureName": "autoconsent", "subfeatureName": "unknownSubfeature"]
        )

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertEqual(dict?["enabled"], false)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenIsSubFeatureEnabledWithMissingFeatureNameThenReturnsMissingParameterError() async {
        let message = createMessage(
            method: "isSubFeatureEnabled",
            params: ["subfeatureName": "onByDefault"]
        )

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .missingParameter(let parameter) = handlerError {
                XCTAssertTrue(parameter.contains("featureName"))
            } else {
                XCTFail("Expected missingParameter error")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    func testWhenIsSubFeatureEnabledWithMissingSubfeatureNameThenReturnsMissingParameterError() async {
        let message = createMessage(
            method: "isSubFeatureEnabled",
            params: ["featureName": "autoconsent"]
        )

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .missingParameter(let parameter) = handlerError {
                XCTAssertTrue(parameter.contains("subfeatureName"))
            } else {
                XCTFail("Expected missingParameter error")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    // MARK: - getResourceIfNew

    func testWhenGetResourceIfNewWithSameVersionThenReturnsNotUpdated() async {
        mockPrivacyConfigurationManager.currentConfigString = """
        {
            "version": "1.0.0",
            "features": {}
        }
        """

        let message = createMessage(
            method: "getResourceIfNew",
            params: ["name": "config", "version": "1.0.0"]
        )

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Any]
            XCTAssertEqual(dict?["updated"] as? Bool, false)
            XCTAssertNil(dict?["data"])
            XCTAssertNil(dict?["version"])
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenGetResourceIfNewWithDifferentVersionThenReturnsUpdatedConfig() async {
        mockPrivacyConfigurationManager.currentConfigString = """
        {
            "version": "2.0.0",
            "features": {}
        }
        """

        let message = createMessage(
            method: "getResourceIfNew",
            params: ["name": "config", "version": "1.0.0"]
        )

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Any]
            XCTAssertEqual(dict?["updated"] as? Bool, true)
            XCTAssertNotNil(dict?["data"])
            XCTAssertEqual(dict?["version"] as? String, "2.0.0")
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenGetResourceIfNewWithUnsupportedResourceTypeThenReturnsError() async {
        let message = createMessage(
            method: "getResourceIfNew",
            params: ["name": "unsupportedResource", "version": "1.0.0"]
        )

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .unsupportedResourceType(let resourceType) = handlerError {
                XCTAssertEqual(resourceType, "unsupportedResource")
            } else {
                XCTFail("Expected unsupportedResourceType error")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    func testWhenGetResourceIfNewWithMissingNameThenReturnsMissingParameterError() async {
        let message = createMessage(
            method: "getResourceIfNew",
            params: ["version": "1.0.0"]
        )

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .missingParameter(let parameter) = handlerError {
                XCTAssertTrue(parameter.contains("name"))
            } else {
                XCTFail("Expected missingParameter error")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    func testWhenGetResourceIfNewWithMissingVersionThenReturnsMissingParameterError() async {
        let message = createMessage(
            method: "getResourceIfNew",
            params: ["name": "config"]
        )

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .missingParameter(let parameter) = handlerError {
                XCTAssertTrue(parameter.contains("version"))
            } else {
                XCTFail("Expected missingParameter error")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    func testWhenGetResourceIfNewWithInvalidJSONThenReturnsConfigurationError() async {
        mockPrivacyConfigurationManager.currentConfigString = "invalid json"

        let message = createMessage(
            method: "getResourceIfNew",
            params: ["name": "config", "version": "1.0.0"]
        )

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .configurationError = handlerError {
            } else {
                XCTFail("Expected configurationError")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    func testWhenGetResourceIfNewWithMissingVersionInConfigThenReturnsConfigurationError() async {
        mockPrivacyConfigurationManager.currentConfigString = """
        {
            "features": {}
        }
        """

        let message = createMessage(
            method: "getResourceIfNew",
            params: ["name": "config", "version": "1.0.0"]
        )

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .configurationError = handlerError {
            } else {
                XCTFail("Expected configurationError")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    // MARK: - isAutoconsentSettingEnabled

    func testWhenIsAutoconsentSettingEnabledAndPreferenceIsTrueThenReturnsEnabled() async {
        mockAutoconsentPreferences.isAutoconsentEnabled = true
        let message = createMessage(method: "isAutoconsentSettingEnabled")

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertEqual(dict?["enabled"], true)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenIsAutoconsentSettingEnabledAndPreferenceIsFalseThenReturnsDisabled() async {
        mockAutoconsentPreferences.isAutoconsentEnabled = false
        let message = createMessage(method: "isAutoconsentSettingEnabled")

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertEqual(dict?["enabled"], false)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenIsAutoconsentSettingEnabledWithParametersThenIgnoresParamsAndReturnsCorrectly() async {
        mockAutoconsentPreferences.isAutoconsentEnabled = true
        let message = createMessage(
            method: "isAutoconsentSettingEnabled",
            params: ["someKey": "someValue"]
        )

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertEqual(dict?["enabled"], true)
        } else {
            XCTFail("Expected success result")
        }
    }

    // MARK: - extensionLog

    func testWhenExtensionLogWithMessageThenReturnsSuccess() async {
        let message = createMessage(
            method: "extensionLog",
            params: ["message": "Test log message"]
        )

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: String]
            XCTAssertEqual(dict?["response"], "ok")
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenExtensionLogWithEmptyMessageThenReturnsSuccess() async {
        let message = createMessage(
            method: "extensionLog",
            params: ["message": ""]
        )

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: String]
            XCTAssertEqual(dict?["response"], "ok")
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenExtensionLogWithMissingMessageThenReturnsMissingParameterError() async {
        let message = createMessage(method: "extensionLog", params: [:])

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .missingParameter(let parameter) = handlerError {
                XCTAssertEqual(parameter, "message")
            } else {
                XCTFail("Expected missingParameter error")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    // MARK: - Helper Methods

    private func createMessage(
        method: String,
        params: [String: Any]? = nil
    ) -> WebExtensionMessage {
        WebExtensionMessage(
            featureName: "autoconsent",
            method: method,
            id: nil,
            params: params,
            context: "test-context",
            extensionIdentifier: "test-extension-id"
        )
    }
}

// MARK: - Mock Classes

@available(macOS 15.4, iOS 18.4, *)
final class MockAutoconsentPreferences: AutoconsentPreferencesProviding {
    var isAutoconsentEnabled: Bool = false
}
