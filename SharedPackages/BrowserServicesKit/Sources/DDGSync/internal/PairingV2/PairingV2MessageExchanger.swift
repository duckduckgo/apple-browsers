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
        try await executeRequestIgnoringResponse(request, validatingStatusWith: validateSuccessfulStatusCode)
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
        let result = try await executeRequest(request, validatingStatusWith: validateMessageExchangeStatusCode)
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
        try await executeRequestIgnoringResponse(request, validatingStatusWith: validateCloseChannelStatusCode)
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

    private func executeRequest(_ request: HTTPRequesting, validatingStatusWith validateStatusCode: (Int) throws -> Void) async throws -> HTTPResult {
        do {
            let result = try await request.execute()
            try validateStatusCode(result.response.statusCode)
            return result
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            // Some request implementations throw status-code errors instead of returning a response.
            // Re-run the injected validator so endpoint-specific status mapping still applies.
            try validateStatusCode(statusCode)
            throw SyncError.unexpectedStatusCode(statusCode)
        }
    }

    private func executeRequestIgnoringResponse(_ request: HTTPRequesting, validatingStatusWith validateStatusCode: (Int) throws -> Void) async throws {
        do {
            let result = try await request.execute()
            try validateStatusCode(result.response.statusCode)
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            // Some request implementations throw status-code errors instead of returning a response.
            // Re-run the injected validator so endpoint-specific status mapping still applies.
            try validateStatusCode(statusCode)
        }
    }

    private func executeMessagePost(_ request: HTTPRequesting, to channelID: String) async throws {
        var retryDelays = channelsWithCompletedFirstMessagePost.contains(channelID) ? [] : firstMessagePostChannelUnavailableRetryDelays

        while true {
            do {
                let result = try await request.execute()
                try validateMessageExchangeStatusCode(result.response.statusCode)
                channelsWithCompletedFirstMessagePost.insert(channelID)
                return
            } catch {
                let error = normalizeMessageExchangeError(error)
                if case PairingV2Error.relayChannelUnavailable = error,
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

    private func normalizeMessageExchangeError(_ error: Error) -> Error {
        guard case SyncError.unexpectedStatusCode(let statusCode) = error else {
            return error
        }

        do {
            try validateMessageExchangeStatusCode(statusCode)
            return error
        } catch let normalizedError {
            return normalizedError
        }
    }

    private func validateSuccessfulStatusCode(_ statusCode: Int) throws {
        guard statusCode.isSuccessfulHTTPStatusCode else {
            throw SyncError.unexpectedStatusCode(statusCode)
        }
    }

    private func validateMessageExchangeStatusCode(_ statusCode: Int) throws {
        switch statusCode {
        case 404:
            throw PairingV2Error.relayChannelUnavailable
        case 410:
            throw PairingV2Error.relayChannelExpired
        default:
            try validateSuccessfulStatusCode(statusCode)
        }
    }

    private func validateCloseChannelStatusCode(_ statusCode: Int) throws {
        switch statusCode {
        case 404, 410:
            return
        default:
            try validateSuccessfulStatusCode(statusCode)
        }
    }
}

private extension Int {

    var isSuccessfulHTTPStatusCode: Bool {
        (200..<300).contains(self)
    }
}
