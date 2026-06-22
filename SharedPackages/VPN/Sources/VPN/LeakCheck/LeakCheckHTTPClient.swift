//
//  LeakCheckHTTPClient.swift
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
import ConcurrencyExtensions
import Foundation
import FoundationExtensions
import Network

public protocol LeakCheckHTTPClient: Sendable {
    func fetchIP(
        host: String,
        port: UInt16,
        usesTLS: Bool,
        ipVersion: IPVersion,
        timeout: TimeInterval,
        requiredInterface: NWInterface?
    ) async throws -> String
}

enum LeakCheckHTTPResponseParser {

    enum ParseError: Error, Equatable {
        case malformedResponse
        case nonSuccessStatus(Int)
        case missingBody
        case malformedJSON
        case missingIP
    }

    private struct Payload: Decodable { let ip: String }

    static func parse(_ raw: String) throws -> String {
        guard let headerBodySplit = raw.range(of: "\r\n\r\n") else {
            throw ParseError.malformedResponse
        }
        let headers = raw[..<headerBodySplit.lowerBound]
        let body = raw[headerBodySplit.upperBound...]

        guard let statusLine = headers.split(separator: "\r\n").first else {
            throw ParseError.malformedResponse
        }
        let statusParts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard statusParts.count >= 2, let status = Int(statusParts[1]) else {
            throw ParseError.malformedResponse
        }
        guard (200..<300).contains(status) else {
            throw ParseError.nonSuccessStatus(status)
        }
        guard !body.isEmpty, let data = String(body).data(using: .utf8) else {
            throw ParseError.missingBody
        }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard !payload.ip.isEmpty else { throw ParseError.missingIP }
            return payload.ip
        } catch is DecodingError {
            throw ParseError.malformedJSON
        }
    }
}

public struct DefaultLeakCheckHTTPClient: LeakCheckHTTPClient {

    public init() {}

    public func fetchIP(
        host: String,
        port: UInt16,
        usesTLS: Bool,
        ipVersion: IPVersion,
        timeout: TimeInterval,
        requiredInterface: NWInterface?
    ) async throws -> String {
        let parameters: NWParameters = usesTLS ? NWParameters(tls: NWProtocolTLS.Options()) : .tcp
        if let ipOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            switch ipVersion {
            case .v4: ipOptions.version = .v4
            case .v6: ipOptions.version = .v6
            }
        }
        parameters.requiredInterface = requiredInterface

        let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(integerLiteral: port))
        let connection = NWConnection(to: endpoint, using: parameters)
        defer { connection.cancel() }

        let request = "GET / HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\n\r\n"

        // `perform` is parked in `withCheckedThrowingContinuation` and won't observe Task
        // cancellation on its own — `withTaskCancellationHandler` cancels the connection so the
        // state handler resumes the continuation and the timeout doesn't deadlock waiting.
        return try await withTimeout(timeout, throwing: URLError(.timedOut)) {
            try await withTaskCancellationHandler {
                try await Self.perform(connection: connection, request: request)
            } onCancel: {
                connection.cancel()
            }
        }
    }

    private static func perform(connection: NWConnection, request: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let state = HTTPReceiveState(continuation)

            func receiveLoop() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                    if let error = error {
                        state.resume(.failure(error))
                        return
                    }
                    if let data = data { state.append(data) }
                    if isComplete {
                        let buffer = state.currentBuffer()
                        guard let raw = String(data: buffer, encoding: .utf8) else {
                            state.resume(.failure(URLError(.cannotDecodeContentData)))
                            return
                        }
                        do {
                            state.resume(.success(try LeakCheckHTTPResponseParser.parse(raw)))
                        } catch {
                            state.resume(.failure(error))
                        }
                        return
                    }
                    receiveLoop()
                }
            }

            connection.stateUpdateHandler = { nwState in
                switch nwState {
                case .ready:
                    connection.send(
                        content: Data(request.utf8),
                        completion: .contentProcessed { sendError in
                            if let sendError = sendError {
                                state.resume(.failure(sendError))
                                return
                            }
                            receiveLoop()
                        }
                    )
                case .failed(let error):
                    state.resume(.failure(error))
                case .waiting(let error):
                    state.resume(.failure(error))
                case .cancelled:
                    state.resume(.failure(CancellationError()))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
        }
    }
}

private final class HTTPReceiveState: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var continuation: CheckedContinuation<String, Error>?

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }

    func currentBuffer() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func resume(_ result: Result<String, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
