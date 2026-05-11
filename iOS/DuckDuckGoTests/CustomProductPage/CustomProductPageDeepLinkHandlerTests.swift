//
//  CustomProductPageDeepLinkHandlerTests.swift
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

@MainActor
@Suite("Custom Product Page - Deep Link Handler")
struct CustomProductPageDeepLinkHandlerTests {
    let mockEvaluator: MockCustomProductPageEvaluator
    let mockHandler: MockCustomProductPageDestinationHandler
    let mockPresenter: MockAppStoreCustomProductPagePresenter
    let handlers: [AppStoreCustomProductPage: CustomProductPageDestinationHandling]
    let sut: AppStoreCustomProductPageDeepLinkHandler

    init() {
        mockEvaluator = MockCustomProductPageEvaluator()
        mockHandler = MockCustomProductPageDestinationHandler()
        mockPresenter = MockAppStoreCustomProductPagePresenter()
        handlers = [
            .duckAI: mockHandler
        ]
        sut = AppStoreCustomProductPageDeepLinkHandler(
            handlers: handlers,
            customProductPageEvaluator: mockEvaluator
        )
    }

    // MARK: - Successful Routing Tests

    @Test("Calls evaluator and handler with provided URL")
    func callsEvaluatorWithProvidedURL() throws {
        // GIVEN
        mockEvaluator.stubbedResult = .duckAI
        let url = try #require(URL(string: "ddgCPP://duckAI"))

        // WHEN
        sut.handleDeepLink(url, on: mockPresenter)

        // THEN
        #expect(mockEvaluator.evaluateCustomProductPageCalled)
        #expect(mockEvaluator.capturedURL == url)
        #expect(mockHandler.capturedPresenter === mockPresenter)
        #expect(mockHandler.capturedURL?.absoluteString == "ddgCPP://duckAI")
    }

    // MARK: - Invalid URL Tests

    @Test("Does not call handler when evaluator returns nil")
    func doesNotCallHandlerWhenEvaluatorReturnsNil() throws {
        // GIVEN
        mockEvaluator.stubbedResult = nil
        let url = try #require(URL(string: "ddgCPP://unknown"))

        // WHEN
        sut.handleDeepLink(url, on: mockPresenter)

        // THEN
        #expect(mockEvaluator.evaluateCustomProductPageCalled)
        #expect(!mockHandler.handleCalled)
    }

    @Test("Does not call handler when CPP type has no registered handler")
    func doesNotCallHandlerWhenCPPTypeHasNoRegisteredHandler() throws {
        // GIVEN
        mockEvaluator.stubbedResult = .duckAI
        let sut = AppStoreCustomProductPageDeepLinkHandler(
            handlers: [:],
            customProductPageEvaluator: mockEvaluator
        )

        let url = try #require(URL(string: "ddgCPP://duckAI"))

        // WHEN
        sut.handleDeepLink(url, on: mockPresenter)

        // THEN
        #expect(mockEvaluator.evaluateCustomProductPageCalled)
        #expect(!mockHandler.handleCalled)
    }

}
