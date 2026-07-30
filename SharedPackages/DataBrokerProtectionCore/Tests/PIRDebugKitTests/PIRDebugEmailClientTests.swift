//
//  PIRDebugEmailClientTests.swift
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

import Common
import DataBrokerProtectionCore
import XCTest
@testable import PIRDebugKit

final class PIRDebugEmailClientTests: XCTestCase {

    private let attemptId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private var session: URLSession!
    /// Requests the stub served, in order, for asserting on paths/headers/bodies.
    private var requests: [URLRequest] = []

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        session = nil
        requests = []
        super.tearDown()
    }

    private func makeClient(token: String? = "test-token") throws -> PIRDebugEmailClient {
        try PIRDebugEmailClient(authManager: StaticTokenAuthenticationManager(token: token),
                                servicesEndpoint: .custom(URL(string: "https://services.example")!),
                                pixelHandler: EventMapping { _, _, _, _ in },
                                urlSession: session)
    }

    /// Serves `json` for every request, recording each one.
    private func stub(statusCode: Int = 200, json: String) {
        StubURLProtocol.handler = { [weak self] request in
            self?.requests.append(request)
            return .init(statusCode: statusCode, data: Data(json.utf8), headers: [:])
        }
    }

    // MARK: - generate

    func testGenerateEmailHitsV0GenerateAndReturnsAddress() async throws {
        stub(json: #"{"pattern": "fake+*@duck.com", "emailAddress": "abc@duck.com"}"#)

        let generated = try await makeClient().generateEmail(dataBrokerURL: "fakebroker.com", attemptId: attemptId)

        XCTAssertEqual(generated.dataBroker, "fakebroker.com")
        XCTAssertEqual(generated.email, "abc@duck.com")
        XCTAssertEqual(generated.pattern, "fake+*@duck.com")
        XCTAssertEqual(generated.attemptId, attemptId.uuidString)
        XCTAssertEqual(generated.mailbox, PIRDebugEmailMailbox(email: "abc@duck.com", attemptId: attemptId))

        let request = try XCTUnwrap(requests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/dbp/em/v0/generate")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "dataBroker" })?.value, "fakebroker.com")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "attemptId" })?.value, attemptId.uuidString)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "bearer test-token")
    }

    func testGenerateEmailWithoutTokenThrows() async throws {
        stub(json: #"{"emailAddress": "abc@duck.com"}"#)

        do {
            _ = try await makeClient(token: nil).generateEmail(dataBrokerURL: "fakebroker.com", attemptId: attemptId)
            XCTFail("Expected a missing-token failure")
        } catch {
            XCTAssertEqual(error as? AuthenticationError, .noAuthToken)
            XCTAssertTrue(requests.isEmpty, "No request should be sent without a token")
        }
    }

    func testGenerateEmailPropagatesHTTPError() async throws {
        stub(statusCode: 500, json: "{}")

        do {
            _ = try await makeClient().generateEmail(dataBrokerURL: "fakebroker.com", attemptId: attemptId)
            XCTFail("Expected an HTTP failure")
        } catch {
            XCTAssertEqual(error as? EmailError, .httpError(statusCode: 500))
        }
    }

    // MARK: - inbox

    func testFetchInboxDecodesReadyItem() async throws {
        stub(json: """
        {"items": [{"email": "abc@duck.com",
                    "attemptId": "\(attemptId.uuidString)",
                    "status": "ready",
                    "data": [{"name": "link", "value": "https://fakebroker.com/confirm"},
                             {"name": "code", "value": "12345"}],
                    "email_received_at": 1785000000.5}]}
        """)

        let items = try await makeClient().fetchInbox([.init(email: "abc@duck.com", attemptId: attemptId)])

        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.status, .ready)
        XCTAssertEqual(item.confirmationLink, "https://fakebroker.com/confirm")
        XCTAssertEqual(item.data, ["link": "https://fakebroker.com/confirm", "code": "12345"])
        XCTAssertEqual(item.receivedAt, Date(timeIntervalSince1970: 1785000000.5))
        XCTAssertNil(item.errorCode)

        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/dbp/em/v1/email-data")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "bearer test-token")
    }

    func testFetchInboxDecodesPendingAndErrorItems() async throws {
        stub(json: """
        {"items": [{"email": "pending@duck.com", "attemptId": "\(attemptId.uuidString)",
                    "status": "pending", "data": []},
                   {"email": "broken@duck.com", "attemptId": "\(attemptId.uuidString)",
                    "status": "error", "error_code": "extraction_error", "data": []}]}
        """)

        let items = try await makeClient().fetchInbox([
            .init(email: "pending@duck.com", attemptId: attemptId),
            .init(email: "broken@duck.com", attemptId: attemptId)
        ])

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].status, .pending)
        XCTAssertNil(items[0].confirmationLink)
        XCTAssertTrue(items[0].data.isEmpty)
        XCTAssertEqual(items[1].status, .error)
        XCTAssertEqual(items[1].errorCode, "extraction_error")
    }

    func testFetchInboxRejectsAnOverSizedBatch() async throws {
        stub(json: #"{"items": []}"#)
        let mailboxes = (0...EmailServiceV1.Constants.maxBatchSize).map {
            PIRDebugEmailMailbox(email: "\($0)@duck.com", attemptId: attemptId)
        }

        do {
            _ = try await makeClient().fetchInbox(mailboxes)
            XCTFail("Expected an over-sized batch to be rejected")
        } catch let error as PIRDebugError {
            guard case .emailBatchTooLarge(let count, let maximum) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(count, EmailServiceV1.Constants.maxBatchSize + 1)
            XCTAssertEqual(maximum, EmailServiceV1.Constants.maxBatchSize)
            XCTAssertTrue(requests.isEmpty, "The request must not be sent")
        }
    }

    // MARK: - delete

    func testDeleteInboxPostsToTheDeleteEndpoint() async throws {
        stub(json: "{}")

        try await makeClient().deleteInbox([.init(email: "abc@duck.com", attemptId: attemptId)])

        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/dbp/em/v1/email-data/delete")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testDeleteInboxWithNoMailboxesSendsNothing() async throws {
        stub(json: "{}")

        try await makeClient().deleteInbox([])

        XCTAssertTrue(requests.isEmpty)
    }

    // MARK: - Codable

    func testInboxItemRoundTripsThroughJSON() async throws {
        stub(json: """
        {"items": [{"email": "abc@duck.com", "attemptId": "\(attemptId.uuidString)",
                    "status": "ready",
                    "data": [{"name": "link", "value": "https://fakebroker.com/confirm"}],
                    "email_received_at": 1785000000.5}]}
        """)
        let items = try await makeClient().fetchInbox([.init(email: "abc@duck.com", attemptId: attemptId)])
        let item = try XCTUnwrap(items.first)

        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(PIRDebugEmailInboxItem.self, from: encoded)

        XCTAssertEqual(decoded, item)
        // Timestamps are emitted as ISO-8601, matching PIRDebugEvent rather than a raw Date.
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["receivedAt"] as? String, "2026-07-25T17:20:00.500Z")
    }
}
