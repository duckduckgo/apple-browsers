//
//  AuditLogRequestTests.swift
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
@_spi(Testing) @testable import Networking
@testable import DDGSync

final class AuditLogRequestTests: XCTestCase {
    func testErrorBodyIsReadAndRequestRetainsAuthenticationAndCursor() async throws {
        let endpoints = Endpoints(baseURL: URL(string: "https://example.com")!)
        let body = Data(#"{"error":"invalid_cursor"}"#.utf8)
        let response = HTTPURLResponse(url: endpoints.auditLog, statusCode: 400, httpVersion: nil, headerFields: nil)!
        var sentRequest: APIRequestV2?
        let service = MockAPIService { request in
            sentRequest = request
            return .success(APIResponseV2(data: body, httpResponse: response))
        }
        let legacyAPI = RemoteAPIRequestCreatingMock()
        let manager = AccountManager(endpoints: endpoints, api: legacyAPI, auditLogAPIService: service,
                                     crypter: CryptingMock(), isScopedAccessCredentialsEnabled: { true })

        await assertThrowsError(AuditLogError.invalidCursor) {
            _ = try await manager.fetchAuditLog(for: .mock, cursor: .after("cursor +/=?"), limit: 100)
        }

        let request = try XCTUnwrap(sentRequest).urlRequest
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), APIRequest.Headers.userAgent ?? "")
        let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") }),
                       ["after": "cursor +/=?", "limit": "100"])
        XCTAssertEqual(legacyAPI.createRequestCallCount, 0)
    }

    func testRateLimitResponseWithEmptyBodyRemainsAStatusError() async {
        let endpoints = Endpoints(baseURL: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(url: endpoints.auditLog, statusCode: 418, httpVersion: nil, headerFields: nil)!
        let service = MockAPIService()
        service.set(response: APIResponseV2(data: Data(), httpResponse: response), forRequestURL: endpoints.auditLog)
        let manager = AccountManager(endpoints: endpoints, api: RemoteAPIRequestCreatingMock(), auditLogAPIService: service,
                                     crypter: CryptingMock(), isScopedAccessCredentialsEnabled: { true })

        await assertThrowsError(SyncError.unexpectedStatusCode(418)) {
            _ = try await manager.fetchAuditLog(for: .mock, cursor: nil)
        }
    }
}
