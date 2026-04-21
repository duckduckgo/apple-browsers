//
//  TrackerDataQueryExtensionTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import TrackerRadarKit
@testable import BrowserServicesKit

final class TrackerDataQueryExtensionTests: XCTestCase {

    func testWhenHostHasAnEntityAssociatedAndEntityHasAParentThenReturnParent() throws {
        // GIVEN
        let tds = try JSONDecoder().decode(TrackerData.self, from: Self.mockTDS)

        // WHEN
        let result = try XCTUnwrap(tds.findParentEntityOrFallback(forHost: "www.instagram.com"))

        // THEN
        XCTAssertEqual(result.displayName, "Facebook")
    }

    func testWhenHostHasAnEntityAssociatedAndEntityDoesNotHaveAParentThenReturnEntityAssociated() throws {
        // GIVEN
        let tds = try JSONDecoder().decode(TrackerData.self, from: Self.mockTDS)

        // WHEN
        let result = try XCTUnwrap(tds.findParentEntityOrFallback(forHost: "www.roku.com"))

        // THEN
        XCTAssertEqual(result.displayName, "Roku")
    }

    func testWhenHostDoesNotHaveAnEntityAssociatedThenReturnNil() throws {
        // GIVEN
        let tds = try JSONDecoder().decode(TrackerData.self, from: Self.mockTDS)

        // WHEN
        let result = tds.findParentEntityOrFallback(forHost: "www.test.com")

        // THEN
        XCTAssertNil(result)
    }

}

private extension TrackerDataQueryExtensionTests {

    static let mockTDS = """
{
    "trackers": {
        "instagram.com": {
            "domain": "instagram.com",
            "owner": {
                "name": "Instagram",
                "displayName": "Instagram (Facebook)",
                "localizedName": "Instagram",
                "ownedBy": "Facebook, Inc."
            },
            "prevalence": 0.00573,
            "fingerprinting": 1,
            "cookies": 0.00139,
            "categories": [
                "Ad Motivated Tracking",
                "Advertising",
                "Embedded Content",
                "Social - Share",
                "Social Network"
            ],
            "default": "ignore",
            "rules": [
                {
                    "rule": "instagram\\.com\\/en_US\\/embeds\\.js",
                    "fingerprinting": 1,
                    "cookies": 0
                },
                {
                    "rule": "instagram\\.com\\/embed\\.js",
                    "fingerprinting": 1,
                    "cookies": 0
                },
                {
                    "rule": "instagram\\.com\\/ajax\\/bz",
                    "fingerprinting": 0,
                    "cookies": 0.000864
                },
                {
                    "rule": "instagram\\.com\\/logging\\/falco",
                    "fingerprinting": 0,
                    "cookies": 0.0000817
                },
                {
                    "rule": "instagram\\.com\\/static\\/bundles\\/es6\\/EmbedSDK\\.js\\/2fe3a16f6aeb\\.js",
                    "fingerprinting": 1,
                    "cookies": 0
                },
                {
                    "rule": "instagram\\.com\\/login\\/",
                    "fingerprinting": 0,
                    "cookies": 0,
                    "comment": "pixel"
                },
                {
                    "rule": "instagram\\.com\\/accounts\\/login\\/",
                    "fingerprinting": 0,
                    "cookies": 0,
                    "comment": "pixel"
                },
                {
                    "rule": "instagram\\.com\\/static\\/images\\/ig-badge-view-24\\.png",
                    "fingerprinting": 0,
                    "cookies": 0.0000408,
                    "comment": "pixel"
                },
                {
                    "rule": "instagram\\.com\\/static\\/images\\/ig-badge-view-sprite-24\\.png",
                    "fingerprinting": 0,
                    "cookies": 0.0000408,
                    "comment": "pixel"
                },
                {
                    "rule": "instagram\\.com\\/v1\\/users\\/self\\/media\\/recent",
                    "fingerprinting": 0,
                    "cookies": 0.0000613,
                    "comment": "pixel"
                }
            ]
        }
    },
    "entities": {
        "Facebook, Inc.": {
            "domains": [
                "accountkit.com",
                "atdmt.com",
                "atdmt2.com",
                "atlassbx.com",
                "atlassolutions.com",
                "cdninstagram.com",
                "crowdtangle.com",
                "facebook.com",
                "facebook.net",
                "facebookmail.com",
                "fb.com",
                "fb.gg",
                "fb.me",
                "fbcdn.net",
                "fbsbx.com",
                "fbthirdpartypixel.com",
                "fbthirdpartypixel.net",
                "fbthirdpartypixel.org",
                "flow.org",
                "flowtype.org",
                "graphql.org",
                "instagram.co",
                "liverail.com",
                "m.me",
                "messenger.com",
                "oculus.com",
                "oculuscdn.com",
                "oculusrift.com",
                "oculusvr.com",
                "onavo.com",
                "onavo.net",
                "onavo.org",
                "onavoinsights.com",
                "powersunitedvr.com",
                "reactjs.org",
                "thefind.com",
                "vircado.com",
                "wa.me",
                "whatsapp.com",
                "whatsapp.net",
                "wit.ai"
            ],
            "prevalence": 26.4,
            "displayName": "Facebook"
        },
        "Roku, Inc.": {
            "domains": [
                "dataxu.com",
                "ravm.net",
                "ravm.tv",
                "roku.com",
                "rokulabs.net",
                "rokutime.com",
                "w55c.net"
            ],
            "prevalence": 7.57,
            "displayName": "Roku"
        },
    },
    "Example Limited": {
        "domains": [
            "example.com",
            "examplerules.com"
        ],
        "prevalence": 1,
        "displayName": "Example Ltd"
    },
    "domains": {
        "instagram.com": "Instagram",
        "roku.com": "Roku, Inc.",
    },
    "cnames": {}
}
""".data(using: .utf8)!
}
