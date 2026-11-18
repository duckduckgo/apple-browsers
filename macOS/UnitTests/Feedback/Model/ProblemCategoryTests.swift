//
//  ProblemCategoryTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class ProblemCategoryTests: XCTestCase {

    // MARK: - Identifiable Protocol Tests

    func testWhenComparingProblemCategoriesWithSameIdThenTheyAreEqual() {
        let category1 = ProblemCategory(id: "same", text: "Name 1", subcategories: [])
        let category2 = ProblemCategory(id: "same", text: "Name 2", subcategories: [SubCategory(id: "different", text: "Different")])

        XCTAssertEqual(category1, category2)
    }

    func testWhenComparingProblemCategoriesWithDifferentIdThenTheyAreNotEqual() {
        let category1 = ProblemCategory(id: "id1", text: "Same Name", subcategories: [])
        let category2 = ProblemCategory(id: "id2", text: "Same Name", subcategories: [])

        XCTAssertNotEqual(category1, category2)
    }

    func testWhenUsingProblemCategoriesInSetThenOnlyUniqueIdsAreKept() {
        let category1 = ProblemCategory(id: "same", text: "Name 1", subcategories: [])
        let category2 = ProblemCategory(id: "same", text: "Name 2", subcategories: [SubCategory(id: "different", text: "Different")])
        let category3 = ProblemCategory(id: "different", text: "Name 3", subcategories: [])

        let categorySet: Set<ProblemCategory> = [category1, category2, category3]

        XCTAssertEqual(categorySet.count, 2)
        XCTAssertTrue(categorySet.contains(category1))
        XCTAssertTrue(categorySet.contains(category2))
        XCTAssertTrue(categorySet.contains(category3))
    }

    // MARK: - Static Categories Tests

    func testWhenAccessingAllCategoriesThenAllExpectedCategoriesArePresent() {
        let allCategories = ProblemCategory.allCategories

        let expectedIds = [
            "computer-or-browser-is-too-slow",
            "browser-doesnt-work-as-expected",
            "browser-install-and-updates",
            "report-broken-website",
            "ads-causing-issues",
            "password-issues",
            "something-else"
        ]

        XCTAssertEqual(allCategories.count, expectedIds.count)

        for expectedId in expectedIds {
            XCTAssertTrue(allCategories.contains { $0.id == expectedId }, "Missing category with id: \(expectedId)")
        }
    }

    func testWhenAccessingAllCategoriesThenSubcategoryIdsMatchBackendContract() {
        let expected: [String: [String]] = [
            "computer-or-browser-is-too-slow": [
                "browser-starts-slowly", "browser-uses-too-much-memory", "changing-tabs-takes-too-long",
                "new-tabs-open-slowly", "websites-load-slowly"
            ],
            "browser-doesnt-work-as-expected": [
                "browser-uses-too-much-memory", "camera-audio-permissions", "cant-restart-failed-downloads",
                "confusing-or-missing-settings", "logged-out-unexpectedly", "lost-tabs-or-history",
                "no-download-history", "popup-windows-not-opening", "too-many-captchas",
                "video-audio-plays-automatically", "video-doesnt-play"
            ],
            "browser-install-and-updates": [
                "browser-version-issues", "cant-control-updates", "installing", "uninstalling", "too-many-updates"
            ],
            "report-broken-website": [
                "site-wont-load", "site-looks-broken", "features-dont-work", "something-else"
            ],
            "ads-causing-issues": [
                "banner-ads-blocking-content", "distracting-animations-on-ads", "interrupting-pop-ups",
                "large-banner-ads", "site-asks-to-turn-off-ad-blocker"
            ],
            "password-issues": [
                "cant-sync-passwords", "exporting-passwords", "importing-passwords", "passwords-management"
            ],
            "something-else": [
                "cant-complete-a-purchase", "cant-restart-failed-downloads", "confusing-or-missing-settings",
                "no-downloads-history", "video-audio-plays-automatically", "promotional-messages"
            ]
        ]

        for category in ProblemCategory.allCategories {
            XCTAssertEqual(category.subcategories.map(\.id), expected[category.id], "category: \(category.id)")
        }
    }

    func testWhenAccessingAllCategoriesThenEachCategoryHasUniqueId() {
        let allCategories = ProblemCategory.allCategories
        let allIds = allCategories.map { $0.id }
        let uniqueIds = Set(allIds)

        XCTAssertEqual(allIds.count, uniqueIds.count, "Found duplicate category IDs")
    }

    func testWhenAccessingAllCategoriesThenAllSubcategoriesAreNonEmpty() {
        let allCategories = ProblemCategory.allCategories

        for category in allCategories {
            XCTAssertFalse(category.subcategories.isEmpty, "Category \(category.id) has empty subcategories")

            for subcategory in category.subcategories {
                XCTAssertFalse(subcategory.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                             "Category \(category.id) has empty subcategory")
            }
        }
    }
}
