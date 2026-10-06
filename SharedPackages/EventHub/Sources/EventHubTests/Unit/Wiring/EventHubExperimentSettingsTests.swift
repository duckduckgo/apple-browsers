//
//  EventHubExperimentSettingsTests.swift
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

import Testing
import Foundation
import PrivacyConfig
import PrivacyConfigTestsUtils
@testable import EventHub

/// The step that finds the experiments declaring metrics, reading a real `AppPrivacyConfiguration`.
///
/// The metrics specification suite injects its experiment settings straight into the hub, which is
/// what keeps those 18 cases readable — but it means the reading itself runs in no case there. In
/// particular M-SEL-8's claim that *both* experiment parent features are read is invisible to that
/// suite: removing a parent from `parentFeatures` leaves every spec case green. This is where that
/// claim is pinned.
@Suite("EventHubExperimentSettings")
struct EventHubExperimentSettingsTests {

    /// A privacy config with one experiment under each parent feature that may declare metrics, using
    /// the specification fixture's own IDs: CSS experiments live under `contentScopeExperiments`, and
    /// on Apple TDS experiments live under `contentBlocking`.
    private static let bothParents = """
    {
        "readme": "test",
        "version": 1,
        "features": {
            "contentScopeExperiments": {
                "state": "enabled",
                "exceptions": [],
                "features": {
                    "contentScopeExperiment1": {
                        "state": "enabled",
                        "settings": { "metrics": { "captchaSeen": { "event": "captchaDetected" } } }
                    }
                }
            },
            "contentBlocking": {
                "state": "enabled",
                "exceptions": [],
                "features": {
                    "tdsNextExperiment007": {
                        "state": "enabled",
                        "settings": { "metrics": { "pageLoad": { "event": "pageLoaded" } } }
                    }
                }
            }
        },
        "unprotectedTemporary": []
    }
    """

    private func configuration(_ json: String) throws -> AppPrivacyConfiguration {
        let data = try PrivacyConfigurationData(data: Data(json.utf8))
        return AppPrivacyConfiguration(data: data,
                                       identifier: "test",
                                       localProtection: MockDomainsProtectionStore(),
                                       internalUserDecider: MockInternalUserDecider())
    }

    @Test("both experiment parent features are read")
    func bothExperimentParentFeaturesAreRead() throws {
        // The wiring leg of M-SEL-8. Drop either entry from `parentFeatures` and this fails — which is
        // exactly what the specification suite cannot see.
        let result = EventHubExperimentSettings.current(try configuration(Self.bothParents))

        #expect(result.keys.sorted() == ["contentScopeExperiment1", "tdsNextExperiment007"])
        #expect(result["contentScopeExperiment1"]?.contains("captchaSeen") == true)
        #expect(result["tdsNextExperiment007"]?.contains("pageLoad") == true)
    }

    @Test("parentFeatures names exactly the two features metrics may be declared under")
    func parentFeaturesNamesTheTwoExperimentParents() {
        // Stated as its own expectation so a change to the list is a deliberate act, not a side effect.
        #expect(EventHubExperimentSettings.parentFeatures == [.contentScopeExperiments, .contentBlocking])
    }

    @Test("a subfeature with no settings is omitted")
    func aSubfeatureWithNoSettingsIsOmitted() throws {
        let result = EventHubExperimentSettings.current(try configuration("""
        {
            "readme": "test",
            "version": 1,
            "features": {
                "contentScopeExperiments": {
                    "state": "enabled",
                    "exceptions": [],
                    "features": {
                        "withSettings":    { "state": "enabled", "settings": { "metrics": {} } },
                        "withoutSettings": { "state": "enabled" }
                    }
                }
            },
            "unprotectedTemporary": []
        }
        """))

        #expect(result.keys.sorted() == ["withSettings"])
    }

    @Test("on a subfeature ID present under both parents, the first parent listed wins")
    func onACollisionTheFirstParentListedWins() throws {
        // Documented behaviour of `current(_:)`, and arbitrary by design — nothing downstream depends
        // on which parent a metric came from, since a conversion request names only the subfeature.
        // Pinned so the arbitrary choice cannot change unnoticed.
        let result = EventHubExperimentSettings.current(try configuration("""
        {
            "readme": "test",
            "version": 1,
            "features": {
                "contentScopeExperiments": {
                    "state": "enabled",
                    "exceptions": [],
                    "features": { "sharedID": { "state": "enabled", "settings": { "from": "css" } } }
                },
                "contentBlocking": {
                    "state": "enabled",
                    "exceptions": [],
                    "features": { "sharedID": { "state": "enabled", "settings": { "from": "tds" } } }
                }
            },
            "unprotectedTemporary": []
        }
        """))

        #expect(result.count == 1)
        #expect(result["sharedID"]?.contains("css") == true)
    }

    @Test("a config declaring no experiment features yields nothing")
    func aConfigWithNoExperimentFeaturesYieldsNothing() throws {
        let result = EventHubExperimentSettings.current(try configuration("""
        { "readme": "test", "version": 1, "features": {}, "unprotectedTemporary": [] }
        """))

        #expect(result.isEmpty)
    }
}
