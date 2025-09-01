//
//  FeedbackTests.swift
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

final class FeedbackTests: XCTestCase {

    // MARK: - Initialization Tests

    func testWhenInitializingFeedbackWithoutSubcategoryThenDefaultsToEmpty() {
        let feedback = Feedback(
            category: .featureRequest,
            comment: "Feature request",
            appVersion: "1.0.0",
            osVersion: "macOS 14.0"
        )

        XCTAssertEqual(feedback.subcategory, "")
    }

    // MARK: - Factory Method Tests

    func testWhenCreatingFeedbackFromSelectedPillsAndTextThenPropertiesAreSetCorrectly() {
        let selectedPills = ["fast-browser", "bug-fix"]
        let text = "This is my feedback"
        let appVersion = "1.2.3"
        let category = Feedback.Category.bug
        let problemCategory = ProblemCategory(
            id: "browser-is-too-slow",
            text: "Browser is too slow",
            subcategories: []
        )

        let feedback = Feedback.from(
            selectedPillIds: selectedPills,
            text: text,
            appVersion: appVersion,
            category: category,
            problemCategory: problemCategory
        )

        XCTAssertEqual(feedback.category, .bug)
        XCTAssertEqual(feedback.comment, text)
        XCTAssertEqual(feedback.appVersion, appVersion)
        XCTAssertTrue(feedback.subcategory.contains("browser-is-too-slow"))
        XCTAssertTrue(feedback.subcategory.contains("fast-browser"))
        XCTAssertTrue(feedback.subcategory.contains("bug-fix"))
    }

    func testWhenCreatingFeedbackWithEmptyTextThenCommentIsDefaultForCategory() {
        let selectedPills = ["feature"]
        let text = ""
        let appVersion = "1.0.0"
        let category = Feedback.Category.bug

        let feedback = Feedback.from(
            selectedPillIds: selectedPills,
            text: text,
            appVersion: appVersion,
            category: category,
            problemCategory: nil
        )

        XCTAssertEqual(feedback.comment, "Via Report a Problem Form")
    }

    func testWhenCreatingFeedbackWithFeatureRequestCategoryThenCommentIsCorrect() {
        let selectedPills = ["feature"]
        let text = ""
        let appVersion = "1.0.0"
        let category = Feedback.Category.featureRequest

        let feedback = Feedback.from(
            selectedPillIds: selectedPills,
            text: text,
            appVersion: appVersion,
            category: category,
            problemCategory: nil
        )

        XCTAssertEqual(feedback.comment, "Via Request New Feature Form")
    }

    func testWhenCreatingFeedbackWithNoProblemCategoryThenSubcategoryContainsOnlySelectedPills() {
        let selectedPills = ["feature-one", "feature-two"]
        let text = "Test text"
        let appVersion = "1.0.0"
        let category = Feedback.Category.featureRequest

        let feedback = Feedback.from(
            selectedPillIds: selectedPills,
            text: text,
            appVersion: appVersion,
            category: category,
            problemCategory: nil
        )

        XCTAssertTrue(feedback.subcategory.contains("feature-one"))
        XCTAssertTrue(feedback.subcategory.contains("feature-two"))
        XCTAssertFalse(feedback.subcategory.contains(",feature-one")) // Should not start with comma
    }

    func testWhenCreatingFeedbackWithProblemCategoryThenSubcategoryContainsBoth() {
        let selectedPills = ["option-one"]
        let text = "Test text"
        let appVersion = "1.0.0"
        let category = Feedback.Category.bug
        let problemCategory = ProblemCategory(
            id: "test-category",
            text: "Test Category",
            subcategories: []
        )

        let feedback = Feedback.from(
            selectedPillIds: selectedPills,
            text: text,
            appVersion: appVersion,
            category: category,
            problemCategory: problemCategory
        )

        XCTAssertTrue(feedback.subcategory.contains("test-category"))
        XCTAssertTrue(feedback.subcategory.contains("option-one"))
        XCTAssertTrue(feedback.subcategory.contains(",")) // Should contain comma separator
    }

    // MARK: - ID-Based Feedback Tests

    func testWhenCreatingFeedbackWithCategoryThenSubcategoryUsesCorrectIDs() {
        // Test that problem categories use their IDs instead of localized names
        let problemCategory = ProblemCategory(
            id: "ads-causing-issues",
            text: "Ads causing issues",
            subcategories: [
                SubCategory(id: "banner-ads-blocking-content", text: "Banner ads blocking content"),
                SubCategory(id: "large-banner-ads", text: "Large banner ads")
            ]
        )

        let selectedSubcategoryIds = ["banner-ads-blocking-content", "large-banner-ads"]

        let feedback = Feedback.from(
            selectedPillIds: selectedSubcategoryIds,
            text: "Test feedback",
            appVersion: "1.0.0",
            category: .bug,
            problemCategory: problemCategory
        )

        // Should contain the category ID and subcategory IDs, not localized text
        XCTAssertTrue(feedback.subcategory.contains("ads-causing-issues"))
        XCTAssertTrue(feedback.subcategory.contains("banner-ads-blocking-content"))
        XCTAssertTrue(feedback.subcategory.contains("large-banner-ads"))
        XCTAssertFalse(feedback.subcategory.contains("Ads causing issues"))
        XCTAssertFalse(feedback.subcategory.contains("Banner ads blocking content"))
    }

    func testWhenCreatingFeatureRequestFeedbackThenUsesFeatureIDs() {
        // Test that feature requests use feature IDs
        let selectedFeatureIds = ["advanced-ad-blocking", "ai-support", "reader-mode"]

        let feedback = Feedback.from(
            selectedPillIds: selectedFeatureIds,
            text: "Feature request feedback",
            appVersion: "1.0.0",
            category: .featureRequest,
            problemCategory: nil
        )

        // Should contain the feature IDs directly
        XCTAssertTrue(feedback.subcategory.contains("advanced-ad-blocking"))
        XCTAssertTrue(feedback.subcategory.contains("ai-support"))
        XCTAssertTrue(feedback.subcategory.contains("reader-mode"))
        XCTAssertTrue(feedback.subcategory.contains(",")) // Should contain comma separators
    }

    // MARK: - Category Extension Tests

    func testWhenConvertingBugCategoryToStringThenReturnsCorrectString() {
        let category = Feedback.Category.bug
        XCTAssertEqual(category.toString, "Via Report a Problem Form")
    }

    func testWhenConvertingFeatureRequestCategoryToStringThenReturnsCorrectString() {
        let category = Feedback.Category.featureRequest
        XCTAssertEqual(category.toString, "Via Request New Feature Form")
    }

    func testWhenConvertingAllOtherCategoriesToStringThenReturnsOther() {
        let otherCategories: [Feedback.Category] = [
            .designFeedback,
            .other,
            .usability,
            .dataImport,
            .generalFeedback
        ]

        for category in otherCategories {
            XCTAssertEqual(category.toString, "other", "Failed for category: \(category)")
        }
    }
}
