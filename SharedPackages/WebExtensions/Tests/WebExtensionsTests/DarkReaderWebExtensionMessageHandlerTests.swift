//
//  DarkReaderWebExtensionMessageHandlerTests.swift
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

import XCTest
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class DarkReaderWebExtensionMessageHandlerTests: XCTestCase {

    var handler: DarkReaderWebExtensionMessageHandler!
    var mockExcludedDomainsProvider: MockDarkReaderExcludedDomainsProvider!

    override func setUp() {
        super.setUp()
        mockExcludedDomainsProvider = MockDarkReaderExcludedDomainsProvider()
        handler = DarkReaderWebExtensionMessageHandler(excludedDomainsProvider: mockExcludedDomainsProvider)
    }

    override func tearDown() {
        handler = nil
        mockExcludedDomainsProvider = nil
        super.tearDown()
    }

    // MARK: - Handler Properties

    func testHandledFeatureName() {
        XCTAssertEqual(handler.handledFeatureName, "darkReader")
    }

    // MARK: - Unknown Method

    func testWhenUnknownMethodThenReturnsUnknownMethodError() async {
        let message = createMessage(method: "unknownMethod")

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .unknownMethod(let method) = handlerError {
                XCTAssertEqual(method, "unknownMethod")
            } else {
                XCTFail("Expected unknownMethod error")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    // MARK: - isDomainExcluded

    func testWhenDomainIsExcludedThenReturnsTrue() async {
        mockExcludedDomainsProvider.excludedDomains = ["example.com"]
        let message = createMessage(method: "isDomainExcluded", params: ["url": "https://example.com/page"])

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertEqual(dict?["isExcluded"], true)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenSubdomainOfExcludedDomainThenReturnsTrue() async {
        mockExcludedDomainsProvider.excludedDomains = ["example.com"]
        let message = createMessage(method: "isDomainExcluded", params: ["url": "https://www.example.com/page"])

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertEqual(dict?["isExcluded"], true)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenDomainIsNotExcludedThenReturnsFalse() async {
        mockExcludedDomainsProvider.excludedDomains = ["example.com"]
        let message = createMessage(method: "isDomainExcluded", params: ["url": "https://other.com/page"])

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertEqual(dict?["isExcluded"], false)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenNoExcludedDomainsThenReturnsFalse() async {
        mockExcludedDomainsProvider.excludedDomains = []
        let message = createMessage(method: "isDomainExcluded", params: ["url": "https://example.com/page"])

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertEqual(dict?["isExcluded"], false)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenMultipleExcludedDomainsAndUrlMatchesOneThenReturnsTrue() async {
        mockExcludedDomainsProvider.excludedDomains = ["first.com", "second.com", "third.com"]
        let message = createMessage(method: "isDomainExcluded", params: ["url": "https://second.com/"])

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertEqual(dict?["isExcluded"], true)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenSimilarDomainButNotMatchThenReturnsFalse() async {
        mockExcludedDomainsProvider.excludedDomains = ["example.com"]
        let message = createMessage(method: "isDomainExcluded", params: ["url": "https://notexample.com/page"])

        let result = await handler.handleMessage(message)

        if case .success(let response) = result {
            let dict = response as? [String: Bool]
            XCTAssertEqual(dict?["isExcluded"], false)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testWhenMissingUrlParamThenReturnsMissingParameterError() async {
        let message = createMessage(method: "isDomainExcluded", params: [:])

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .missingParameter(let parameter) = handlerError {
                XCTAssertEqual(parameter, "url")
            } else {
                XCTFail("Expected missingParameter error")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    func testWhenNilParamsThenReturnsMissingParameterError() async {
        let message = createMessage(method: "isDomainExcluded", params: nil)

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .missingParameter = handlerError {
                // Expected
            } else {
                XCTFail("Expected missingParameter error")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    func testWhenInvalidUrlThenReturnsMissingParameterError() async {
        let message = createMessage(method: "isDomainExcluded", params: ["url": "not a valid url"])

        let result = await handler.handleMessage(message)

        if case .failure(let error) = result {
            let handlerError = error as? WebExtensionMessageHandlerError
            if case .missingParameter = handlerError {
                // Expected — URL parsing fails, no host available
            } else {
                XCTFail("Expected missingParameter error")
            }
        } else {
            XCTFail("Expected failure result")
        }
    }

    // MARK: - Helper Methods

    private func createMessage(
        method: String,
        params: [String: Any]? = nil
    ) -> WebExtensionMessage {
        WebExtensionMessage(
            featureName: "darkReader",
            method: method,
            id: nil,
            params: params,
            context: "test-context",
            extensionIdentifier: "test-extension-id"
        )
    }
}

// MARK: - Mock Classes

@available(macOS 15.4, iOS 18.4, *)
final class MockDarkReaderExcludedDomainsProvider: DarkReaderExcludedDomainsProviding {
    var excludedDomains: [String] = []
}
