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
        let selectedPills = ["Fast Browser", "Bug Fix"]
        let text = "This is my feedback"
        let appVersion = "1.2.3"
        let category = Feedback.Category.bug
        let problemCategory = ProblemCategory(
            id: "browserTooSlow",
            name: "Browser is too slow",
            subcategories: []
        )

        let feedback = Feedback.from(
            selectedPills: selectedPills,
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
        let selectedPills = ["Feature"]
        let text = ""
        let appVersion = "1.0.0"
        let category = Feedback.Category.bug

        let feedback = Feedback.from(
            selectedPills: selectedPills,
            text: text,
            appVersion: appVersion,
            category: category,
            problemCategory: nil
        )

        XCTAssertEqual(feedback.comment, "Via Report a Problem Form")
    }

    func testWhenCreatingFeedbackWithFeatureRequestCategoryThenCommentIsCorrect() {
        let selectedPills = ["Feature"]
        let text = ""
        let appVersion = "1.0.0"
        let category = Feedback.Category.featureRequest

        let feedback = Feedback.from(
            selectedPills: selectedPills,
            text: text,
            appVersion: appVersion,
            category: category,
            problemCategory: nil
        )

        XCTAssertEqual(feedback.comment, "Via Request New Feature Form")
    }

    func testWhenCreatingFeedbackWithNoProblemCategoryThenSubcategoryContainsOnlySelectedPills() {
        let selectedPills = ["Feature One", "Feature Two"]
        let text = "Test text"
        let appVersion = "1.0.0"
        let category = Feedback.Category.featureRequest

        let feedback = Feedback.from(
            selectedPills: selectedPills,
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
        let selectedPills = ["Option One"]
        let text = "Test text"
        let appVersion = "1.0.0"
        let category = Feedback.Category.bug
        let problemCategory = ProblemCategory(
            id: "testCategory",
            name: "Test Category",
            subcategories: []
        )

        let feedback = Feedback.from(
            selectedPills: selectedPills,
            text: text,
            appVersion: appVersion,
            category: category,
            problemCategory: problemCategory
        )

        XCTAssertTrue(feedback.subcategory.contains("test-category"))
        XCTAssertTrue(feedback.subcategory.contains("option-one"))
        XCTAssertTrue(feedback.subcategory.contains(",")) // Should contain comma separator
    }

    // MARK: - String Extension Tests

    func testWhenConvertingStringToTagThenFormattingIsCorrect() {
        let testCases = [
            ("Simple String", "simple-string"),
            ("String With   Multiple Spaces", "string-with-multiple-spaces"),
            ("  Leading and Trailing  ", "leading-and-trailing"),
            ("UPPERCASE", "uppercase"),
            ("MixedCASE String", "mixedcase-string"),
            ("String\nWith\tWhitespace", "string-with-whitespace"),
            ("Single", "single"),
            // Special character handling
            ("Feature & Bug", "feature-and-bug"),
            ("Browser doesn't work", "browser-doesnt-work"),
            ("100% CPU usage", "100-percent-cpu-usage"),
            ("Camera/audio permissions", "camera-audio-permissions"),
            ("Feature@#$", "feature-at-number-dollar"),
            ("Another Feature!", "another-feature"),
            ("User@domain.com", "user-at-domain-com"),
            ("Test (with parentheses)", "test-with-parentheses"),
            ("Multiple---dashes", "multiple-dashes"),
            ("", ""),
            ("   ", "")
        ]

        for (input, expected) in testCases {
            let result = input.toTag
            XCTAssertEqual(result, expected, "Failed for input: '\(input)'")
        }
    }

        func testWhenConvertingStringToTagThenSpecialCharactersAreHandledCorrectly() {
        // Test comprehensive special character handling
        let complexInput = "Browser doesn't work @ 100% & has issues/problems!"
        let result = complexInput.toTag
        let expected = "browser-doesnt-work-at-100-percent-and-has-issues-problems"
        XCTAssertEqual(result, expected, "Complex special character handling failed")
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

    // MARK: - Edge Cases and Validation Tests

    func testWhenCreatingFeedbackWithEmptySelectedPillsThenSubcategoryIsCorrect() {
        let selectedPills: [String] = []
        let text = "Test text"
        let appVersion = "1.0.0"
        let category = Feedback.Category.bug
        let problemCategory = ProblemCategory(
            id: "testCategory",
            name: "Test Category",
            subcategories: []
        )

        let feedback = Feedback.from(
            selectedPills: selectedPills,
            text: text,
            appVersion: appVersion,
            category: category,
            problemCategory: problemCategory
        )

        XCTAssertTrue(feedback.subcategory.contains("test-category"))
        XCTAssertTrue(feedback.subcategory.hasSuffix(",")) // Should end with comma since no pills
    }

    func testWhenCreatingFeedbackWithSpecialCharactersInPillsThenTaggingHandlesCorrectly() {
        let selectedPills = ["Feature@#$", "Another Feature!"]
        let text = "Test text"
        let appVersion = "1.0.0"
        let category = Feedback.Category.featureRequest

        let feedback = Feedback.from(
            selectedPills: selectedPills,
            text: text,
            appVersion: appVersion,
            category: category,
            problemCategory: nil
        )

        // The toTag function should handle special characters
        XCTAssertTrue(feedback.subcategory.contains("feature-at-number-dollar"))
        XCTAssertTrue(feedback.subcategory.contains("another-feature"))
    }
}
