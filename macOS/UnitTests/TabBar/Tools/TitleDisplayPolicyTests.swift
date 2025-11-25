//
//  TitleDisplayPolicyTests.swift
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

import Testing
import Foundation
@testable import DuckDuckGo_Privacy_Browser

@Suite("TitleDisplayPolicy Tests", .serialized)
struct TitleDisplayPolicyTests {

    private let policy = DefaultTitleDisplayPolicy()

    // MARK: - Skipping Display Title

    @Test
    func testTitleIsSkippedWhenPreviousAndCurrentHostMatchAndLatestTitleIsPlaceholder() {
        let url = URL(string: "https://www.example.com/page")
        let previousURL = URL(string: "https://www.example.com/")
        let title = "example.com"

        #expect(policy.mustSkipDisplayingTitle(title: title, url: url, previousURL: previousURL) == true)
    }

    @Test
    func testTitleIsNotSkippedWhenHostDiffers() {
        let url = URL(string: "https://example.com/page")
        let previousURL = URL(string: "https://different.com/")
        let title = "example.com"

        #expect(policy.mustSkipDisplayingTitle(title: title, url: url, previousURL: previousURL) == false)
    }

    @Test
    func testTitleIsNotSkippedWhenLatestTitleIsNotPlaceholder() {
        let url = URL(string: "https://www.example.com/page")
        let previousURL = URL(string: "https://www.example.com/")
        let title = "Custom Page Title"

        #expect(policy.mustSkipDisplayingTitle(title: title, url: url, previousURL: previousURL) == false)
    }

    // MARK: - Title Transitions

    @Test
    func testTitleTransitionAnimatesWhenTitleChanges() {
        #expect(policy.mustAnimateTitleTransition(title: "New Title", previousTitle: "Old Title") == true)
    }

    @Test
    func testTitleTransitionDoesNotAnimateWhenIsTheSame() {
        #expect(policy.mustAnimateTitleTransition(title: "Same Title", previousTitle: "Same Title") == false)
    }

    @Test
    func testTitleTransitionDoesNotAnimateWhenPreviousTitleWasEmpty() {
        #expect(policy.mustAnimateTitleTransition(title: "New Title", previousTitle: "") == false)
    }

    // MARK: - New Title Fade In

    @Test
    func testTitleAnimatesFadeInWhenDomainDiffers() {
        let targetURL = URL(string: "https://example.com/page")
        let previousURL = URL(string: "https://different.com/page")

        #expect(policy.mustAnimateNewTitleFadeIn(targetURL: targetURL, previousURL: previousURL) == true)
    }

    @Test
    func testTitleDoesNotAnimateFadeInDomainMatches() {
        let targetURL = URL(string: "https://example.com/page1")
        let previousURL = URL(string: "https://example.com/page2")

        #expect(policy.mustAnimateNewTitleFadeIn(targetURL: targetURL, previousURL: previousURL) == false)
    }

    @Test
    func testTitleDoesNotAnimateFadeInWhenSameDomainDifferentSubdomains() {
        let targetURL = URL(string: "https://www.example.com/page")
        let previousURL = URL(string: "https://blog.example.com/page")

        #expect(policy.mustAnimateNewTitleFadeIn(targetURL: targetURL, previousURL: previousURL) == false)
    }
}
