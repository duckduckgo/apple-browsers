//
//  PrivacyConfigurationDataTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import CommonCrypto
@testable import BrowserServicesKit

class PrivacyConfigurationDataTests: XCTestCase {

    private var data = JsonTestDataLoader()

    func testJSONParsing() throws {
        let jsonData = data.fromJsonFile("Resources/privacy-config-example.json")
        let configData = try PrivacyConfigurationData(data: jsonData)

        XCTAssertEqual(configData.version, "2021.6.7")

        XCTAssertEqual(configData.unprotectedTemporary.count, 1)
        XCTAssertEqual(configData.unprotectedTemporary.first?.domain, "example.com")

        let duckPlayerFeature = configData.features["duckPlayer"]
        XCTAssertNotNil(duckPlayerFeature)
        XCTAssertEqual(duckPlayerFeature?.state, "enabled")

        let windowsWaitlistFeature = configData.features["windowsWaitlist"]
        XCTAssertNotNil(windowsWaitlistFeature)
        XCTAssertEqual(windowsWaitlistFeature?.state, "enabled")

        let windowsDownloadLinkFeature = configData.features["windowsDownloadLink"]
        XCTAssertNotNil(windowsDownloadLinkFeature)
        XCTAssertEqual(windowsDownloadLinkFeature?.state, "disabled")

        let newTabContinueSetUp = configData.features["newTabContinueSetUp"]
        XCTAssertNotNil(newTabContinueSetUp)
        XCTAssertEqual(newTabContinueSetUp?.state, "enabled")

        let gpcFeature = configData.features["contentBlocking"]
        XCTAssertNotNil(gpcFeature)
        XCTAssertEqual(gpcFeature?.state, "enabled")
        XCTAssertEqual(gpcFeature?.exceptions.first?.domain, "example.com")

        let exampleFeature = configData.features["exampleFeature"]
        XCTAssertEqual(exampleFeature?.state, "enabled")
        XCTAssertEqual((exampleFeature?.settings["dictValue"] as? [String: String])?["key"], "value")
        XCTAssertEqual((exampleFeature?.settings["arrayValue"] as? [String])?.first, "value")
        XCTAssertEqual((exampleFeature?.settings["stringValue"] as? String), "value")
        XCTAssertEqual((exampleFeature?.settings["numericalValue"] as? Int), 1)

        if let subfeatures = exampleFeature?.features {
            XCTAssertEqual(subfeatures["disabledSubfeature"]?.state, "disabled")
            XCTAssertEqual(subfeatures["minSupportedSubfeature"]?.minSupportedVersion, "1.36.0")
            XCTAssertEqual(subfeatures["enabledSubfeature"]?.state, "enabled")
            XCTAssertEqual(subfeatures["enabledSubfeature"]?.cohorts?.count, 3)
            XCTAssertEqual(subfeatures["enabledSubfeature"]?.cohorts?[0].name, "myExperimentControl")
            XCTAssertEqual(subfeatures["enabledSubfeature"]?.cohorts?[0].weight, 1)
            XCTAssertEqual(subfeatures["enabledSubfeature"]?.targets?[0].localeCountry, "US")
            XCTAssertEqual(subfeatures["enabledSubfeature"]?.targets?[0].localeLanguage, "fr")
            XCTAssertEqual(subfeatures["enabledSubfeature"]?.settings, "{\"foo\":\"foo\\/value\",\"bar\":\"bar\\/value\"}")
            XCTAssertEqual(subfeatures["internalSubfeature"]?.state, "internal")
        } else {
            XCTFail("Could not parse subfeatures")
        }

        let allowlist = configData.trackerAllowlist
        XCTAssertEqual(allowlist.state, "enabled")
        let rulesMap = allowlist.entries.reduce(into: [String: [String]]()) { partialResult, entry in
            for e in entry.value {
                partialResult[e.rule] = e.domains
            }
        }
        XCTAssertEqual(rulesMap["example.com/tracker.js"], ["test.com"])
        XCTAssertEqual(rulesMap["example2.com/path/"], ["<all>"])
        XCTAssertEqual(rulesMap["example2.com/resource.json"], ["<all>"])
    }

    func testJSONWithoutAllowlistParsing() {
        let jsonData = data.fromJsonFile("Resources/privacy-config-example.json")
        var json = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
        var features = json?["features"] as? [String: Any]
        features?.removeValue(forKey: "trackerAllowlist")
        json?["features"] = features

        let configData = PrivacyConfigurationData(json: json!)

        XCTAssertEqual(configData.unprotectedTemporary.count, 1)
        XCTAssertEqual(configData.unprotectedTemporary.first?.domain, "example.com")

        let duckPlayerFeature = configData.features["duckPlayer"]
        XCTAssertNotNil(duckPlayerFeature)
        XCTAssertEqual(duckPlayerFeature?.state, "enabled")

        let windowsWaitlistFeature = configData.features["windowsWaitlist"]
        XCTAssertNotNil(windowsWaitlistFeature)
        XCTAssertEqual(windowsWaitlistFeature?.state, "enabled")

        let windowsDownloadLinkFeature = configData.features["windowsDownloadLink"]
        XCTAssertNotNil(windowsDownloadLinkFeature)
        XCTAssertEqual(windowsDownloadLinkFeature?.state, "disabled")

        let newTabContinueSetUp = configData.features["newTabContinueSetUp"]
        XCTAssertNotNil(newTabContinueSetUp)
        XCTAssertEqual(newTabContinueSetUp?.state, "enabled")

        let gpcFeature = configData.features["contentBlocking"]
        XCTAssertNotNil(gpcFeature)
        XCTAssertEqual(gpcFeature?.state, "enabled")
        XCTAssertEqual(gpcFeature?.exceptions.first?.domain, "example.com")

        let exampleFeature = configData.features["exampleFeature"]
        XCTAssertEqual(exampleFeature?.state, "enabled")
        XCTAssertEqual((exampleFeature?.settings["dictValue"] as? [String: String])?["key"], "value")
        XCTAssertEqual((exampleFeature?.settings["arrayValue"] as? [String])?.first, "value")
        XCTAssertEqual((exampleFeature?.settings["stringValue"] as? String), "value")
        XCTAssertEqual((exampleFeature?.settings["numericalValue"] as? Int), 1)

        let allowlist = configData.trackerAllowlist
        XCTAssertEqual(allowlist.state, "disabled")
        XCTAssertEqual(allowlist.entries.count, 0)
    }

