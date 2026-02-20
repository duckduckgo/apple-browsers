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

import XCTest
import Foundation
@testable import DuckDuckGo_Privacy_Browser

final class TitleDisplayPolicyTests: XCTestCase {

    private let policy = DefaultTitleDisplayPolicy()

    // MARK: - Skipping Display Title

    func testTitleIsSkippedWhenHostMatchesAndTitleIsPlaceholderWhileLoading() {
        let url = URL(string: "https://www.example.com/page")
        let previousURL = URL(string: "https://www.example.com/")
        let title = "example.com"

        XCTAssertTrue(policy.mustSkipDisplayingTitle(title: title, url: url, previousURL: previousURL, isLoading: true))
    }

    func testTitleIsNotSkippedWhenHostMatchesAndTitleIsPlaceholderAfterLoading() {
        let url = URL(string: "https://www.example.com/page")
        let previousURL = URL(string: "https://www.example.com/")
        let title = "example.com"

        XCTAssertFalse(policy.mustSkipDisplayingTitle(title: title, url: url, previousURL: previousURL, isLoading: false))
    }

    func testTitleIsNotSkippedWhenHostDiffers() {
        let url = URL(string: "https://example.com/page")
        let previousURL = URL(string: "https://different.com/")
        let title = "example.com"

        for isLoading in [true, false] {
            XCTAssertFalse(policy.mustSkipDisplayingTitle(title: title, url: url, previousURL: previousURL, isLoading: isLoading))
        }
    }

    func testTitleIsNotSkippedWhenLatestTitleIsNotPlaceholder() {
        let url = URL(string: "https://www.example.com/page")
        let previousURL = URL(string: "https://www.example.com/")
        let title = "Custom Page Title"

        for isLoading in [true, false] {
            XCTAssertFalse(policy.mustSkipDisplayingTitle(title: title, url: url, previousURL: previousURL, isLoading: isLoading))
        }
    }

    // MARK: - Title Transitions

    func testTitleTransitionAnimatesWhenTitleChanges() {
        XCTAssertTrue(policy.mustAnimateTitleTransition(title: "New Title", previousTitle: "Old Title") == true)
    }

    func testTitleTransitionDoesNotAnimateWhenIsTheSame() {
        XCTAssertTrue(policy.mustAnimateTitleTransition(title: "Same Title", previousTitle: "Same Title") == false)
    }

    func testTitleTransitionDoesNotAnimateWhenPreviousTitleWasEmpty() {
        XCTAssertTrue(policy.mustAnimateTitleTransition(title: "New Title", previousTitle: "") == false)
    }

    // MARK: - New Title Fade In

    func testTitleAnimatesFadeInWhenDomainDiffers() {
        let targetURL = URL(string: "https://example.com/page")
        let previousURL = URL(string: "https://different.com/page")

        XCTAssertTrue(policy.mustAnimateNewTitleFadeIn(targetURL: targetURL, previousURL: previousURL) == true)
    }

    func testTitleDoesNotAnimateFadeInDomainMatches() {
        let targetURL = URL(string: "https://example.com/page1")
        let previousURL = URL(string: "https://example.com/page2")

        XCTAssertTrue(policy.mustAnimateNewTitleFadeIn(targetURL: targetURL, previousURL: previousURL) == false)
    }

    func testTitleDoesNotAnimateFadeInWhenSameDomainDifferentSubdomains() {
        let targetURL = URL(string: "https://www.example.com/page")
        let previousURL = URL(string: "https://blog.example.com/page")

        XCTAssertTrue(policy.mustAnimateNewTitleFadeIn(targetURL: targetURL, previousURL: previousURL) == false)
    }
}
