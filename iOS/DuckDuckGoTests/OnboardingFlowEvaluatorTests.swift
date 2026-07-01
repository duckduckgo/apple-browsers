//
//  OnboardingFlowEvaluatorTests.swift
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
import Onboarding
@testable import DuckDuckGo

@Suite("Onboarding - Flow Evaluator")
struct OnboardingFlowEvaluatorTests {

    // MARK: - Default Scheme Tests

    @Test("Returns default flow and default source when URL is nil")
    func nilURLReturnsDefaultFlow() {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator()

        // WHEN
        let result = evaluator.evaluateOnboardingFlow(from: nil)

        // THEN
        #expect(result.flow == .default)
        #expect(result.source == .default)
    }

    @Test("Returns default flow and default source for valid CPP URL with default identifier")
    func validCPPURLWithDefaultIdentifierReturnsDefaultFlow() {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = URL(string: "ddgCPP://default")

        // WHEN
        let result = evaluator.evaluateOnboardingFlow(from: url)

        // THEN
        #expect(result.flow == .default)
        #expect(result.source == .default)
    }

    @Test("Returns duckAI flow and duckAICPP source for valid CPP URL with duckAI identifier")
    func validCPPURLWithDuckAIIdentifierReturnsDuckAIFlow() {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = URL(string: "ddgCPP://duckAI")

        // WHEN
        let result = evaluator.evaluateOnboardingFlow(from: url)

        // THEN
        #expect(result.flow == .duckAI)
        #expect(result.source == .duckAICPP)
    }

    // MARK: - Invalid URL Tests

    @Test("Returns default flow and default source when URL scheme does not match CPP scheme")
    func wrongSchemeReturnsDefaultFlow() {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = URL(string: "ddgOpen://duckAI")

        // WHEN
        let result = evaluator.evaluateOnboardingFlow(from: url)

        // THEN
        #expect(result.flow == .default)
        #expect(result.source == .default)
    }

    @Test("Returns default flow and default source when URL has no host")
    func missingHostReturnsDefaultFlow() {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = URL(string: "ddgCPP://")

        // WHEN
        let result = evaluator.evaluateOnboardingFlow(from: url)

        // THEN
        #expect(result.flow == .default)
        #expect(result.source == .default)
    }

    @Test("Returns default flow and default source when URL host is not a valid flow type")
    func invalidFlowTypeIdentifierReturnsDefaultFlow() {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = URL(string: "ddgCPP://unknown-flow")

        // WHEN
        let result = evaluator.evaluateOnboardingFlow(from: url)

        // THEN
        #expect(result.flow == .default)
        #expect(result.source == .default)
    }

    @Test("Returns default flow and default source when URL has invalid format")
    func malformedURLReturnsDefaultFlow() {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = URL(string: "ddgOpenAIChat://test-something")

        // WHEN
        let result = evaluator.evaluateOnboardingFlow(from: url)

        // THEN
        #expect(result.flow == .default)
        #expect(result.source == .default)
    }

    @Test("Returns default flow and default source when URL has query parameters but invalid host")
    func queryParametersWithInvalidHostReturnsDefaultFlow() {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = URL(string: "ddgCPP://invalid")

        // WHEN
        let result = evaluator.evaluateOnboardingFlow(from: url)

        // THEN
        #expect(result.flow == .default)
        #expect(result.source == .default)
    }

    @Test("Returns default flow and default source when URL has path components instead of host")
    func pathComponentsInsteadOfHostReturnsDefaultFlow() {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = URL(string: "ddgCPP:///duckAI")

        // WHEN
        let result = evaluator.evaluateOnboardingFlow(from: url)

        // THEN
        #expect(result.flow == .default)
        #expect(result.source == .default)
    }

    // MARK: - Custom Scheme Tests

    @Test("Returns duckAI flow and duckAICPP source when using custom scheme with duckAI identifier")
    func customSchemeWithDuckAIIdentifierReturnsDuckAIFlow() {
        // GIVEN
        let customScheme = "customScheme"
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: customScheme)
        let url = URL(string: "\(customScheme)://duckAI")

        // WHEN
        let result = evaluator.evaluateOnboardingFlow(from: url)

        // THEN
        #expect(result.flow == .duckAI)
        #expect(result.source == .duckAICPP)
    }

    @Test("Returns default flow and default source when using custom scheme with default identifier")
    func customSchemeWithDefaultIdentifierReturnsDefaultFlow() {
        // GIVEN
        let customScheme = "customScheme"
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: customScheme)
        let url = URL(string: "\(customScheme)://default")

        // WHEN
        let result = evaluator.evaluateOnboardingFlow(from: url)

        // THEN
        #expect(result.flow == .default)
        #expect(result.source == .default)
    }

    @Test("Returns default flow and default source when custom scheme does not match URL scheme")
    func customSchemeMismatchReturnsDefaultFlow() {
        // GIVEN
        let customScheme = "customScheme"
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: customScheme)
        let url = URL(string: "ddgCPP://duckAI")

        // WHEN
        let result = evaluator.evaluateOnboardingFlow(from: url)

        // THEN
        #expect(result.flow == .default)
        #expect(result.source == .default)
    }

    // MARK: - Case Sensitivity Tests

    @Test("Returns DuckAI flow and duckAICPP source when scheme has uppercase letters")
    func uppercaseSchemeReturnsDefaultFlow() {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator()
        let url = URL(string: "DDGCPP://duckAI")

        // WHEN
        let result = evaluator.evaluateOnboardingFlow(from: url)

        // THEN
        #expect(result.flow == .duckAI)
        #expect(result.source == .duckAICPP)
    }

    // MARK: - Edge Cases

    @Test("Returns duckAI flow and duckAICPP source when URL has query parameters")
    func validURLWithQueryParametersReturnsDuckAIFlow() {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = URL(string: "ddgCPP://duckAI?campaign=something")

        // WHEN
        let result = evaluator.evaluateOnboardingFlow(from: url)

        // THEN
        #expect(result.flow == .duckAI)
        #expect(result.source == .duckAICPP)
    }

    @Test("Returns duckAI flow and duckAICPP source when URL has fragment")
    func validURLWithFragmentReturnsDuckAIFlow() {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = URL(string: "ddgCPP://duckAI#section")

        // WHEN
        let result = evaluator.evaluateOnboardingFlow(from: url)

        // THEN
        #expect(result.flow == .duckAI)
        #expect(result.source == .duckAICPP)
    }

    @Test("Returns default flow and default source when identifier contains only whitespace")
    func whitespaceIdentifierReturnsDefaultFlow() {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = URL(string: "ddgCPP://%20")

        // WHEN
        let result = evaluator.evaluateOnboardingFlow(from: url)

        // THEN
        #expect(result.flow == .default)
        #expect(result.source == .default)
    }

    @Test("Returns default flow and default source when URL is empty string")
    func emptyStringURLReturnsDefaultFlow() {
        // GIVEN
        let evaluator = AppStoreCustomProductPageEvaluator(customProductPageScheme: "ddgCPP")
        let url = URL(string: "")

        // WHEN
        let result = evaluator.evaluateOnboardingFlow(from: url)

        // THEN
        #expect(result.flow == .default)
        #expect(result.source == .default)
    }

}
