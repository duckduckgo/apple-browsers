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
@testable import Networking
@testable import DDGSync

final class AuditLogRequestTests: XCTestCase {
    func testErrorBodyIsReadAndRequestRetainsAuthenticationAndCursor() async throws {
        let endpoints = Endpoints(baseURL: URL(string: "https://example.com")!)
        let body = Data(#"{"error":"invalid_cursor"}"#.utf8)
        let response = HTTPURLResponse(url: endpoints.auditLog, statusCode: 400, httpVersion: nil, headerFields: nil)!
        let api = RemoteAPIRequestCreatingMock()
        api.request = HTTPRequestingMock(result: HTTPResult(data: body, response: response))
        let manager = AccountManager(endpoints: endpoints, api: api,
                                     crypter: CryptingMock(), isScopedAccessCredentialsEnabled: { true })

        await assertThrowsError(AuditLogError.invalidCursor) {
            _ = try await manager.fetchAuditLog(for: .mock, cursor: .after("cursor +/=?"), limit: 100)
        }

        let args = try XCTUnwrap(api.createRequestCallArgs.last)
        XCTAssertEqual(args.requirements, [.allowHTTPNotModified, .allowHTTPErrorResponse])
        let createdRequest = RemoteAPIRequestCreator().createRequest(url: args.url, method: args.method,
                                                                     headers: args.headers, parameters: args.parameters,
                                                                     body: args.body, contentType: args.contentType,
                                                                     requirements: args.requirements)
        let request = try XCTUnwrap(createdRequest as? APIRequest).request
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), APIRequest.Headers.userAgent ?? "")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Accept-Encoding"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Accept-Language"))
        let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") }),
                       ["after": "cursor +/=?", "limit": "100"])
    }

    func testRateLimitResponseWithEmptyBodyRemainsAStatusError() async {
        let endpoints = Endpoints(baseURL: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(url: endpoints.auditLog, statusCode: 418, httpVersion: nil, headerFields: nil)!
        let api = RemoteAPIRequestCreatingMock()
        api.request = HTTPRequestingMock(result: HTTPResult(data: Data(), response: response))
        let manager = AccountManager(endpoints: endpoints, api: api,
                                     crypter: CryptingMock(), isScopedAccessCredentialsEnabled: { true })

        await assertThrowsError(SyncError.unexpectedStatusCode(418)) {
            _ = try await manager.fetchAuditLog(for: .mock, cursor: nil)
        }
    }

    func testOtherSyncRequestsDoNotOptIntoHTTPErrorResponses() throws {
        let api = RemoteAPIRequestCreatingMock()
        _ = api.createAuthenticatedGetRequest(url: URL(string: "https://example.com/sync/devices")!, authToken: "token")

        XCTAssertEqual(try XCTUnwrap(api.createRequestCallArgs.last).requirements, [.allowHTTPNotModified])
    }
}
