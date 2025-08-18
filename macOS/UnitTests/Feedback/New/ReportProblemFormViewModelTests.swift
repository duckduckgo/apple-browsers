//
//  ReportProblemFormViewModelTests.swift
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
import Combine
@testable import DuckDuckGo_Privacy_Browser

final class ReportProblemFormViewModelTests: XCTestCase {

    var viewModel: ReportProblemFormViewModel!
    var mockFeedbackSender: MockFeedbackSender!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockFeedbackSender = MockFeedbackSender()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        viewModel = nil
        mockFeedbackSender = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testWhenInitializedWithCanReportBrokenSiteTrueThenBrokenWebsiteCategoryIsAvailable() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        let brokenWebsiteCategory = viewModel.availableCategories.first { $0.id == "report-broken-website" }
        XCTAssertNotNil(brokenWebsiteCategory)
    }

    func testWhenInitializedWithCanReportBrokenSiteFalseThenBrokenWebsiteCategoryIsNotAvailable() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: false,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        let brokenWebsiteCategory = viewModel.availableCategories.first { $0.id == "report-broken-website" }
        XCTAssertNil(brokenWebsiteCategory)
    }

    func testWhenInitializedThenInitialStateIsCorrect() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        XCTAssertFalse(viewModel.showThankYou)
        XCTAssertNil(viewModel.selectedProblemCategory)
        XCTAssertTrue(viewModel.selectedOptions.isEmpty)
        XCTAssertTrue(viewModel.customText.isEmpty)
        XCTAssertTrue(viewModel.availableOptions.isEmpty)
    }

    // MARK: - Computed Properties Tests

    func testWhenNoCategorySelectedThenIsShowingCategorySelectionIsTrue() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        XCTAssertTrue(viewModel.isShowingCategorySelection)
        XCTAssertFalse(viewModel.isShowingDetailForm)
    }

    func testWhenCategorySelectedThenIsShowingDetailFormIsTrue() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        let category = ProblemCategory.allCategories.first!
        viewModel.selectCategory(category)

        XCTAssertFalse(viewModel.isShowingCategorySelection)
        XCTAssertTrue(viewModel.isShowingDetailForm)
    }

    func testWhenThankYouShownThenBothScreensAreFalse() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        viewModel.showThankYou = true

        XCTAssertFalse(viewModel.isShowingCategorySelection)
        XCTAssertFalse(viewModel.isShowingDetailForm)
    }

    func testWhenOptionsSelectedThenShouldEnableSubmitIsTrue() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        viewModel.selectedOptions.insert("test option")

        XCTAssertTrue(viewModel.shouldEnableSubmit)
    }

    func testWhenCustomTextEnteredThenShouldEnableSubmitIsTrue() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        viewModel.customText = "test feedback"

        XCTAssertTrue(viewModel.shouldEnableSubmit)
    }

    func testWhenNoOptionsOrTextThenShouldEnableSubmitIsFalse() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        XCTAssertFalse(viewModel.shouldEnableSubmit)
    }

    func testWhenOnlyWhitespaceTextThenShouldEnableSubmitIsFalse() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        viewModel.customText = "   \n\t  "

        XCTAssertFalse(viewModel.shouldEnableSubmit)
    }

    // MARK: - Category Selection Tests

    func testWhenBrokenWebsiteCategorySelectedThenOnReportBrokenSiteIsCalled() {
        var onReportBrokenSiteCalled = false
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: { onReportBrokenSiteCalled = true },
            feedbackSender: mockFeedbackSender
        )

        let brokenWebsiteCategory = ProblemCategory.allCategories.first { $0.id == "report-broken-website" }!
        viewModel.selectCategory(brokenWebsiteCategory)

        XCTAssertTrue(onReportBrokenSiteCalled)
        XCTAssertNil(viewModel.selectedProblemCategory)
    }

    func testWhenNonBrokenWebsiteCategorySelectedThenCategoryIsSet() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        let category = ProblemCategory.allCategories.first { $0.id != "report-broken-website" }!
        viewModel.selectCategory(category)

        XCTAssertEqual(viewModel.selectedProblemCategory, category)
    }

    func testWhenCategorySelectedThenAvailableOptionsAreSet() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        let category = ProblemCategory.allCategories.first { $0.id != "report-broken-website" }!
        viewModel.selectCategory(category)

        XCTAssertFalse(viewModel.availableOptions.isEmpty)
        XCTAssertLessThanOrEqual(viewModel.availableOptions.count, 8) // 7 subcategories + "Something else"
    }

    func testWhenCategorySelectedThenFormDataIsReset() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        // Set some initial data
        viewModel.selectedOptions.insert("existing option")
        viewModel.customText = "existing text"

        let category = ProblemCategory.allCategories.first { $0.id != "report-broken-website" }!
        viewModel.selectCategory(category)

        XCTAssertTrue(viewModel.selectedOptions.isEmpty)
        XCTAssertTrue(viewModel.customText.isEmpty)
    }

    // MARK: - Navigation Tests

    func testWhenGoBackToCategorySelectionThenStateIsReset() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        // Set up some state
        let category = ProblemCategory.allCategories.first { $0.id != "report-broken-website" }!
        viewModel.selectCategory(category)
        viewModel.selectedOptions.insert("test option")
        viewModel.customText = "test text"

        viewModel.goBackToCategorySelection()

        XCTAssertNil(viewModel.selectedProblemCategory)
        XCTAssertTrue(viewModel.availableOptions.isEmpty)
        XCTAssertTrue(viewModel.selectedOptions.isEmpty)
        XCTAssertTrue(viewModel.customText.isEmpty)
    }

    // MARK: - Option Toggle Tests

    func testWhenToggleOptionNotSelectedThenOptionIsAdded() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        let option = "test option"
        viewModel.toggleOption(option)

        XCTAssertTrue(viewModel.selectedOptions.contains(option))
    }

    func testWhenToggleOptionAlreadySelectedThenOptionIsRemoved() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        let option = "test option"
        viewModel.selectedOptions.insert(option)

        viewModel.toggleOption(option)

        XCTAssertFalse(viewModel.selectedOptions.contains(option))
    }

    // MARK: - Feedback Submission Tests

    func testWhenSubmitFeedbackWithNoCategoryThenFeedbackIsNotSent() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        viewModel.submitFeedback()

        XCTAssertFalse(mockFeedbackSender.feedbackSent)
        XCTAssertFalse(viewModel.showThankYou)
    }

    func testWhenSubmitFeedbackWithCategoryThenFeedbackIsSent() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        let category = ProblemCategory.allCategories.first { $0.id != "report-broken-website" }!
        viewModel.selectCategory(category)
        viewModel.selectedOptions.insert("test option")
        viewModel.customText = "test text"

        viewModel.submitFeedback()

        XCTAssertTrue(mockFeedbackSender.feedbackSent)
        XCTAssertTrue(viewModel.showThankYou)
    }

    func testWhenSubmitFeedbackThenCorrectFeedbackIsCreated() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        let category = ProblemCategory.allCategories.first { $0.id != "report-broken-website" }!
        viewModel.selectCategory(category)
        viewModel.selectedOptions.insert("test-option")
        viewModel.customText = "test text"

        viewModel.submitFeedback()

        let sentFeedback = mockFeedbackSender.lastFeedback!
        XCTAssertEqual(sentFeedback.category, .bug)
        XCTAssertEqual(sentFeedback.comment, "test text")
        XCTAssertTrue(sentFeedback.subcategory.contains(category.id))
        XCTAssertTrue(sentFeedback.subcategory.contains("test-option"))
    }

    // MARK: - Published Properties Tests

    func testWhenShowThankYouChangedThenPublisherEmits() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        let expectation = XCTestExpectation(description: "showThankYou publisher emits")
        var receivedValue: Bool?

        viewModel.$showThankYou
            .dropFirst() // Skip initial value
            .sink { value in
                receivedValue = value
                expectation.fulfill()
            }
            .store(in: &cancellables)

        viewModel.showThankYou = true

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedValue, true)
    }

    func testWhenSelectedProblemCategoryChangedThenPublisherEmits() {
        viewModel = ReportProblemFormViewModel(
            canReportBrokenSite: true,
            onReportBrokenSite: {},
            feedbackSender: mockFeedbackSender
        )

        let expectation = XCTestExpectation(description: "selectedProblemCategory publisher emits")
        var receivedValue: ProblemCategory?

        viewModel.$selectedProblemCategory
            .dropFirst() // Skip initial value
            .sink { value in
                receivedValue = value
                expectation.fulfill()
            }
            .store(in: &cancellables)

        let category = ProblemCategory.allCategories.first { $0.id != "report-broken-website" }!
        viewModel.selectCategory(category)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedValue, category)
    }
}

// MARK: - Mock Objects

final class MockFeedbackSender: FeedbackSenderImplementing {
    var feedbackSent = false
    var lastFeedback: Feedback?
    var lastDataImportReport: DataImportReportModel?

    func sendFeedback(_ feedback: Feedback) {
        feedbackSent = true
        lastFeedback = feedback
    }

    func sendDataImportReport(_ report: DataImportReportModel) {
        lastDataImportReport = report
    }
}
