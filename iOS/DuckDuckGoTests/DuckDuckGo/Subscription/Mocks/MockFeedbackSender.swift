//
//  MockFeedbackSender.swift
//  DuckDuckGo
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

import Foundation
@testable import DuckDuckGo

final class MockFeedbackSender: UnifiedFeedbackSender {
    var shouldThrowError = false

    // Pixel tracking
    var formShowPixelSent = false
    var actionsScreenShowPixelSent = false
    var categoryScreenShowPixelSent = false
    var subcategoryScreenShowPixelSent = false
    var submitScreenShowPixelSent = false
    var submitScreenFAQClickPixelSent = false

    var featureRequestPixelSent = false
    var generalFeedbackPixelSent = false
    var reportIssuePixelSent = false

    var lastFeatureRequestDescription: String?
    var lastGeneralFeedbackDescription: String?
    var lastReportIssueDescription: String?
    var lastReportIssueCategory: String?
    var lastReportIssueSubcategory: String?

    enum MockError: Error {
        case testError
    }

    func sendFeatureRequestPixel(description: String, source: String) async throws {
        if shouldThrowError {
            throw MockError.testError
        }
        featureRequestPixelSent = true
        lastFeatureRequestDescription = description
    }

    func sendGeneralFeedbackPixel(description: String, source: String) async throws {
        if shouldThrowError {
            throw MockError.testError
        }
        generalFeedbackPixelSent = true
        lastGeneralFeedbackDescription = description
    }

    func sendReportIssuePixel<T>(source: String, category: String, subcategory: String, description: String, metadata: T?) async throws where T: DuckDuckGo.UnifiedFeedbackMetadata {
        if shouldThrowError {
            throw MockError.testError
        }
        reportIssuePixelSent = true
        lastReportIssueDescription = description
        lastReportIssueCategory = category
        lastReportIssueSubcategory = subcategory
    }

    func sendFormShowPixel() async {
        formShowPixelSent = true
    }

    func sendSubmitScreenShowPixel(source: String, reportType: String, category: String, subcategory: String) async {
        submitScreenShowPixelSent = true
    }

    func sendActionsScreenShowPixel(source: String) async {
        actionsScreenShowPixelSent = true
    }

    func sendCategoryScreenShow(source: String, reportType: String) async {
        categoryScreenShowPixelSent = true
    }

    func sendSubcategoryScreenShow(source: String, reportType: String, category: String) async {
        subcategoryScreenShowPixelSent = true
    }

    func sendSubmitScreenFAQClickPixel(source: String, reportType: String, category: String, subcategory: String) async {
        submitScreenFAQClickPixelSent = true
    }
}
