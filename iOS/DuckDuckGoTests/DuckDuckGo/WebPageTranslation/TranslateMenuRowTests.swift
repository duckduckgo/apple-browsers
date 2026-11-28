//
//  TranslateMenuRowTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import WebPageTranslation
import XCTest
@testable import DuckDuckGo

final class TranslateMenuRowTests: XCTestCase {

    private let offer = TranslationOffer(source: "es", target: "en", pairID: "es-en", downloadBytes: 1)
    private let locale = Locale(identifier: "en_US")

    func testIdleOffersToTranslateIntoTheTargetLanguage() {
        XCTAssertEqual(TranslateMenuRow.content(for: offer, state: .idle, locale: locale),
                       TranslateMenuRow.Content(name: "Translate Page to English", isEnabled: true, showsDot: false))
    }

    func testTranslatingIsDisabled() {
        XCTAssertEqual(TranslateMenuRow.content(for: offer, state: .translating, locale: locale),
                       TranslateMenuRow.Content(name: "Translating…", isEnabled: false, showsDot: false))
    }

    func testATranslatedPageOffersTheOriginal() {
        for state in [PageTranslationSession.State.partiallyTranslated, .fullyTranslated] {
            XCTAssertEqual(TranslateMenuRow.content(for: offer, state: state, locale: locale),
                           TranslateMenuRow.Content(name: "Show Original Page", isEnabled: true, showsDot: true))
        }
    }
}
