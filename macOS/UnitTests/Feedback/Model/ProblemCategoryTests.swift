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

    // MARK: - Initialization Tests

    func testWhenInitializingProblemCategoryThenPropertiesAreSetCorrectly() {
        let category = ProblemCategory(
            id: "testId",
            text: "Test Category",
            subcategories: [SubCategory(id: "sub1", text: "Sub 1"), SubCategory(id: "sub2", text: "Sub 2")]
        )

        XCTAssertEqual(category.id, "testId")
        XCTAssertEqual(category.text, "Test Category")
        XCTAssertEqual(category.subcategories.map(\.text), ["Sub 1", "Sub 2"])
    }

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

    // MARK: - Hashable Protocol Tests

    func testWhenHashingProblemCategoriesWithSameIdThenHashesAreEqual() {
        let category1 = ProblemCategory(id: "same", text: "Name 1", subcategories: [])
        let category2 = ProblemCategory(id: "same", text: "Name 2", subcategories: [SubCategory(id: "different", text: "Different")])

        XCTAssertEqual(category1.hashValue, category2.hashValue)
    }

    func testWhenHashingProblemCategoriesWithDifferentIdThenHashesAreDifferent() {
        let category1 = ProblemCategory(id: "id1", text: "Same Name", subcategories: [])
        let category2 = ProblemCategory(id: "id2", text: "Same Name", subcategories: [])

        XCTAssertNotEqual(category1.hashValue, category2.hashValue)
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

    func testWhenAccessingBrowserTooSlowCategoryThenSubcategoriesAreCorrect() {
        let category = ProblemCategory.allCategories.first { $0.id == "computer-or-browser-is-too-slow" }!

        let expectedSubcategories = [
            UserText.problemSubcategoryBrowserStartsSlowly,
            UserText.problemSubcategoryBrowserUsesTooMuchMemory,
            UserText.problemSubcategoryChangingTabsTakesTooLong,
            UserText.problemSubcategoryNewTabsOpenSlowly,
            UserText.problemSubcategoryWebsitesLoadSlowly
        ]

        XCTAssertEqual(Set(category.subcategories.map(\.text)), Set(expectedSubcategories))
    }

    func testWhenAccessingBrowserDoesntWorkCategoryThenSubcategoriesAreCorrect() {
        let category = ProblemCategory.allCategories.first { $0.id == "browser-doesnt-work-as-expected" }!

        let expectedSubcategories = [
            UserText.problemSubcategoryBrowserUsesTooMuchMemory,
            UserText.problemSubcategoryCameraAudioPermissions,
            UserText.problemSubcategoryCantRestartFailedDownloads,
            UserText.problemSubcategoryConfusingOrMissingSettings,
            UserText.problemSubcategoryLoggedOutUnexpectedly,
            UserText.problemSubcategoryLostTabsOrHistory,
            UserText.problemSubcategoryNoDownloadHistory,
            UserText.problemSubcategoryPopupWindowsNotOpening,
            UserText.problemSubcategoryTooManyCaptchas,
            UserText.problemSubcategoryVideoAudioPlaysAutomatically,
            UserText.problemSubcategoryVideoDoesntPlay
        ]

        XCTAssertEqual(Set(category.subcategories.map(\.text)), Set(expectedSubcategories))
    }

    func testWhenAccessingInstallUpdatesCategoryThenSubcategoriesAreCorrect() {
        let category = ProblemCategory.allCategories.first { $0.id == "browser-install-and-updates" }!

        let expectedSubcategories = [
            UserText.problemSubcategoryBrowserVersionIssues,
            UserText.problemSubcategoryCantControlUpdates,
            UserText.problemSubcategoryInstalling,
            UserText.problemSubcategoryUninstalling,
            UserText.problemSubcategoryTooManyUpdates
        ]

        XCTAssertEqual(Set(category.subcategories.map(\.text)), Set(expectedSubcategories))
    }

    func testWhenAccessingBrokenWebsiteCategoryThenSubcategoriesAreCorrect() {
        let category = ProblemCategory.allCategories.first { $0.id == "report-broken-website" }!

        let expectedSubcategories = [
            UserText.problemSubcategorySiteWontLoad,
            UserText.problemSubcategorySiteLooksBroken,
            UserText.problemSubcategoryFeaturesDontWork,
            UserText.problemSubcategorySomethingElse
        ]

        XCTAssertEqual(Set(category.subcategories.map(\.text)), Set(expectedSubcategories))
    }

    func testWhenAccessingAdsIssuesCategoryThenSubcategoriesAreCorrect() {
        let category = ProblemCategory.allCategories.first { $0.id == "ads-causing-issues" }!

        let expectedSubcategories = [
            UserText.problemSubcategoryBannerAdsBlockingContent,
            UserText.problemSubcategoryDistractingAnimationsOnAds,
            UserText.problemSubcategoryInterruptingPopups,
            UserText.problemSubcategoryLargeBannerAds,
            UserText.problemSubcategorySiteAsksToTurnOffAdBlocker
        ]

        XCTAssertEqual(Set(category.subcategories.map(\.text)), Set(expectedSubcategories))
    }

    func testWhenAccessingPasswordIssuesCategoryThenSubcategoriesAreCorrect() {
        let category = ProblemCategory.allCategories.first { $0.id == "password-issues" }!

        let expectedSubcategories = [
            UserText.problemSubcategoryCantSyncPasswords,
            UserText.problemSubcategoryExportingPasswords,
            UserText.problemSubcategoryImportingPasswords,
            UserText.problemSubcategoryPasswordsManagement
        ]

        XCTAssertEqual(Set(category.subcategories.map(\.text)), Set(expectedSubcategories))
    }

    func testWhenAccessingSomethingElseCategoryThenSubcategoriesAreCorrect() {
        let category = ProblemCategory.allCategories.first { $0.id == "something-else" }!

        let expectedSubcategories = [
            UserText.problemSubcategoryCantCompleteAPurchase,
            UserText.problemSubcategoryCantRestartFailedDownloads,
            UserText.problemSubcategoryConfusingOrMissingSettings,
            UserText.problemSubcategoryNoDownloadsHistory,
            UserText.problemSubcategoryVideoAudioPlaysAutomatically,
            UserText.problemSubcategoryPromotionalMessages
        ]

        XCTAssertEqual(Set(category.subcategories.map(\.text)), Set(expectedSubcategories))
    }

    // MARK: - Category Name Tests

    func testWhenAccessingCategoryNamesThenTheyMatchUserText() {
        let allCategories = ProblemCategory.allCategories

        let nameMap = [
            "computer-or-browser-is-too-slow": UserText.problemCategoryBrowserTooSlow,
            "browser-doesnt-work-as-expected": UserText.problemCategoryBrowserDoesntWork,
            "browser-install-and-updates": UserText.problemCategoryInstallUpdates,
            "report-broken-website": UserText.problemCategoryBrokenWebsite,
            "ads-causing-issues": UserText.problemCategoryAdsIssues,
            "password-issues": UserText.problemCategoryPasswordIssues,
            "something-else": UserText.problemCategoryOtherFeedback
        ]

        for category in allCategories {
            XCTAssertEqual(category.text, nameMap[category.id], "Name mismatch for category: \(category.id)")
        }
    }

    // MARK: - Edge Cases and Validation Tests

    func testWhenComparingNilProblemCategoriesThenEqualityWorksCorrectly() {
        let category1: ProblemCategory? = nil
        let category2: ProblemCategory? = nil
        let category3: ProblemCategory? = ProblemCategory(id: "test", text: "Test", subcategories: [])

        XCTAssertEqual(category1, category2)
        XCTAssertNotEqual(category1, category3)
        XCTAssertNotEqual(category2, category3)
    }

    func testWhenCreatingCategoryWithEmptySubcategoriesThenItWorksCorrectly() {
        let category = ProblemCategory(id: "empty", text: "Empty Category", subcategories: [])

        XCTAssertEqual(category.id, "empty")
        XCTAssertEqual(category.text, "Empty Category")
        XCTAssertTrue(category.subcategories.isEmpty)
    }

    func testWhenUsingCategoryInDictionaryThenHashingWorksCorrectly() {
        let category1 = ProblemCategory(id: "key1", text: "Category 1", subcategories: [])
        let category2 = ProblemCategory(id: "key2", text: "Category 2", subcategories: [])
        let category3 = ProblemCategory(id: "key1", text: "Category 1 Modified", subcategories: [SubCategory(id: "sub", text: "Sub")])

        var categoryDict: [ProblemCategory: String] = [:]
        categoryDict[category1] = "value1"
        categoryDict[category2] = "value2"
        categoryDict[category3] = "value3" // Should overwrite category1 since same id

        XCTAssertEqual(categoryDict.count, 2)
        XCTAssertEqual(categoryDict[category1], "value3") // Should get the updated value
        XCTAssertEqual(categoryDict[category2], "value2")
        XCTAssertEqual(categoryDict[category3], "value3")
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

    // MARK: - Performance Tests

    func testWhenAccessingAllCategoriesMultipleTimesThenPerformanceIsAcceptable() {
        measure {
            for _ in 0..<1000 {
                _ = ProblemCategory.allCategories
            }
        }
    }

    func testWhenComparingManyProblemCategoriesThenPerformanceIsAcceptable() {
        let categories = Array(repeating: ProblemCategory.allCategories, count: 100).flatMap { $0 }

        measure {
            let categoriesSet = Set(categories)
            XCTAssertEqual(categoriesSet.count, ProblemCategory.allCategories.count)
        }
    }
}
