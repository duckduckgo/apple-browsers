//
//  AutoconsentCompactRuleFilterTests.swift
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
@testable import PrivacyConfig

final class AutoconsentCompactRuleFilterTests: XCTestCase {

    // Sorted and indexed as autoconsent's encodeRules writes it: generic rules, then frame rules, then the other site rules.
    // r[4] holds runContext digits (main, frame): 1 = true, 0 = false, 2 = unset.
    private static let indexedRuleList = #"""
    {
      "v": 1,
      "s": ["#generic", "#generic-button", "#frame-generic", "#frame-site", "#site-a", "#site-b", "#shared"],
      "r": [
        [1, "generic", 0, "", 22, [0], [{ "e": 0 }], [{ "v": 0 }], [{ "c": 1 }], [], {}],
        [1, "frameGeneric", 0, "", 11, [], [{ "e": 2 }], [{ "v": 2 }], [{ "c": 2 }], [], {}],
        [1, "frameSite", 0, "^https?://consent\\.frame-cmp\\.example/", 1, [], [{ "e": 3 }], [{ "v": 3 }], [{ "c": 3 }], [], {}],
        [1, "siteA", 0, "^https?://(www\\.)?site-a\\.example/", 22, [], [{ "if": { "e": 4 }, "then": [{ "c": 4 }], "else": [{ "c": 6 }] }], [{ "v": 4 }], [{ "c": 4 }], [], {}],
        [1, "siteB", 0, "^https?://(www\\.)?site-b\\.example/", 10, [5], [{ "e": 5 }], [{ "v": 5 }], [{ "any": [{ "c": 5 }] }], [], {}],
        [3, "siteAStepV3", 0, "^https?://(www\\.)?site-a\\.example/", 22, [], [{ "exists": ["#host", "button"] }], [], [], [], {}]
      ],
      "index": {
        "genericRuleRange": [0, 2],
        "frameRuleRange": [1, 3],
        "specificRuleRange": [2, 6],
        "genericStringEnd": 3,
        "frameStringEnd": 4
      }
    }
    """#

    func testWhenFilteringThenEachFrameGetsOnlyTheRulesItCanRun() throws {
        let cases: [(url: String, isMainFrame: Bool, expected: [String])] = [
            ("https://example.com/", true, ["generic", "frameGeneric"]),
            ("https://www.site-a.example/page", true, ["generic", "frameGeneric", "siteA", "siteAStepV3"]),
            ("https://site-b.example/", true, ["generic", "frameGeneric", "siteB"]),
            ("https://consent.frame-cmp.example/", true, ["generic", "frameGeneric"]),
            ("https://ads.example/", false, ["frameGeneric"]),
            ("https://consent.frame-cmp.example/", false, ["frameGeneric", "frameSite"]),
            ("https://www.site-a.example/", false, ["frameGeneric"]),
        ]
        let filter = try makeFilter(Self.indexedRuleList)

        for testCase in cases {
            let filtered = filter.filter(url: testCase.url, isMainFrame: testCase.isMainFrame)
            XCTAssertEqual(ruleNames(filtered), testCase.expected, "\(testCase.url) mainFrame: \(testCase.isMainFrame)")
        }
    }

    func testWhenSiteRuleMatchesThenUnusedStringsAreBlankedAndIndicesKept() throws {
        for ruleList in [Self.indexedRuleList, try withoutIndex(Self.indexedRuleList)] {
            let filtered = try makeFilter(ruleList).filter(url: "https://www.site-a.example/", isMainFrame: true)

            XCTAssertEqual(filtered["s"] as? [String], ["#generic", "#generic-button", "#frame-generic", "", "#site-a", "", "#shared"])
        }
    }

    func testWhenNoSiteRuleMatchesThenStringsAfterTheLastUsedOneAreDropped() throws {
        let filtered = try makeFilter(Self.indexedRuleList).filter(url: "https://example.com/", isMainFrame: true)

        XCTAssertEqual(filtered["s"] as? [String], ["#generic", "#generic-button", "#frame-generic"])
    }

    func testWhenFilteringThenIndexIsOmittedBecauseItNoLongerMatchesTheRules() throws {
        let filtered = try makeFilter(Self.indexedRuleList).filter(url: "https://www.site-a.example/", isMainFrame: true)

        XCTAssertEqual(filtered["v"] as? Int, 1)
        XCTAssertNil(filtered["index"])
    }

    func testWhenRuleListHasAnUnknownShapeThenFilterIsNotCreated() throws {
        let ruleLists = [
            #"{ "v": 2, "s": [], "r": [] }"#,
            #"{ "v": 1, "s": [], "r": [[1, "short"]] }"#,
            ##"{ "v": 1, "s": ["#a"], "r": [[1, "outOfRange", 0, "", 22, [], [{ "e": 5 }], [], [], [], {}]] }"##,
            #"[1, 2, 3]"#,
        ]

        for ruleList in ruleLists {
            XCTAssertNil(AutoconsentCompactRuleFilter(ruleList: try parse(ruleList)), ruleList)
        }
    }

    func testWhenPatternCannotBeCompiledThenRuleIsKept() throws {
        let ruleList = ##"{ "v": 1, "s": ["#a"], "r": [[1, "brokenPattern", 0, "^https://(", 22, [], [{ "e": 0 }], [], [], [], {}]] }"##

        let filtered = try makeFilter(ruleList).filter(url: "https://example.com/", isMainFrame: true)

        XCTAssertEqual(ruleNames(filtered), ["brokenPattern"])
    }

    @MainActor
    func testWhenRuleListCannotBeFilteredThenItIsSentUnchanged() throws {
        let ruleList = try parse(##"{ "v": 2, "s": ["#a"], "r": [] }"##)

        let sent = AutoconsentCompactRuleFilter.ruleList(ruleList, frameURL: "https://example.com/", isMainFrame: true) as? [String: Any]

        XCTAssertEqual(sent?["v"] as? Int, 2)
        XCTAssertEqual(sent?["s"] as? [String], ["#a"])
    }

    @MainActor
    func testWhenRuleListChangesThenNewRulesAreFiltered() throws {
        let first = try parse(Self.indexedRuleList)
        let second = try parse(Self.indexedRuleList.replacingOccurrences(of: "\"generic\", 0", with: "\"renamedGeneric\", 0"))

        let firstSent = AutoconsentCompactRuleFilter.ruleList(first, frameURL: "https://example.com/", isMainFrame: true) as? [String: Any]
        let secondSent = AutoconsentCompactRuleFilter.ruleList(second, frameURL: "https://example.com/", isMainFrame: true) as? [String: Any]

        XCTAssertEqual(firstSent.map(ruleNames), ["generic", "frameGeneric"])
        XCTAssertEqual(secondSent.map(ruleNames), ["renamedGeneric", "frameGeneric"])
    }

    private func parse(_ json: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(json.utf8))
    }

    private func makeFilter(_ json: String) throws -> AutoconsentCompactRuleFilter {
        try XCTUnwrap(AutoconsentCompactRuleFilter(ruleList: try parse(json)))
    }

    private func withoutIndex(_ json: String) throws -> String {
        var ruleList = try XCTUnwrap(try parse(json) as? [String: Any])
        ruleList["index"] = nil
        return String(decoding: try JSONSerialization.data(withJSONObject: ruleList), as: UTF8.self)
    }

    private func ruleNames(_ ruleList: [String: Any]) -> [String] {
        (ruleList["r"] as? [[Any]] ?? []).compactMap { $0[1] as? String }
    }
}
