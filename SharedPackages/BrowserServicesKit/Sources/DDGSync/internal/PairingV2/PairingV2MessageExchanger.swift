//
//  PairingV2MessageExchanger.swift
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

/// Relay transport for Pairing V2: a device fetches from its own channel and sends to the peer's,
/// so one connect flow addresses two channel IDs.
protocol PairingV2MessageExchanging {
    /// Creates this device's own channel (its inbox) so the peer can write to it.
    func openChannel(_ channelID: String) async throws
    /// Sends encrypted messages to the peer's channel.
    func send(_ messages: [PairingV2EncryptedMessage], to channelID: String) async throws
    /// Fetches new messages from this device's own channel, after the given sequence number.
    func fetchMessages(from channelID: String, after sequence: Int) async throws -> [PairingV2SequencedMessage]
    /// Deletes this device's own channel once it stops polling.
    func closeChannel(_ channelID: String) async throws
}

final class PairingV2MessageExchanger: PairingV2MessageExchanging {

    let endpoints: Endpoints
    let api: RemoteAPIRequestCreating
    /// Retry delays for a first message POST when the peer channel isn't available yet (gives channel
    /// creation time to propagate). Nanoseconds; default is 0.2s then 0.5s — two retries.
    private let firstMessagePostChannelUnavailableRetryDelays: [UInt64]
    private var channelsWithCompletedFirstMessagePost: Set<String> = []

    init(endpoints: Endpoints,
         api: RemoteAPIRequestCreating,
         firstMessagePostChannelUnavailableRetryDelays: [UInt64] = [200_000_000, 500_000_000]) {
        self.endpoints = endpoints
        self.api = api
        self.firstMessagePostChannelUnavailableRetryDelays = firstMessagePostChannelUnavailableRetryDelays
    }

    func openChannel(_ channelID: String) async throws {
        let request = api.createRequest(url: channelURL(channelID),
                                        method: .put,
                                        headers: [:],
                                        parameters: [:],
                                        body: nil,
                                        contentType: nil)
        _ = try await executeRelayRequest(request)
    }

    func send(_ messages: [PairingV2EncryptedMessage], to channelID: String) async throws {
        let body = try JSONEncoder.snakeCaseKeys.encode(SendMessagesRequest(messages: messages))
        let request = api.createRequest(url: messagesURL(channelID),
                                        method: .post,
                                        headers: [:],
                                        parameters: [:],
                                        body: body,
                                        contentType: "application/json")
        try await executeMessagePost(request, to: channelID)
    }

    func fetchMessages(from channelID: String, after sequence: Int) async throws -> [PairingV2SequencedMessage] {
        let request = api.createRequest(url: messagesURL(channelID),
                                        method: .get,
                                        headers: [:],
                                        parameters: ["after": String(sequence)],
                                        body: nil,
                                        contentType: nil)
        let result = try await executeRelayRequest(request)
        guard let body = result.data else {
            throw SyncError.noResponseBody
        }
        return try JSONDecoder.snakeCaseKeys.decode(FetchMessagesResponse.self, from: body).messages
    }

    func closeChannel(_ channelID: String) async throws {
        let request = api.createRequest(url: channelURL(channelID),
                                        method: .delete,
                                        headers: [:],
                                        parameters: [:],
                                        body: nil,
                                        contentType: nil)
        try await executeCloseRequest(request)
    }

    private struct SendMessagesRequest: Encodable {
        let messages: [PairingV2EncryptedMessage]
    }

    private struct FetchMessagesResponse: Decodable {
        let messages: [PairingV2SequencedMessage]
    }

    private func channelURL(_ channelID: String) -> URL {
        endpoints.pairingV2Exchange.appendingPathComponent(channelID)
    }

    private func messagesURL(_ channelID: String) -> URL {
        channelURL(channelID).appendingPathComponent("messages")
    }

    private func executeRelayRequest(_ request: HTTPRequesting) async throws -> HTTPResult {
        do {
            let result = try await request.execute()
            guard result.response.statusCode.isSuccessfulHTTPStatusCode else {
                throw relayRequestError(statusCode: result.response.statusCode)
            }
            return result
        } catch let error as PairingV2RelayRequestError {
            throw error
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            throw relayRequestError(statusCode: statusCode)
        } catch {
            throw PairingV2RelayRequestError(kind: .networkError, underlyingError: error)
        }
    }

    private func executeCloseRequest(_ request: HTTPRequesting) async throws {
        do {
            let result = try await request.execute()
            try validateCloseChannelStatusCode(result.response.statusCode)
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            // Some request implementations throw status-code errors instead of returning a response.
            // Apply the close endpoint's status rules to the thrown status as well.
            try validateCloseChannelStatusCode(statusCode)
        }
    }

    private func executeMessagePost(_ request: HTTPRequesting, to channelID: String) async throws {
        var retryDelays = channelsWithCompletedFirstMessagePost.contains(channelID) ? [] : firstMessagePostChannelUnavailableRetryDelays

        while true {
            do {
                _ = try await executeRelayRequest(request)
                channelsWithCompletedFirstMessagePost.insert(channelID)
                return
            } catch let error as PairingV2RelayRequestError {
                if error.kind == .unavailable,
                   !channelsWithCompletedFirstMessagePost.contains(channelID),
                   !retryDelays.isEmpty {
                    let retryDelay = retryDelays.removeFirst()
                    if retryDelay > 0 {
                        try await Task.sleep(nanoseconds: retryDelay)
                    }
                    continue
                }
                throw error
            }
        }
    }

    private func relayRequestError(statusCode: Int) -> PairingV2RelayRequestError {
        let underlyingError: Error
        switch statusCode {
        case 404:
            underlyingError = PairingV2Error.relayChannelUnavailable
        case 410:
            underlyingError = PairingV2Error.relayChannelExpired
        default:
            underlyingError = SyncError.unexpectedStatusCode(statusCode)
        }
        return PairingV2RelayRequestError(kind: PairingV2FailureKind(statusCode: statusCode), underlyingError: underlyingError)
    }

    private func validateCloseChannelStatusCode(_ statusCode: Int) throws {
        switch statusCode {
        case 404, 410:
            return
        default:
            guard statusCode.isSuccessfulHTTPStatusCode else {
                throw SyncError.unexpectedStatusCode(statusCode)
            }
        }
    }
}

private extension Int {

    var isSuccessfulHTTPStatusCode: Bool {
        (200..<300).contains(self)
    }
}
