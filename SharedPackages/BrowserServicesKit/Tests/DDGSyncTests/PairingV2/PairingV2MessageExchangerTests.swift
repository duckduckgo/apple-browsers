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

    func testWhenFetchMessagesReceives404ThenThrowsRelayChannelUnavailable() async throws {
        api.request = makeRequest(statusCode: 404)
        let exchanger = makeExchanger()

        do {
            _ = try await exchanger.fetchMessages(from: "channel", after: 0)
            XCTFail("Expected PairingV2Error.relayChannelUnavailable")
        } catch PairingV2Error.relayChannelUnavailable {
        } catch {
            XCTFail("Expected PairingV2Error.relayChannelUnavailable, got \(error)")
        }
    }

    func testWhenFetchMessagesReceives410ThenThrowsRelayChannelExpired() async throws {
        api.request = makeRequest(statusCode: 410)
        let exchanger = makeExchanger()

        do {
            _ = try await exchanger.fetchMessages(from: "channel", after: 0)
            XCTFail("Expected PairingV2Error.relayChannelExpired")
        } catch PairingV2Error.relayChannelExpired {
        } catch {
            XCTFail("Expected PairingV2Error.relayChannelExpired, got \(error)")
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

    func testWhenFirstSendKeepsReceiving404ThenThrowsRelayChannelUnavailableAfterRetryBudget() async throws {
        let request = SequencedHTTPRequestingMock(results: [
            .init(data: nil, response: makeHTTPURLResponse(statusCode: 404)),
            .init(data: nil, response: makeHTTPURLResponse(statusCode: 404)),
            .init(data: nil, response: makeHTTPURLResponse(statusCode: 404)),
            .init(data: nil, response: makeHTTPURLResponse(statusCode: 204))
        ])
        api.request = request
        let exchanger = makeExchanger()

        do {
            try await exchanger.send([.init(payload: "payload")], to: "channel")
            XCTFail("Expected PairingV2Error.relayChannelUnavailable")
        } catch PairingV2Error.relayChannelUnavailable {
        } catch {
            XCTFail("Expected PairingV2Error.relayChannelUnavailable, got \(error)")
        }

        XCTAssertEqual(request.executeCallCount, 3)
        XCTAssertEqual(api.createRequestCallCount, 1)
    }

    func testWhenSendReceives404AfterFirstSuccessfulMessagePostThenThrowsRelayChannelUnavailableWithoutRetrying() async throws {
        let request = SequencedHTTPRequestingMock(results: [
            .init(data: nil, response: makeHTTPURLResponse(statusCode: 204)),
            .init(data: nil, response: makeHTTPURLResponse(statusCode: 404)),
            .init(data: nil, response: makeHTTPURLResponse(statusCode: 204))
        ])
        api.request = request
        let exchanger = makeExchanger()

        try await exchanger.send([.init(payload: "first-payload")], to: "channel")
        do {
            try await exchanger.send([.init(payload: "second-payload")], to: "channel")
            XCTFail("Expected PairingV2Error.relayChannelUnavailable")
        } catch PairingV2Error.relayChannelUnavailable {
        } catch {
            XCTFail("Expected PairingV2Error.relayChannelUnavailable, got \(error)")
        }

        XCTAssertEqual(request.executeCallCount, 2)
        XCTAssertEqual(api.createRequestCallCount, 2)
    }

    func testWhenSendReceives410ThenThrowsRelayChannelExpired() async throws {
        api.request = makeRequest(statusCode: 410)
        let exchanger = makeExchanger()

        do {
            try await exchanger.send([.init(payload: "payload")], to: "channel")
            XCTFail("Expected PairingV2Error.relayChannelExpired")
        } catch PairingV2Error.relayChannelExpired {
        } catch {
            XCTFail("Expected PairingV2Error.relayChannelExpired, got \(error)")
        }
    }

    func testWhenOpenChannelReceivesSuccessfulStatusThenSucceeds() async throws {
        api.request = makeRequest(statusCode: 201)
        let exchanger = makeExchanger()

        try await exchanger.openChannel("channel")

        XCTAssertEqual(api.createRequestCallCount, 1)
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
}
