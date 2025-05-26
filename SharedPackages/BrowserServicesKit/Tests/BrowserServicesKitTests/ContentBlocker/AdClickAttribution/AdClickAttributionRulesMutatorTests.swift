//
//  AdClickAttributionRulesMutatorTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
@testable import TrackerRadarKit

final class MockAttributionConfig: AdClickAttributing {

    func isMatchingAttributionFormat(_ url: URL) -> Bool {
        return true
    }

    func attributionDomainParameterName(for: URL) -> String? {
        return nil
    }

    var isEnabled = true
    var allowlist = [AdClickAttributionFeature.AllowlistEntry]()
    var navigationExpiration: Double = 0
    var totalExpiration: Double = 0
    var isHeuristicDetectionEnabled: Bool = true
    var isDomainDetectionEnabled: Bool = true

}

final class AdClickAttributionRulesMutatorTests: XCTestCase {

    let exampleTDS = """
{
    "trackers": {
        "example.com": {
            "domain": "example.com",
            "owner": {
                "name": "Example Limited",
                "displayName": "Example Ltd"
            },
            "prevalence": 0.0001,
            "fingerprinting": 1,
            "cookies": 0,
            "categories": [],
            "default": "block"
        },
        "examplerules.com": {
            "domain": "examplerules.com",
            "owner": {
                "name": "Example Limited",
                "displayName": "Example Ltd"
            },
            "prevalence": 0.0001,
            "fingerprinting": 1,
            "cookies": 0,
            "categories": [],
            "default": "block",
            "rules": [
                {
                    "rule": "example.com/customrule/1.js",
                    "action": "ignore"
                }
            ]
        }
    },
    "entities": {
        "Example Limited": {
            "domains": [
                "example.com",
                "examplerules.com"
            ],
            "prevalence": 1,
            "displayName": "Example Ltd"
        }
    },
    "domains": {
        "example.com": "Example Limited"
    },
    "cnames": {}
}
""".data(using: .utf8)!

    func isEqualAsJson<T: Encodable>(l: T?, r: T?) throws -> Bool {
        guard let l = l, let r = r else {
            XCTFail("Could not encode objects")
            return false
        }

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .sortedKeys

        let lData = try jsonEncoder.encode(l)
        let rData = try jsonEncoder.encode(r)

        return String(data: lData, encoding: .utf8) == String(data: rData, encoding: .utf8)
    }

    func testWhenEntityIsOnAllowlistThenRuleIsApplied() throws {
        let trackerData = try JSONDecoder().decode(TrackerData.self, from: exampleTDS)

        let mockConfig = MockAttributionConfig()
        mockConfig.allowlist.append(AdClickAttributionFeature.AllowlistEntry(entity: "example.com", host: "test.com"))

        let mutator = AdClickAttributionRulesMutator(trackerData: trackerData, config: mockConfig)
        let attributedRules = mutator.addException(vendorDomain: "vendor.com")

        XCTAssertNotNil(attributedRules.trackers["example.com"])
        XCTAssertFalse(try isEqualAsJson(l: attributedRules.trackers["example.com"], r: trackerData.trackers["example.com"]))

        XCTAssertEqual(attributedRules.trackers["example.com"]?.rules?.count, 1)
        XCTAssertEqual(attributedRules.trackers["example.com"]?.rules?.first?.rule, "test\\.com(:[0-9]+)?/.*")
        XCTAssertEqual(attributedRules.trackers["example.com"]?.rules?.first?.exceptions?.domains, ["vendor.com"])

        XCTAssert(try isEqualAsJson(l: attributedRules.trackers["examplerules.com"], r: trackerData.trackers["examplerules.com"]))

        XCTAssertEqual(trackerData.domains, attributedRules.domains)
        XCTAssertEqual(trackerData.entities, attributedRules.entities)
        XCTAssertEqual(trackerData.cnames, attributedRules.cnames)
    }

