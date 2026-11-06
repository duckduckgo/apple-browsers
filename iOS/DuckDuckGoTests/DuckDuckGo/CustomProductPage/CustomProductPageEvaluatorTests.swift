//
//  CustomProductPageEvaluatorTests.swift
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

import Foundation
import Testing
@testable import DuckDuckGo

@Suite("Custom Product Page - Evaluator")
struct CustomProductPageEvaluatorTests {

    // MARK: - Valid CPP URL Tests

    @Test("Returns duckAI for valid CPP URL with duckAI identifier", arguments: ["ddgCPP", "DDGCPP"])
    func validCPPURLWithDuckAIIdentifierReturnsDuckAI(urlScheme: String) throws {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = try #require(URL(string: "\(urlScheme)://duckAI"))

        // WHEN
        let result = evaluator.evaluateCustomProductPage(from: url)

        // THEN
        #expect(result == .duckAI)
    }

    @Test("Returns duckAI for valid CPP URL with query parameters")
    func validCPPURLWithQueryParametersReturnsDuckAI() throws {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = try #require(URL(string: "ddgCPP://duckAI?campaign=something"))

        // WHEN
        let result = evaluator.evaluateCustomProductPage(from: url)

        // THEN
        #expect(result == .duckAI)
    }

    @Test("Returns duckAI for valid CPP URL with fragment")
    func validCPPURLWithFragmentReturnsDuckAI() throws {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = try #require(URL(string: "ddgCPP://duckAI#section"))

        // WHEN
        let result = evaluator.evaluateCustomProductPage(from: url)

        // THEN
        #expect(result == .duckAI)
    }

    // MARK: - Invalid URL Scheme Tests

    @Test(
        "Returns nil when URL scheme does not match CPP scheme",
        arguments: [
            "ddgOpen",
            "https",
        ]
    )
    func wrongSchemeReturnsNil(scheme: String) throws {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = try #require(URL(string: "\(scheme)://duckAI"))

        // WHEN
        let result = evaluator.evaluateCustomProductPage(from: url)

        // THEN
        #expect(result == nil)
    }

    // MARK: - Invalid Host/Identifier Tests

    @Test(
        "Returns nil when invalid host",
        arguments: [
            "",
            "unknown-page",
            "/duckAI",
            "%20",
            "default",
            "duck@AI",

        ]
    )
    func invalidHostOrIdentifierReturnsNil(value: String) throws {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = try #require(URL(string: "ddgCPP://\(value)"))

        // WHEN
        let result = evaluator.evaluateCustomProductPage(from: url)

        // THEN
        #expect(result == nil)
    }

    // MARK: - Custom Scheme Tests

    @Test("Returns duckAI when using custom scheme with duckAI identifier")
    func customSchemeWithDuckAIIdentifierReturnsDuckAI() throws {
        // GIVEN
        let customScheme = "customScheme"
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: customScheme)
        let url = try #require(URL(string: "\(customScheme)://duckAI"))

        // WHEN
        let result = evaluator.evaluateCustomProductPage(from: url)

        // THEN
        #expect(result == .duckAI)
    }

    @Test("Returns nil when custom scheme does not match URL scheme")
    func customSchemeMismatchReturnsNil() throws {
        // GIVEN
        let customScheme = "customScheme"
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: customScheme)
        let url = try #require(URL(string: "ddgCPP://duckAI"))

        // WHEN
        let result = evaluator.evaluateCustomProductPage(from: url)

        // THEN
        #expect(result == nil)
    }

    // MARK: - Edge Cases

    @Test("Returns nil for URL with only scheme")
    func onlySchemeReturnsNil() throws {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = try #require(URL(string: "ddgCPP:"))

        // WHEN
        let result = evaluator.evaluateCustomProductPage(from: url)

        // THEN
        #expect(result == nil)
    }

    // MARK: - Case Sensitivity Tests

    @Test(
        "Returns nil when identifier has different casing",
        arguments: [
            "DuckAI",
            "duckai",
            "DUCKAI",
        ]
    )
    func differentCasingIdentifierReturnsNil(value: String) throws {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = try #require(URL(string: "ddgCPP://\(value)"))

        // WHEN
        let result = evaluator.evaluateCustomProductPage(from: url)

        // THEN
        #expect(result == nil)
    }
}
