//
//  SubscriptionOnboardingConnectionInfoServiceTests.swift
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
@testable import DuckDuckGo

final class SubscriptionOnboardingConnectionInfoServiceTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.stub = nil
        super.tearDown()
    }

    private func makeService(statusCode: Int = 200, body: Data) -> DefaultSubscriptionOnboardingConnectionInfoService {
        StubURLProtocol.stub = (statusCode, body)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return DefaultSubscriptionOnboardingConnectionInfoService(urlSession: URLSession(configuration: configuration))
    }

    func testWhenResponseIsValidJSONThenInfoIsDecoded() async throws {
        let json = Data(#"{"ip":"31.120.130.50","city":"Madrid","country":"ES"}"#.utf8)
        let service = makeService(body: json)

        let info = try await service.fetchConnectionInfo()

        XCTAssertEqual(info, SubscriptionOnboardingConnectionInfo(ip: "31.120.130.50", city: "Madrid", country: "ES"))
    }

    func testWhenJSONIsMalformedThenThrowsDecodingError() async {
        let service = makeService(body: Data("not json".utf8))

        do {
            _ = try await service.fetchConnectionInfo()
            XCTFail("Expected a decoding error")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testWhenServerReturns500ThenThrows() async {
        let service = makeService(statusCode: 500, body: Data("{}".utf8))

        do {
            _ = try await service.fetchConnectionInfo()
            XCTFail("Expected an error for a 5xx response")
        } catch {
            // Expected: a non-2xx status must not be decoded as success.
        }
    }
}

/// Intercepts requests so the service can be exercised without touching the network.
private final class StubURLProtocol: URLProtocol {

    /// The status code + body returned for the next request.
    static var stub: (statusCode: Int, body: Data)?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (statusCode, body) = Self.stub ?? (200, Data())
        if let url = request.url,
           let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