    func testRoundTripEncodingDecoding() throws {
        // Load the JSON from the file.
        let jsonData = data.fromJsonFile("Resources/privacy-config-example.json")
        let originalConfig = try PrivacyConfigurationData(data: jsonData)

        // Re-Encode the original config
        let encodedJsonData = try originalConfig.toJSONData()

        // De-decode the config into PrivacyConfigurationData
        let roundTrippedConfig = try PrivacyConfigurationData(data: encodedJsonData)

        // Check de-decoded PrivacyConfigurationData contains correct fields
        XCTAssertEqual(roundTrippedConfig.version, "2021.6.7")

        XCTAssertEqual(roundTrippedConfig.unprotectedTemporary.count, 1)
        XCTAssertEqual(roundTrippedConfig.unprotectedTemporary.first?.domain, "example.com")

        let duckPlayerFeature = roundTrippedConfig.features["duckPlayer"]
        XCTAssertNotNil(duckPlayerFeature)
        XCTAssertEqual(duckPlayerFeature?.state, "enabled")

        let windowsWaitlistFeature = roundTrippedConfig.features["windowsWaitlist"]
        XCTAssertNotNil(windowsWaitlistFeature)
        XCTAssertEqual(windowsWaitlistFeature?.state, "enabled")

        let windowsDownloadLinkFeature = roundTrippedConfig.features["windowsDownloadLink"]
        XCTAssertNotNil(windowsDownloadLinkFeature)
        XCTAssertEqual(windowsDownloadLinkFeature?.state, "disabled")

        let newTabContinueSetUp = roundTrippedConfig.features["newTabContinueSetUp"]
        XCTAssertNotNil(newTabContinueSetUp)
        XCTAssertEqual(newTabContinueSetUp?.state, "enabled")

        let gpcFeature = roundTrippedConfig.features["contentBlocking"]
        XCTAssertNotNil(gpcFeature)
        XCTAssertEqual(gpcFeature?.state, "enabled")
        XCTAssertEqual(gpcFeature?.exceptions.first?.domain, "example.com")

        let exampleFeature = roundTrippedConfig.features["exampleFeature"]
        XCTAssertEqual(exampleFeature?.state, "enabled")
        XCTAssertEqual((exampleFeature?.settings["dictValue"] as? [String: String])?["key"], "value")
        XCTAssertEqual((exampleFeature?.settings["arrayValue"] as? [String])?.first, "value")
        XCTAssertEqual((exampleFeature?.settings["stringValue"] as? String), "value")
        XCTAssertEqual((exampleFeature?.settings["numericalValue"] as? Int), 1)

        if let subfeatures = exampleFeature?.features {
            XCTAssertEqual(subfeatures["disabledSubfeature"]?.state, "disabled")
            XCTAssertEqual(subfeatures["minSupportedSubfeature"]?.minSupportedVersion, "1.36.0")
            XCTAssertEqual(subfeatures["enabledSubfeature"]?.state, "enabled")
            XCTAssertEqual(subfeatures["enabledSubfeature"]?.cohorts?.count, 3)
            XCTAssertEqual(subfeatures["enabledSubfeature"]?.cohorts?[0].name, "myExperimentControl")
            XCTAssertEqual(subfeatures["enabledSubfeature"]?.cohorts?[0].weight, 1)
            XCTAssertEqual(subfeatures["enabledSubfeature"]?.targets?[0].localeCountry, "US")
            XCTAssertEqual(subfeatures["enabledSubfeature"]?.targets?[0].localeLanguage, "fr")
            XCTAssertEqual(subfeatures["enabledSubfeature"]?.settings, "{\"foo\":\"foo\\/value\",\"bar\":\"bar\\/value\"}")
            XCTAssertEqual(subfeatures["internalSubfeature"]?.state, "internal")
        } else {
            XCTFail("Could not parse subfeatures")
        }

        let allowlist = roundTrippedConfig.trackerAllowlist
        XCTAssertEqual(allowlist.state, "enabled")
        let rulesMap = allowlist.entries.reduce(into: [String: [String]]()) { partialResult, entry in
            for e in entry.value {
                partialResult[e.rule] = e.domains
            }
        }
        XCTAssertEqual(rulesMap["example.com/tracker.js"], ["test.com"])
        XCTAssertEqual(rulesMap["example2.com/path/"], ["<all>"])
        XCTAssertEqual(rulesMap["example2.com/resource.json"], ["<all>"])
    }
}
