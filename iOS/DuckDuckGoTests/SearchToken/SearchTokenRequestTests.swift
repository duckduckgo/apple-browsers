//
//  SearchTokenRequestTests.swift
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

import XCTest
import Networking
import NetworkingTestingUtils
@testable import DuckDuckGo

final class SearchTokenRequestTests: XCTestCase {

    private let url = URL(string: "https://example.com/search-token")!

    func testDecodesEnvelopeOnSuccess() async throws {
        let sut = makeSUT(status: 200, body: #"{"envelope":"tok-xyz"}"#)
        let token = try await sut.requestToken(userAgent: "UA/2.0")
        XCTAssertEqual(token, "tok-xyz")
    }

    func testThrowsOnNonSuccessStatusEvenWithDecodableBody() async {
        // A 4xx/5xx whose body happens to decode must NOT be treated as a valid token.
        let sut = makeSUT(status: 500, body: #"{"envelope":"should-not-be-used"}"#)
        await assertThrows(sut) { error in
            guard case SearchTokenRequest.RequestError.unexpectedStatusCode(let code) = error else {
                return XCTFail("expected unexpectedStatusCode, got \(error)")
            }
            XCTAssertEqual(code, 500)
        }
    }

    func testThrowsOnMalformedBody() async {
        let sut = makeSUT(status: 200, body: "not json")
        await assertThrows(sut)
    }

    func testThrowsWhenEnvelopeMissing() async {
        let sut = makeSUT(status: 200, body: #"{"other":"x"}"#)
        await assertThrows(sut)
    }

    func testPropagatesTransportError() async {
        let service = MockAPIService(requestHandler: { _ in .failure(URLError(.notConnectedToInternet)) })
        let sut = SearchTokenRequest(tokenURL: url, apiService: service)
        await assertThrows(sut)
    }

    // MARK: helpers

    private func makeSUT(status: Int, body: String) -> SearchTokenRequest {
        let service = MockAPIService(requestHandler: { [url] _ in
            let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            return .success(APIResponseV2(data: body.data(using: .utf8), httpResponse: http))
        })
        return SearchTokenRequest(tokenURL: url, apiService: service)
    }

    private func assertThrows(_ sut: SearchTokenRequest,
                              _ verify: (Error) -> Void = { _ in },
                              file: StaticString = #filePath,
                              line: UInt = #line) async {
        do {
            _ = try await sut.requestToken(userAgent: "UA")
            XCTFail("expected requestToken to throw", file: file, line: line)
        } catch {
            verify(error)
        }
    }
}
