//
//  RequestNewFeatureViewModelTests.swift
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

final class RequestNewFeatureViewModelTests: XCTestCase {

    var viewModel: RequestNewFeatureViewModel!
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

    func testWhenInitializedThenInitialStateIsCorrect() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        XCTAssertTrue(viewModel.selectedFeatures.isEmpty)
        XCTAssertTrue(viewModel.customFeatureText.isEmpty)
        XCTAssertFalse(viewModel.availableFeatures.isEmpty)
    }

    func testWhenInitializedThenAvailableFeaturesAreShuffledAndLimited() {
        let viewModel1 = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)
        let viewModel2 = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        // Should have at most 12 features
        XCTAssertLessThanOrEqual(viewModel1.availableFeatures.count, 12)
        XCTAssertLessThanOrEqual(viewModel2.availableFeatures.count, 12)

        // Features should be from the expected list
        let allExpectedFeatures = [
            UserText.featureAdvancedAdBlocking,
            UserText.featureAISupport,
            UserText.featureCastVideo,
            UserText.featureCustomizeTheme,
            UserText.featureDarkModeAllSites,
            UserText.featureImportBookmarkFolders,
            UserText.featureImportHistory,
            UserText.featureIncognito,
            UserText.featureMoveBrowserButtons,
            UserText.featureNewTabPageWidgets,
            UserText.featurePasswordManagerExtensions,
            UserText.featurePictureInPicture,
            UserText.featureReaderMode,
            UserText.featureTabGroups,
            UserText.featureUserProfiles,
            UserText.featureVerticalTabs,
            UserText.featureWebsiteTranslation
        ]

        for feature in viewModel1.availableFeatures {
            XCTAssertTrue(allExpectedFeatures.contains(feature))
        }
    }

    // MARK: - Computed Properties Tests

    func testWhenNoFeaturesSelectedAndNoTextThenShouldEnableSubmitIsFalse() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        XCTAssertFalse(viewModel.shouldEnableSubmit)
    }

    func testWhenFeaturesSelectedThenShouldEnableSubmitIsTrue() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        viewModel.selectedFeatures.insert("test feature")

        XCTAssertTrue(viewModel.shouldEnableSubmit)
    }

    func testWhenCustomTextEnteredThenShouldEnableSubmitIsTrue() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        viewModel.customFeatureText = "custom feature idea"

        XCTAssertTrue(viewModel.shouldEnableSubmit)
    }

    func testWhenOnlyWhitespaceTextThenShouldEnableSubmitIsFalse() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        viewModel.customFeatureText = "   \n\t  "

        XCTAssertFalse(viewModel.shouldEnableSubmit)
    }

    func testWhenIncognitoFeatureNotSelectedThenShouldShowIncognitoInfoIsFalse() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        viewModel.selectedFeatures.insert("some other feature")

        XCTAssertFalse(viewModel.shouldShowIncognitoInfo)
    }

    func testWhenIncognitoFeatureSelectedThenShouldShowIncognitoInfoIsTrue() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        viewModel.selectedFeatures.insert(UserText.featureIncognito)

        XCTAssertTrue(viewModel.shouldShowIncognitoInfo)
    }

    func testWhenNoFeaturesSelectedThenHasSelectedFeaturesIsFalse() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        XCTAssertFalse(viewModel.hasSelectedFeatures)
    }

    func testWhenFeaturesSelectedThenHasSelectedFeaturesIsTrue() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        viewModel.selectedFeatures.insert("test feature")

        XCTAssertTrue(viewModel.hasSelectedFeatures)
    }

    func testWhenNoCustomTextThenHasCustomTextIsFalse() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        XCTAssertFalse(viewModel.hasCustomText)
    }

    func testWhenCustomTextEnteredThenHasCustomTextIsTrue() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        viewModel.customFeatureText = "custom idea"

        XCTAssertTrue(viewModel.hasCustomText)
    }

    func testWhenOnlyWhitespaceCustomTextThenHasCustomTextIsFalse() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        viewModel.customFeatureText = "   \n\t  "

        XCTAssertFalse(viewModel.hasCustomText)
    }

    // MARK: - Feature Toggle Tests

    func testWhenToggleFeatureNotSelectedThenFeatureIsAdded() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        let feature = "test feature"
        viewModel.toggleFeature(feature)

        XCTAssertTrue(viewModel.selectedFeatures.contains(feature))
    }

    func testWhenToggleFeatureAlreadySelectedThenFeatureIsRemoved() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        let feature = "test feature"
        viewModel.selectedFeatures.insert(feature)

        viewModel.toggleFeature(feature)

        XCTAssertFalse(viewModel.selectedFeatures.contains(feature))
    }

    // MARK: - Feedback Submission Tests

    func testWhenSubmitFeedbackWithSelectedFeaturesThenFeedbackIsSent() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        viewModel.selectedFeatures.insert("test feature")
        viewModel.submitFeedback()

        XCTAssertTrue(mockFeedbackSender.feedbackSent)
    }

    func testWhenSubmitFeedbackWithCustomTextThenFeedbackIsSent() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        viewModel.customFeatureText = "custom feature idea"
        viewModel.submitFeedback()

        XCTAssertTrue(mockFeedbackSender.feedbackSent)
    }

    func testWhenSubmitFeedbackThenCorrectFeedbackIsCreated() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        viewModel.selectedFeatures.insert("test feature")
        viewModel.customFeatureText = "custom feature text"
        viewModel.submitFeedback()

        let sentFeedback = mockFeedbackSender.lastFeedback!
        XCTAssertEqual(sentFeedback.category, .featureRequest)
        XCTAssertEqual(sentFeedback.comment, "custom feature text")
        XCTAssertTrue(sentFeedback.subcategory.contains("test-feature"))
    }

    func testWhenSubmitFeedbackWithOnlyFeaturesThenCommentIsDefault() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        viewModel.selectedFeatures.insert("test feature")
        viewModel.submitFeedback()

        let sentFeedback = mockFeedbackSender.lastFeedback!
        XCTAssertEqual(sentFeedback.comment, "Via Request New Feature Form")
    }

    func testWhenSubmitFeedbackWithMultipleFeaturesThenAllAreIncluded() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        viewModel.selectedFeatures.insert("feature one")
        viewModel.selectedFeatures.insert("feature two")
        viewModel.submitFeedback()

        let sentFeedback = mockFeedbackSender.lastFeedback!
        XCTAssertTrue(sentFeedback.subcategory.contains("feature-one"))
        XCTAssertTrue(sentFeedback.subcategory.contains("feature-two"))
    }

    // MARK: - Published Properties Tests

    func testWhenSelectedFeaturesChangedThenPublisherEmits() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        let expectation = XCTestExpectation(description: "selectedFeatures publisher emits")
        var receivedValue: Set<String>?

        viewModel.$selectedFeatures
            .dropFirst() // Skip initial value
            .sink { value in
                receivedValue = value
                expectation.fulfill()
            }
            .store(in: &cancellables)

        viewModel.selectedFeatures.insert("test feature")

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedValue, ["test feature"])
    }

    func testWhenCustomFeatureTextChangedThenPublisherEmits() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        let expectation = XCTestExpectation(description: "customFeatureText publisher emits")
        var receivedValue: String?

        viewModel.$customFeatureText
            .dropFirst() // Skip initial value
            .sink { value in
                receivedValue = value
                expectation.fulfill()
            }
            .store(in: &cancellables)

        viewModel.customFeatureText = "test text"

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedValue, "test text")
    }

    // MARK: - Integration Tests

    func testWhenMultipleInteractionsThenStateIsConsistent() {
        viewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)

        // Add some features
        viewModel.toggleFeature("feature 1")
        viewModel.toggleFeature("feature 2")
        XCTAssertEqual(viewModel.selectedFeatures.count, 2)
        XCTAssertTrue(viewModel.shouldEnableSubmit)

        // Remove one feature
        viewModel.toggleFeature("feature 1")
        XCTAssertEqual(viewModel.selectedFeatures.count, 1)
        XCTAssertTrue(viewModel.shouldEnableSubmit)

        // Remove all features
        viewModel.toggleFeature("feature 2")
        XCTAssertTrue(viewModel.selectedFeatures.isEmpty)
        XCTAssertFalse(viewModel.shouldEnableSubmit)

        // Add custom text
        viewModel.customFeatureText = "custom idea"
        XCTAssertTrue(viewModel.shouldEnableSubmit)
        XCTAssertTrue(viewModel.hasCustomText)
    }

    func testWhenIncognitoFeatureIsAvailableAndSelectedThenInfoIsShown() {
        // Create a new view model to ensure we get incognito in available features
        var viewModelWithIncognito: RequestNewFeatureViewModel?

        // Try multiple times since features are shuffled
        for _ in 0..<10 {
            let testViewModel = RequestNewFeatureViewModel(feedbackSender: mockFeedbackSender)
            if testViewModel.availableFeatures.contains(UserText.featureIncognito) {
                viewModelWithIncognito = testViewModel
                break
            }
        }

        // Skip test if incognito feature is not available in any attempt
        guard let viewModel = viewModelWithIncognito else {
            XCTSkip("Incognito feature not available in shuffled features")
        }

        XCTAssertFalse(viewModel.shouldShowIncognitoInfo)

        viewModel.toggleFeature(UserText.featureIncognito)

        XCTAssertTrue(viewModel.shouldShowIncognitoInfo)
        XCTAssertTrue(viewModel.selectedFeatures.contains(UserText.featureIncognito))
    }
}
