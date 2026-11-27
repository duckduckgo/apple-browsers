//
//  TranslateOfferLanguageTests.swift
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

import Foundation
import Testing
@testable import DuckDuckGo_Privacy_Browser

@Suite("Translate offer language")
struct TranslateOfferLanguageTests {

    private let english = Locale(identifier: "en")

    private func code(_ page: String?, preferred: String? = "en-US") -> String? {
        TranslateOfferLanguage.foreignLanguageCode(pageLanguage: page, preferredLanguage: preferred, locale: english)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A page in the user's language gets no offer, whatever its region or case", .timeLimit(.minutes(1)))
    func sameLanguage() {
        #expect(code("en") == nil)
        #expect(code("en-GB") == nil)
        #expect(code("EN_us") == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A page in another language offers its primary language, lowercased", .timeLimit(.minutes(1)))
    func foreignLanguage() {
        #expect(code("es") == "es")
        #expect(code("es-MX") == "es")
        #expect(code("ES") == "es")
        #expect(code(" fr-CA ") == "fr")
        #expect(code("en", preferred: "es-UY") == "en")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A page without a language gets no offer", .timeLimit(.minutes(1)))
    func noLanguage() {
        #expect(code(nil) == nil)
        #expect(code("") == nil)
        #expect(code("  ") == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A language Locale can't name gets no offer", .timeLimit(.minutes(1)))
    func unnameable() {
        #expect(code("xx") == nil)
        #expect(code("zz-ZZ") == nil)
        #expect(code("123") == nil)
        #expect(code("x-klingon") == nil)
        #expect(code("und") == nil)
        #expect(code("zxx") == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The language is named in the given locale", .timeLimit(.minutes(1)))
    func names() {
        #expect(TranslateOfferLanguage.name(of: "es-MX", in: english) == "Spanish")
        #expect(TranslateOfferLanguage.name(of: "de", in: Locale(identifier: "es")) == "alemán")
    }
}
