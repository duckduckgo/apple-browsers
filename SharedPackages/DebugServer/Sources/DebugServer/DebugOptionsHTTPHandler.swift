//
//  DebugOptionsHTTPHandler.swift
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

import DebugOptions
import Foundation
import os

/// The wire contract is independent of option IDs and platform-specific handlers.
public struct DebugOptionsHTTPHandler: Sendable {
    public static let root = "/api/v1/debug-options"
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.duckduckgo.debug-options", category: "DebugOptionsAPI")
    private let registry: DebugOptionRegistry
    private let token: String

    public init(registry: DebugOptionRegistry, token: String) throws {
        guard token.utf8.count >= 32 else {
            throw DebugOptionError(code: .invalidParameters, message: "The server requires a session token of at least 32 bytes.")
        }
        self.registry = registry
        self.token = token
    }

    public func register(on server: DebugHTTPServer) {
        server.addAsyncRoute(Self.root, method: .GET) { request in await handle(request) }
        server.addAsyncRoute(Self.root + "/modify", method: .POST) { request in await handle(request) }
    }

    public func handle(_ request: HTTPRequest) async -> HTTPResponse {
        let requestID = UUID().uuidString
        let started = ProcessInfo.processInfo.systemUptime
        Self.logger.notice("[DebugOptions API] [\(requestID, privacy: .public)] Received \(request.method.rawValue, privacy: .public) \(logValue(request.path), privacy: .public)")
        let response = await handle(request, requestID: requestID)
        let milliseconds = Int((ProcessInfo.processInfo.systemUptime - started) * 1_000)
        if response.status.rawValue >= 400 {
            Self.logger.error("[DebugOptions API] [\(requestID, privacy: .public)] Failed: HTTP \(response.status.rawValue) in \(milliseconds) ms")
        } else {
            Self.logger.notice("[DebugOptions API] [\(requestID, privacy: .public)] Completed: HTTP \(response.status.rawValue) in \(milliseconds) ms")
        }
        return response
    }

    private func handle(_ request: HTTPRequest, requestID: String) async -> HTTPResponse {
        let authorization = request.headers.first { $0.key.caseInsensitiveCompare("Authorization") == .orderedSame }?.value
        guard authorization == "Bearer " + token else {
            Self.logger.warning("[DebugOptions API] [\(requestID, privacy: .public)] Rejected: unauthorized")
            return response(.object(["error": .object(["code": .string("unauthorized"), "message": .string("A valid bearer token is required.")])]),
                            status: .unauthorized)
        }
        var invocation: DebugOptionInvocation?
        do {
            if request.path == Self.root, request.method == .GET {
                let options = await registry.discover()
                return try encodedResponse(Discovery(options: options))
            }
            guard request.path == Self.root + "/modify", request.method == .POST else {
                Self.logger.warning("[DebugOptions API] [\(requestID, privacy: .public)] Rejected: unsupportedRequest")
                return response(.object(["error": .object(["code": .string("unsupportedRequest")])]), status: .methodNotAllowed)
            }
            let contentType = request.headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
            guard contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json",
                  let body = request.body, body.count <= 65_536 else {
                throw DebugOptionError(code: .invalidParameters, message: "Provide an application/json body of at most 64 KiB.")
            }
            do {
                invocation = try JSONDecoder().decode(DebugOptionInvocation.self, from: body)
            } catch {
                throw DebugOptionError(code: .invalidParameters, message: "Provide id, action, and an object containing parameters.")
            }
            guard let invocation else { preconditionFailure("Invocation decoded above") }
            Self.logger.notice("[DebugOptions API] [\(requestID, privacy: .public)] Executing id=\(logValue(invocation.id), privacy: .public) action=\(logValue(invocation.action), privacy: .public)")
            let result = try await registry.execute(invocation)
            return try encodedResponse(Execution(id: invocation.id, action: invocation.action, result: result))
        } catch let error as DebugOptionError {
            return errorResponse(error, invocation: invocation, requestID: requestID)
        } catch is CancellationError {
            return errorResponse(.init(code: .unavailable, message: "The request was cancelled."), invocation: invocation, requestID: requestID)
        } catch {
            return errorResponse(.init(code: .internalError, message: "The debug action failed."), invocation: invocation, requestID: requestID)
        }
    }

    private struct Discovery: Encodable {
        let apiVersion = 1
        let options: [DebugOptionDescriptor]
    }

    private struct Execution: Encodable {
        let id: String
        let action: String
        let result: DebugValue
    }

    private struct Failure: Encodable {
        let id: String?
        let action: String?
        let error: DebugOptionError
    }

    private func errorResponse(_ error: DebugOptionError, invocation: DebugOptionInvocation?, requestID: String) -> HTTPResponse {
        Self.logger.error("[DebugOptions API] [\(requestID, privacy: .public)] Error: \(error.code.rawValue, privacy: .public)")
        let status: HTTPStatusCode
        switch error.code {
        case .unknownOption: status = .notFound
        case .unsupportedAction, .invalidParameters: status = .badRequest
        case .unavailable: status = .forbidden
        case .conflict, .busy: status = .conflict
        case .refreshFailed: status = .unprocessableEntity
        case .internalError: status = .internalServerError
        }
        return (try? encodedResponse(Failure(id: invocation?.id, action: invocation?.action, error: error), status: status))
            ?? .empty(status: .internalServerError)
    }

    private func response(_ value: DebugValue, status: HTTPStatusCode) -> HTTPResponse {
        (try? encodedResponse(value, status: status)) ?? .empty(status: .internalServerError)
    }

    /// Keep caller-supplied identifiers on one console line and bound their length.
    private func logValue(_ value: String) -> String {
        String(value.prefix(160)).debugDescription
    }

    private func encodedResponse(_ value: some Encodable, status: HTTPStatusCode = .ok) throws -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return HTTPResponse(status: status, headers: ["Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store"],
                            body: try encoder.encode(value))
    }
}
