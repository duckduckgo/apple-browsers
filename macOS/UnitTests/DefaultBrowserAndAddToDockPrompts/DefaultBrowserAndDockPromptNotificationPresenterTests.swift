//
//  DefaultBrowserAndDockPromptNotificationPresenterTests.swift
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
import UserNotifications

final class DefaultBrowserAndDockPromptNotificationPresenterTests: XCTestCase {

    func testHandleNotificationResponse_ForInactiveUserFeedbackRequest_OpensFeedbackFormWithExpectedCategoryAndSubCategory() async throws {
        // GIVEN
        var actualCategory: ProblemCategory?
        var actualSubCategory: SubCategory?
        let reportABrowserProblemPresenter = { ( _: Any?, category: ProblemCategory?, subCategory: SubCategory?) in
            actualCategory = category
            actualSubCategory = subCategory
        }
        let sut = DefaultBrowserAndDockPromptNotificationPresenter(reportABrowserProblemPresenter: reportABrowserProblemPresenter)

        // WHEN
        await sut.handleNotificationResponse(for: .inactiveUserFeedbackRequest)

        // THEN
        XCTAssertTrue(try XCTUnwrap(actualCategory?.isSomethingElseCategory))
        XCTAssertTrue(try XCTUnwrap(actualSubCategory?.isPromotionalMessagesSubcategory))
    }

}
