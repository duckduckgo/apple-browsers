//
//  DataBrokerProtectionDebugControl.swift
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

import DataBrokerProtectionCore
import DebugServer
import Foundation
import WebKit

/// Lets the debug server change PIR state and run jobs, on top of reading it.
public protocol DataBrokerProtectionDebugControlling: AnyObject {
    /// Saves the broker JSON, replacing any stored broker with the same URL whatever its version.
    func installBroker(json: Data) async throws -> DebugInstalledBroker
    /// Starts the broker's scan for every profile query in a visible window, and returns without waiting for it.
    func runScans(brokerIdentifier: String) async throws -> DebugScanRun
    /// `droppingSubmitted` clears submitted attempts first, as a dashboard reload does.
    func assistedOptOutsForDebugging(droppingSubmitted: Bool) async -> DebugAssistedOptOuts
    func startAssistedOptOutForDebugging(id: String) async throws
    func cancelAssistedOptOutForDebugging(id: String) async throws
}

public enum DataBrokerProtectionDebugControlError: LocalizedError {
    case brokerNotFound(String)
    case assistedOptOutNotFound(String)
    case userAssistanceDisabled(String)

    public var errorDescription: String? {
        switch self {
        case .brokerNotFound(let identifier):
            return "Broker not found: \(identifier)"
        case .assistedOptOutNotFound(let id):
            return "Assisted opt-out not found: \(id)"
        case .userAssistanceDisabled(let reason):
            return "User assistance is off: \(reason)"
        }
    }
}

public struct DebugInstalledBroker: Encodable {
    public let id: Int64?
    public let name: String
    public let url: String
    public let version: String
    public let isRemoved: Bool

    public init(id: Int64?, name: String, url: String, version: String, isRemoved: Bool) {
        self.id = id
        self.name = name
        self.url = url
        self.version = version
        self.isRemoved = isRemoved
    }
}

public struct DebugScanRun: Encodable {
    public let broker: String
    public let profileQueryIds: [Int64]

    public init(broker: String, profileQueryIds: [Int64]) {
        self.broker = broker
        self.profileQueryIds = profileQueryIds
    }
}

public struct DebugAssistedOptOuts: Encodable {
    public let isFeatureOn: Bool
    public let enabledBrokers: [String]
    public let optOuts: [AssistedOptOut]

    public init(isFeatureOn: Bool, enabledBrokers: [String], optOuts: [AssistedOptOut]) {
        self.isFeatureOn = isFeatureOn
        self.enabledBrokers = enabledBrokers
        self.optOuts = optOuts
    }
}

struct DebugWebViewSummary: Encodable {
    let id: Int
    let brokerURL: String?
    let createdAt: Date
    let url: String?
    let title: String?
    let isLoading: Bool
    let isVisible: Bool
}

struct DebugEvaluationResult: Encodable {
    let result: DebugJSONValue
}

/// Any JSON value a page script returns.
enum DebugJSONValue: Encodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([DebugJSONValue])
    case object([String: DebugJSONValue])

    init(_ value: Any?) {
        switch value {
        case nil, is NSNull:
            self = .null
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            self = .bool(number.boolValue)
        case let number as NSNumber:
            self = .number(number.doubleValue)
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.map(DebugJSONValue.init))
        case let dictionary as [String: Any]:
            self = .object(dictionary.mapValues(DebugJSONValue.init))
        case let value?:
            self = .string(String(describing: value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// Web view inspection for the debug server. Route handlers are synchronous and run off the main thread,
/// so each call blocks the server's queue until the main-actor work finishes.
enum DebugWebViewInspector {

    static func summaries() throws -> [DebugWebViewSummary] {
        try awaitMainActor {
            DataBrokerProtectionDebugWebViews.shared.live.compactMap { entry in
                guard let webView = entry.webView else { return nil }
                return DebugWebViewSummary(id: entry.id,
                                           brokerURL: entry.brokerURL,
                                           createdAt: entry.createdAt,
                                           url: webView.url?.absoluteString,
                                           title: webView.title,
                                           isLoading: webView.isLoading,
                                           isVisible: webView.window?.isVisible ?? false)
            }
        }
    }

    static func screenshot(id: Int) throws -> Data? {
        try awaitMainActor {
            guard let webView = DataBrokerProtectionDebugWebViews.shared.entry(id: id)?.webView else { return nil }
            let image = try await webView.takeSnapshot(configuration: nil)
#if os(macOS)
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
            return bitmap.representation(using: .png, properties: [:])
#else
            return image.pngData()
#endif
        }
    }

    /// Runs `body` as an async function in the page, so it can `await` and must `return` its result.
    static func evaluate(id: Int, body: String) throws -> DebugEvaluationResult? {
        try awaitMainActor {
            guard let webView = DataBrokerProtectionDebugWebViews.shared.entry(id: id)?.webView else { return nil }
            let value = try await webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: .page)
            return DebugEvaluationResult(result: DebugJSONValue(value))
        }
    }

    static func load(id: Int, url: URL) throws -> Bool {
        try awaitMainActor {
            guard let webView = DataBrokerProtectionDebugWebViews.shared.entry(id: id)?.webView else { return false }
            webView.load(URLRequest(url: url))
            return true
        }
    }
}

enum DebugAwaitError: LocalizedError {
    case timedOut

    var errorDescription: String? { "Timed out waiting for the agent" }
}

private final class ResultBox<Value>: @unchecked Sendable {
    var result: Result<Value, Error>?
}

/// Blocks the calling (non-main) thread until `operation` finishes on the main actor.
func awaitMainActor<Value>(timeout: TimeInterval = 60, _ operation: @escaping @MainActor () async throws -> Value) throws -> Value {
    precondition(!Thread.isMainThread, "Debug server routes must not block the main thread")
    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox<Value>()
    Task { @MainActor in
        do {
            box.result = .success(try await operation())
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + timeout) == .success, let result = box.result else {
        throw DebugAwaitError.timedOut
    }
    return try result.get()
}
