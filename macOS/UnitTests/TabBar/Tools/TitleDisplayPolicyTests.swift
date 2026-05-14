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
        let previousTitle = "example.com"

        XCTAssertTrue(policy.mustSkipDisplayingTitle(title: title, url: url, previousTitle: previousTitle, previousURL: previousURL, isLoading: true))
    }

    func testTitleIsNotSkippedWhenHostAndTitlesMatchAfterLoading() {
        let url = URL(string: "https://www.example.com/page")
        let previousURL = URL(string: "https://www.example.com/")
        let title = "example.com page"
        let previousTitle = title

        XCTAssertFalse(policy.mustSkipDisplayingTitle(title: title, url: url, previousTitle: previousTitle, previousURL: previousURL, isLoading: false))
    }

    func testTitleIsNotSkippedWhenHostDifferAndTitleIsPlaceholderWhileLoading() {
        let url = URL(string: "https://example.com/page")
        let previousURL = URL(string: "https://different.com/")
        let title = "example.com"
        let previousTitle = "example.com page"

        XCTAssertFalse(policy.mustSkipDisplayingTitle(title: title, url: url, previousTitle: previousTitle, previousURL: previousURL, isLoading: true))
    }

    func testTitleIsNotSkippedWhenLatestTitleIsNotPlaceholder() {
        let url = URL(string: "https://www.example.com/page")
        let previousURL = URL(string: "https://www.example.com/")
        let title = "Custom Page Title"
        let previousTitle = "example.com"

        for isLoading in [true, false] {
            XCTAssertFalse(policy.mustSkipDisplayingTitle(title: title, url: url, previousTitle: previousTitle, previousURL: previousURL, isLoading: isLoading))
        }
    }

    func testTitleIsSkippedWhenHostDiffersButTitlesMatch() {
        let url = URL(string: "https://www.example.com/")
        let previousURL = URL(string: "https://www.different.com/")
        let title = "Custom Page Title"
        let previousTitle = title

        for isLoading in [true, false] {
            XCTAssertTrue(policy.mustSkipDisplayingTitle(title: title, url: url, previousTitle: previousTitle, previousURL: previousURL, isLoading: isLoading))
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
}
