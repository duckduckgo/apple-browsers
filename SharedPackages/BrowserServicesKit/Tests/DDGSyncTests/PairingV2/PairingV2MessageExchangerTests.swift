//
//  PairingV2MessageExchangerTests.swift
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
import XCTest

@testable import DDGSync

final class PairingV2MessageExchangerTests: XCTestCase {

    private let endpoints = Endpoints(baseURL: URL(string: "https://dev.null")!)
    private var api: RemoteAPIRequestCreatingMock!

    override func setUp() {
        super.setUp()
        api = RemoteAPIRequestCreatingMock()
    }

    override func tearDown() {
        api = nil
        super.tearDown()
    }

    func testWhenFetchMessagesReceives404ThenClassifiesUnavailable() async throws {
        api.request = makeRequest(statusCode: 404)
        let exchanger = makeExchanger()

        let error = await relayRequestError {
            _ = try await exchanger.fetchMessages(from: "channel", after: 0)
        }

        XCTAssertEqual(error?.kind, .unavailable)
        XCTAssertEqual(error?.underlyingError as? PairingV2Error, .relayChannelUnavailable)
    }

    func testWhenFetchMessagesReceives410ThenClassifiesExpired() async throws {
        api.request = makeRequest(statusCode: 410)
        let exchanger = makeExchanger()

        let error = await relayRequestError {
            _ = try await exchanger.fetchMessages(from: "channel", after: 0)
        }

        XCTAssertEqual(error?.kind, .expired)
        XCTAssertEqual(error?.underlyingError as? PairingV2Error, .relayChannelExpired)
    }

    func testWhenFetchMessagesReceivesOtherHTTPErrorThenClassifiesHTTPError() async throws {
        api.request = makeRequest(statusCode: 503)
        let exchanger = makeExchanger()

        let error = await relayRequestError {
            _ = try await exchanger.fetchMessages(from: "channel", after: 0)
        }

        XCTAssertEqual(error?.kind, .httpError)
        XCTAssertEqual(error?.underlyingError as? SyncError, .unexpectedStatusCode(503))
    }

    func testWhenFetchMessagesReceivesNoHTTPResponseThenClassifiesNetworkError() async throws {
        let request = HTTPRequestingMock()
        let underlyingError = URLError(.notConnectedToInternet)
        request.error = underlyingError
        api.request = request
        let exchanger = makeExchanger()

        let error = await relayRequestError {
            _ = try await exchanger.fetchMessages(from: "channel", after: 0)
        }

        XCTAssertEqual(error?.kind, .networkError)
        XCTAssertEqual((error?.underlyingError as? URLError)?.code, underlyingError.code)
    }

    func testWhenFetchMessagesReceivesMalformedSuccessfulResponseThenPreservesDecodingError() async throws {
        api.request = makeRequest(statusCode: 200, body: "invalid")
        let exchanger = makeExchanger()

        do {
            _ = try await exchanger.fetchMessages(from: "channel", after: 0)
            XCTFail("Expected decoding to fail")
        } catch {
            XCTAssertTrue(error is DecodingError)
            XCTAssertFalse(error is PairingV2RelayRequestError)
        }
    }

    func testWhenFirstSendReceivesTransient404ThenRetriesTwiceAndSucceeds() async throws {
        let request = SequencedHTTPRequestingMock(results: [
            .init(data: nil, response: makeHTTPURLResponse(statusCode: 404)),
            .init(data: nil, response: makeHTTPURLResponse(statusCode: 404)),
            .init(data: nil, response: makeHTTPURLResponse(statusCode: 204))
        ])
        api.request = request
        let exchanger = makeExchanger()

        try await exchanger.send([.init(payload: "payload")], to: "channel")

        XCTAssertEqual(request.executeCallCount, 3)
        XCTAssertEqual(api.createRequestCallCount, 1)
    }

