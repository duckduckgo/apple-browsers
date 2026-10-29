//
//  MultiTabAttachmentCandidateFilterTests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo

final class MultiTabAttachmentCandidateFilterTests: XCTestCase {
    func testWhenTitleAndAddressMatchThenScoresAreAdditiveAndTiesKeepInputOrder() {
        let candidates = [
            candidate("address", title: "Page", address: "https://example.com/wiki"),
            candidate("title", title: "Wikipedia", address: "https://example.com"),
            candidate("both-second-id", title: "Wikipedia B", address: "https://wikipedia.org/B"),
            candidate("both-first-id", title: "Wikipedia A", address: "https://wikipedia.org/A")
        ]

        let result = MultiTabAttachmentCandidateFilter.filter(candidates, query: "WIKI")

        XCTAssertEqual(result.map(\.tabId), ["both-second-id", "both-first-id", "title", "address"])
    }

    func testWhenCurrentTabMatchesThenItPrecedesHigherScoringResults() {
        let candidates = [
            candidate("best", title: "Wikipedia", address: "https://wikipedia.org"),
            candidate("current", title: "Page", address: "https://example.com/wiki", isCurrentTab: true)
        ]

        XCTAssertEqual(MultiTabAttachmentCandidateFilter.filter(candidates, query: "wiki").map(\.tabId), ["current", "best"])
    }

    func testWhenCurrentTabDoesNotMatchThenItIsExcluded() {
        let candidates = [
            candidate("current", title: "Other", address: "https://example.com", isCurrentTab: true),
            candidate("match", title: "Wikipedia", address: "https://wikipedia.org")
        ]

        XCTAssertEqual(MultiTabAttachmentCandidateFilter.filter(candidates, query: "wiki").map(\.tabId), ["match"])
    }

    func testWhenQueryIsEmptyOrHasNoMatchesThenReturnsOriginalOrderOrEmptyResults() {
        let candidates = [
            candidate("current", title: "Wiki", address: "https://example.com", isCurrentTab: true),
            candidate("other", title: "Other", address: "https://other.example.com")
        ]

        XCTAssertEqual(MultiTabAttachmentCandidateFilter.filter(candidates, query: ""), candidates)
        XCTAssertTrue(MultiTabAttachmentCandidateFilter.filter(candidates, query: "missing").isEmpty)
        XCTAssertTrue(MultiTabAttachmentCandidateFilter.filter(candidates, query: "wiki ").isEmpty)
    }

    private func candidate(_ id: String, title: String, address: String, isCurrentTab: Bool = false) -> MultiTabAttachmentCandidate {
        MultiTabAttachmentCandidate(tabId: id, title: title, url: URL(string: address)!, isCurrentTab: isCurrentTab)
    }
}