    func testWhenEntityHasMultipleEntriesOnAllowlistThenAllRulesAreApplied() throws {
        let trackerData = try JSONDecoder().decode(TrackerData.self, from: exampleTDS)

        let mockConfig = MockAttributionConfig()
        mockConfig.allowlist.append(AdClickAttributionFeature.AllowlistEntry(entity: "example.com", host: "test.com"))
        mockConfig.allowlist.append(AdClickAttributionFeature.AllowlistEntry(entity: "example.com", host: "test.org"))

        let mutator = AdClickAttributionRulesMutator(trackerData: trackerData, config: mockConfig)
        let attributedRules = mutator.addException(vendorDomain: "vendor.com")

        XCTAssertNotNil(attributedRules.trackers["example.com"])
        XCTAssertEqual(attributedRules.trackers["example.com"]?.rules?.count, 2)
        XCTAssertEqual(attributedRules.trackers["example.com"]?.rules?.first?.rule, "test\\.org(:[0-9]+)?/.*")
        XCTAssertEqual(attributedRules.trackers["example.com"]?.rules?.first?.exceptions?.domains, ["vendor.com"])
        XCTAssertEqual(attributedRules.trackers["example.com"]?.rules?.last?.rule, "test\\.com(:[0-9]+)?/.*")
        XCTAssertEqual(attributedRules.trackers["example.com"]?.rules?.last?.exceptions?.domains, ["vendor.com"])

        XCTAssertEqual(attributedRules.trackers["examplerules.com"], trackerData.trackers["examplerules.com"])

        XCTAssertEqual(trackerData.domains, attributedRules.domains)
        XCTAssertEqual(trackerData.entities, attributedRules.entities)
        XCTAssertEqual(trackerData.cnames, attributedRules.cnames)
    }

    func testWhenEntityIsNotOnAllowlistThenNothingChanges() throws {
        let trackerData = try JSONDecoder().decode(TrackerData.self, from: exampleTDS)

        let mockConfig = MockAttributionConfig()
        mockConfig.allowlist.append(AdClickAttributionFeature.AllowlistEntry(entity: "other.com", host: "test.com"))

        let mutator = AdClickAttributionRulesMutator(trackerData: trackerData, config: mockConfig)
        let attributedRules = mutator.addException(vendorDomain: "vendor.com")

        XCTAssert(try isEqualAsJson(l: attributedRules.trackers["example.com"], r: trackerData.trackers["example.com"]))
        XCTAssert(try isEqualAsJson(l: attributedRules.trackers["examplerules.com"], r: trackerData.trackers["examplerules.com"]))

        XCTAssertEqual(trackerData.trackers, attributedRules.trackers)
        XCTAssertEqual(trackerData.domains, attributedRules.domains)
        XCTAssertEqual(trackerData.entities, attributedRules.entities)
        XCTAssertEqual(trackerData.cnames, attributedRules.cnames)
    }

    func testWhenEntityExistingRulesThenTheyAreMergedWithAdditonalOnesAndAttributionsAreFirst() throws {
        let trackerData = try JSONDecoder().decode(TrackerData.self, from: exampleTDS)

        let mockConfig = MockAttributionConfig()
        mockConfig.allowlist.append(AdClickAttributionFeature.AllowlistEntry(entity: "example.com", host: "test.com"))
        mockConfig.allowlist.append(AdClickAttributionFeature.AllowlistEntry(entity: "examplerules.com", host: "test.org"))

        let mutator = AdClickAttributionRulesMutator(trackerData: trackerData, config: mockConfig)
        let attributedRules = mutator.addException(vendorDomain: "vendor.com")

        XCTAssertFalse(try isEqualAsJson(l: attributedRules.trackers["example.com"], r: trackerData.trackers["example.com"]))
        XCTAssertFalse(try isEqualAsJson(l: attributedRules.trackers["examplerules.com"], r: trackerData.trackers["examplerules.com"]))

        XCTAssertNotNil(attributedRules.trackers["example.com"])
        XCTAssertEqual(attributedRules.trackers["example.com"]?.rules?.count, 1)
        XCTAssertEqual(attributedRules.trackers["example.com"]?.rules?.first?.rule, "test\\.com(:[0-9]+)?/.*")
        XCTAssertEqual(attributedRules.trackers["example.com"]?.rules?.first?.exceptions?.domains, ["vendor.com"])

        XCTAssertNotNil(attributedRules.trackers["examplerules.com"])
        XCTAssertEqual(attributedRules.trackers["examplerules.com"]?.rules?.count, 2)
        XCTAssertEqual(attributedRules.trackers["examplerules.com"]?.rules?.first?.rule, "test\\.org(:[0-9]+)?/.*")
        XCTAssertEqual(attributedRules.trackers["examplerules.com"]?.rules?.first?.exceptions?.domains, ["vendor.com"])
        XCTAssertEqual(attributedRules.trackers["examplerules.com"]?.rules?.last?.rule, "example.com/customrule/1.js")
        XCTAssertNil(attributedRules.trackers["examplerules.com"]?.rules?.last?.exceptions?.domains)

        XCTAssertEqual(trackerData.domains, attributedRules.domains)
        XCTAssertEqual(trackerData.entities, attributedRules.entities)
        XCTAssertEqual(trackerData.cnames, attributedRules.cnames)
    }
}