    func testWhenFirstSendKeepsReceiving404ThenClassifiesUnavailableAfterRetryBudget() async throws {
        let request = SequencedHTTPRequestingMock(results: [
            .init(data: nil, response: makeHTTPURLResponse(statusCode: 404)),
            .init(data: nil, response: makeHTTPURLResponse(statusCode: 404)),
            .init(data: nil, response: makeHTTPURLResponse(statusCode: 404)),
            .init(data: nil, response: makeHTTPURLResponse(statusCode: 204))
        ])
        api.request = request
        let exchanger = makeExchanger()

        let error = await relayRequestError {
            try await exchanger.send([.init(payload: "payload")], to: "channel")
        }

        XCTAssertEqual(error?.kind, .unavailable)
        XCTAssertEqual(request.executeCallCount, 3)
        XCTAssertEqual(api.createRequestCallCount, 1)
    }

    func testWhenSendReceives404AfterFirstSuccessfulMessagePostThenClassifiesUnavailableWithoutRetrying() async throws {
        let request = SequencedHTTPRequestingMock(results: [
            .init(data: nil, response: makeHTTPURLResponse(statusCode: 204)),
            .init(data: nil, response: makeHTTPURLResponse(statusCode: 404)),
            .init(data: nil, response: makeHTTPURLResponse(statusCode: 204))
        ])
        api.request = request
        let exchanger = makeExchanger()

        try await exchanger.send([.init(payload: "first-payload")], to: "channel")
        let error = await relayRequestError {
            try await exchanger.send([.init(payload: "second-payload")], to: "channel")
        }

        XCTAssertEqual(error?.kind, .unavailable)
        XCTAssertEqual(request.executeCallCount, 2)
        XCTAssertEqual(api.createRequestCallCount, 2)
    }

    func testWhenSendReceives410ThenClassifiesExpired() async throws {
        api.request = makeRequest(statusCode: 410)
        let exchanger = makeExchanger()

        let error = await relayRequestError {
            try await exchanger.send([.init(payload: "payload")], to: "channel")
        }

        XCTAssertEqual(error?.kind, .expired)
    }

    func testWhenOpenChannelReceivesSuccessfulStatusThenSucceeds() async throws {
        api.request = makeRequest(statusCode: 201)
        let exchanger = makeExchanger()

        try await exchanger.openChannel("channel")

        XCTAssertEqual(api.createRequestCallCount, 1)
    }

    func testWhenOpenChannelReceives404ThenClassifiesUnavailable() async throws {
        api.request = makeRequest(statusCode: 404)
        let exchanger = makeExchanger()

        let error = await relayRequestError {
            try await exchanger.openChannel("channel")
        }

        XCTAssertEqual(error?.kind, .unavailable)
    }

    func testWhenCloseChannelReceivesMissingOrExpiredStatusThenSucceeds() async throws {
        for statusCode in [404, 410] {
            api.request = makeRequest(statusCode: statusCode)
            let exchanger = makeExchanger()

            try await exchanger.closeChannel("channel")
        }
    }

    private func makeExchanger() -> PairingV2MessageExchanger {
        PairingV2MessageExchanger(endpoints: endpoints, api: api, firstMessagePostChannelUnavailableRetryDelays: [0, 0])
    }

    private func makeRequest(statusCode: Int, body: String? = nil) -> HTTPRequestingMock {
        HTTPRequestingMock(result: .init(data: body.map { Data($0.utf8) },
                                         response: makeHTTPURLResponse(statusCode: statusCode)))
    }

    private func makeHTTPURLResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://dev.null/test")!,
                        statusCode: statusCode,
                        httpVersion: nil,
                        headerFields: nil)!
    }

    private func relayRequestError(operation: () async throws -> Void) async -> PairingV2RelayRequestError? {
        do {
            try await operation()
            XCTFail("Expected PairingV2RelayRequestError")
            return nil
        } catch let error as PairingV2RelayRequestError {
            return error
        } catch {
            XCTFail("Expected PairingV2RelayRequestError, got \(error)")
            return nil
        }
    }
}
