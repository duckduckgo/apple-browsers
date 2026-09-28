//
//  SearchTokenWebExtensionMessageHandlerTests.swift
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

@available(iOS 18.4, macOS 15.4, *)
final class SearchTokenWebExtensionMessageHandlerTests: XCTestCase {
    final class StubProvider: SearchTokenProviding { var token: String?; func currentToken() -> String? { token } }

    private func message(_ method: String) -> WebExtensionMessage {
        WebExtensionMessage(featureName: "searchToken", method: method, id: nil, params: nil, context: nil, extensionIdentifier: "test")
    }

    func testGetTokenReturnsToken() async {
        let p = StubProvider(); p.token = "TKN"
        let handler = SearchTokenWebExtensionMessageHandler(tokenProvider: p)
        guard case .success(let payload) = await handler.handleMessage(message("getToken")),
              let dict = payload as? [String: String] else { return XCTFail("expected .success with a [String: String] payload") }
        XCTAssertEqual(dict["token"], "TKN")
    }

    func testGetTokenNilReturnsEmpty() async {
        let handler = SearchTokenWebExtensionMessageHandler(tokenProvider: StubProvider())
        guard case .success(let payload) = await handler.handleMessage(message("getToken")),
              let dict = payload as? [String: String] else { return XCTFail("expected .success with a [String: String] payload") }
        XCTAssertTrue(dict.isEmpty)
    }

    func testUnknownMethodFails() async {
        let handler = SearchTokenWebExtensionMessageHandler(tokenProvider: StubProvider())
        guard case .failure = await handler.handleMessage(message("nope")) else { return XCTFail("expected .failure for an unknown method") }
    }
}
