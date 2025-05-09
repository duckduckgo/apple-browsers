//
//  AutofillUserScriptSourceProviderTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

final class AutofillUserScriptSourceProviderTests: XCTestCase {

    let embeddedConfig =
    """
    {
        "features": {
            "autofill": {
              "state": "enabled",
              "features": {
                "credentialsSaving": {
                  "state": "enabled",
                  "minSupportedVersion": "7.74.0"
                },
                "credentialsAutofill": {
                  "state": "enabled",
                  "minSupportedVersion": "7.74.0"
                },
                "inlineIconCredentials": {
                  "state": "enabled",
                  "minSupportedVersion": "7.74.0"
                },
                "accessCredentialManagement": {
                  "state": "enabled",
                  "minSupportedVersion": "7.74.0"
                },
                "autofillPasswordGeneration": {
                  "state": "enabled",
                  "minSupportedVersion": "7.75.0"
                },
                "onByDefault": {
                  "state": "enabled",
                  "minSupportedVersion": "7.93.0",
                  "rollout": {
                    "steps": [
                      {
                        "percent": 1
                      },
                      {
                        "percent": 10
                      },
                      {
                        "percent": 100
                      }
                    ]
                  }
                }
              },
              "hash": "ffaa2e81fb2bf264cb5ce2dadac549e1"
            },
            "contentBlocking": {
              "state": "enabled",
              "exceptions": [
                {
                  "domain": "test-domain.com"
                }
              ],
              "hash": "910e25ffe4d683b3c708a1578d097a16"
            },
            "voiceSearch": {
              "exceptions": [],
              "state": "disabled",
              "hash": "728493ef7a1488e4781656d3f9db84aa"
            }
        },
        "unprotectedTemporary": [],
        "unprotectedOtherKey": []
    }
    """.data(using: .utf8)!
    lazy var privacyConfig = AutofillTestHelper.preparePrivacyConfig(embeddedConfig: embeddedConfig)
    let properties = ContentScopeProperties(gpcEnabled: false, sessionKey: "1234", messageSecret: "1234", featureToggles: ContentScopeFeatureToggles.allTogglesOn)

    func testWhenBuildWithLoadJSThenSourceStrIsBuilt() {
        let autofillSourceProvider = DefaultAutofillSourceProvider.Builder(privacyConfigurationManager: privacyConfig,
                                                                           properties: properties)
            .withJSLoading()
            .build()
        XCTAssertFalse(autofillSourceProvider.source.isEmpty)
    }

    func testWhenBuildRuntimeConfigurationThenConfigurationIsBuilt() {
        let runtimeConfiguration = DefaultAutofillSourceProvider.Builder(privacyConfigurationManager: privacyConfig,
                                                                         properties: properties)
            .build()
            .buildRuntimeConfigResponse()

        XCTAssertNotNil(runtimeConfiguration)
        XCTAssertFalse(runtimeConfiguration!.isEmpty)
    }

    func testWhenBuildRuntimeConfigurationThenContentScopeContainsRequiredAutofillKeys() throws {
        let runtimeConfiguration = DefaultAutofillSourceProvider.Builder(privacyConfigurationManager: privacyConfig,
                                                                         properties: properties)
            .build()
            .buildRuntimeConfigResponse()

        let jsonData = runtimeConfiguration!.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
        let success = json?["success"] as? [String: Any]
        let contentScope = success?["contentScope"] as? [String: Any]
        let features = contentScope?["features"] as? [String: Any]
        XCTAssertNotNil(features?["autofill"] as? [String: Any])
        XCTAssertNotNil(contentScope?["unprotectedTemporary"] as? [Any])
        XCTAssertNil(features?["contentBlocking"])
    }

    func testWhenBuildRuntimeConfigurationThenContentScopeDoesNotContainUnnecessaryKeys() throws {
        let runtimeConfiguration = DefaultAutofillSourceProvider.Builder(privacyConfigurationManager: privacyConfig,
                                                                         properties: properties)
                                                                .build()
                                                                .buildRuntimeConfigResponse()

        let jsonData = runtimeConfiguration!.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
        let success = json?["success"] as? [String: Any]
        let contentScope = success?["contentScope"] as? [String: Any]
        XCTAssertNil(contentScope?["unprotectedOtherKey"])

        let features = contentScope?["features"] as? [String: Any]
        XCTAssertNil(features?["contentBlocking"])
        XCTAssertNil(features?["voiceSearch"])
    }
}
