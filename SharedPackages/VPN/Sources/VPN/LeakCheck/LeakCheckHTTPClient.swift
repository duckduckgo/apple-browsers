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

import Foundation
import Network

public protocol LeakCheckHTTPClient: Sendable {
    func fetchIP(
        host: String,
        port: UInt16,
        scheme: LeakCheckScheme,
        ipVersion: IPVersion,
        timeout: TimeInterval
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
        } catch ParseError.missingIP {
            throw ParseError.missingIP
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
        scheme: LeakCheckScheme,
        ipVersion: IPVersion,
        timeout: TimeInterval
    ) async throws -> String {
        let parameters: NWParameters
        switch scheme {
        case .http:
            parameters = NWParameters.tcp
        case .https:
            parameters = NWParameters(tls: NWProtocolTLS.Options())
        }
        if let ipOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            switch ipVersion {
            case .v4: ipOptions.version = .v4
            case .v6: ipOptions.version = .v6
            }
        }

        let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(integerLiteral: port))
        let connection = NWConnection(to: endpoint, using: parameters)
        defer { connection.cancel() }

        let request = "GET / HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\n\r\n"

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await Self.perform(connection: connection, request: request)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw URLError(.timedOut)
            }
            guard let first = try await group.next() else {
                throw URLError(.badServerResponse)
            }
            group.cancelAll()
            return first
        }
    }

    private static func perform(connection: NWConnection, request: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var buffer = Data()
            var didResume = false
            func resume(_ result: Result<String, Error>) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            func receiveLoop() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                    if let error = error {
                        resume(.failure(error))
                        return
                    }
                    if let data = data { buffer.append(data) }
                    if isComplete {
                        guard let raw = String(data: buffer, encoding: .utf8) else {
                            resume(.failure(URLError(.cannotDecodeContentData)))
                            return
                        }
                        do {
                            resume(.success(try LeakCheckHTTPResponseParser.parse(raw)))
                        } catch {
                            resume(.failure(error))
                        }
                        return
                    }
                    receiveLoop()
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(
                        content: request.data(using: .utf8),
                        completion: .contentProcessed { sendError in
                            if let sendError = sendError {
                                resume(.failure(sendError))
                                return
                            }
                            receiveLoop()
                        }
                    )
                case .failed(let error):
                    resume(.failure(error))
                case .cancelled:
                    resume(.failure(CancellationError()))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
        }
    }
}
