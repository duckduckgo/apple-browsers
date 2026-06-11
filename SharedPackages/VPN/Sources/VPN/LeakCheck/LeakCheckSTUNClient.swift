//
//  LeakCheckSTUNClient.swift
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

public protocol LeakCheckSTUNClient: Sendable {
    func fetchIP(
        host: String,
        port: UInt16,
        ipVersion: IPVersion,
        timeout: TimeInterval,
        requiredInterface: NWInterface?
    ) async throws -> String
}

public struct DefaultLeakCheckSTUNClient: LeakCheckSTUNClient {

    public init() {}

    public func fetchIP(
        host: String,
        port: UInt16,
        ipVersion: IPVersion,
        timeout: TimeInterval,
        requiredInterface: NWInterface?
    ) async throws -> String {
        let transactionID = STUNMessage.randomTransactionID()
        let request = STUNMessage.bindingRequest(transactionID: transactionID)

        let parameters = NWParameters.udp
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

        // `perform` is parked in `withCheckedThrowingContinuation` and won't observe Task
        // cancellation on its own — `withTaskCancellationHandler` cancels the connection so the
        // state handler resumes the continuation and the timeout doesn't deadlock waiting.
        return try await withTimeout(timeout, throwing: URLError(.timedOut)) {
            try await withTaskCancellationHandler {
                try await Self.perform(connection: connection, request: request, transactionID: transactionID)
            } onCancel: {
                connection.cancel()
            }
        }
    }

    private static func perform(
        connection: NWConnection,
        request: Data,
        transactionID: Data
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let state = STUNContinuationState(continuation)

            connection.stateUpdateHandler = { nwState in
                switch nwState {
                case .ready:
                    connection.send(content: request, completion: .contentProcessed { sendError in
                        if let sendError = sendError {
                            state.resume(.failure(sendError))
                            return
                        }
                        connection.receiveMessage { data, _, _, recvError in
                            if let recvError = recvError {
                                state.resume(.failure(recvError))
                                return
                            }
                            guard let data = data else {
                                state.resume(.failure(URLError(.badServerResponse)))
                                return
                            }
                            do {
                                let ip = try STUNMessage.extractMappedAddress(from: data, transactionID: transactionID)
                                state.resume(.success(ip))
                            } catch {
                                state.resume(.failure(error))
                            }
                        }
                    })
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

private final class STUNContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<String, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
