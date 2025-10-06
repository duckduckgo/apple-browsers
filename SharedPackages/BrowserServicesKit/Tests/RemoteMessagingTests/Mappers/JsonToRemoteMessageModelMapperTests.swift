//
//  JsonToRemoteMessageModelMapperTests.swift
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
import RemoteMessagingTestsUtils
@testable import RemoteMessaging

class JsonToRemoteMessageModelMapperTests: XCTestCase {

    func testThatGetTranslationMatchesTheLocale() {
        let translations: [String: RemoteMessageResponse.JsonContentTranslation] = [
            "en-CA": RemoteMessageResponse.JsonContentTranslation(messageType: "type", titleText: "en-CA-title", descriptionText: "en-CA-description", primaryActionText: "en-CA-primary", secondaryActionText: "en-CA-secondary"),
            "en": RemoteMessageResponse.JsonContentTranslation(messageType: "type", titleText: "en-title", descriptionText: "en-description", primaryActionText: "en-primary", secondaryActionText: "en-secondary"),
        ]

        let locale = Locale.init(identifier: "en-CA")
        let translation = JsonToRemoteMessageModelMapper.getTranslation(from: translations, for: locale)

        XCTAssertNotNil(translation)
        XCTAssertEqual(translation?.titleText, "en-CA-title")
        XCTAssertEqual(translation?.descriptionText, "en-CA-description")
        XCTAssertEqual(translation?.primaryActionText, "en-CA-primary")
        XCTAssertEqual(translation?.secondaryActionText, "en-CA-secondary")
    }

    func testThatGetTranslationReturnsGenericTranslationWhenOnlyLanguageMatches() {
        let translations: [String: RemoteMessageResponse.JsonContentTranslation] = [
            "en-CA": RemoteMessageResponse.JsonContentTranslation(messageType: "type", titleText: "en-CA-title", descriptionText: "en-CA-description", primaryActionText: "en-CA-primary", secondaryActionText: "en-CA-secondary"),
            "en": RemoteMessageResponse.JsonContentTranslation(messageType: "type", titleText: "en-title", descriptionText: "en-description", primaryActionText: "en-primary", secondaryActionText: "en-secondary"),
        ]

        let locale = Locale.init(identifier: "en-US")
        let translation = JsonToRemoteMessageModelMapper.getTranslation(from: translations, for: locale)

        XCTAssertNotNil(translation)
        XCTAssertEqual(translation?.titleText, "en-title")
        XCTAssertEqual(translation?.descriptionText, "en-description")
        XCTAssertEqual(translation?.primaryActionText, "en-primary")
        XCTAssertEqual(translation?.secondaryActionText, "en-secondary")
    }

}
