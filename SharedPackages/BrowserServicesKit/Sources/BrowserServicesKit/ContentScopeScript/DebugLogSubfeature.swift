//
//  DebugLogSubfeature.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import WebKit
import UserScript
import os.log

/// Handles debug logging from C-S-S features
/// Routes `this.log.info/warn/error` calls to native os.log for Xcode visibility
///
/// This provides a DX improvement by making JS logs visible in Xcode console
/// alongside native Swift/ObjC logs, without requiring Safari Web Inspector.
///
/// ## Architecture: Cross-Cutting Concern
/// Debug logging is treated as a **cross-cutting concern** in the messaging layer.
/// When any feature sends `debugLog` or `signpost` messages, `UserScriptMessageBroker`
/// automatically routes them to this `debug` feature, regardless of the originating
/// feature name. This means:
/// - Features don't need to implement their own debugLog handlers
/// - Debug messages from any feature flow to a single, centralized handler
/// - Similar to how debug flags work as a system-wide concern
///
/// ## Usage
/// Register with ContentScopeUserScript:
/// ```swift
/// contentScopeUserScript.registerSubfeature(delegate: DebugLogSubfeature())
/// ```
///
/// ## JS Side (in C-S-S content-feature.js)
/// When `debug: true` and platform is ios/macos, `this.log.*` methods
/// will route logs via `this.notify('debugLog', {...})`
public final class DebugLogSubfeature: Subfeature {

    // MARK: - Types

    public struct DebugLogMessage: Decodable {
        public let level: String?
        public let feature: String
        public let timestamp: Double?
        public let args: [DebugLogArg]
    }

    public enum DebugLogArg: Decodable {
        case string(String)
        case errorInfo(ErrorInfo)

        public struct ErrorInfo: Decodable {
            let type: String
            let message: String
            let stack: String?
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let errorInfo = try? container.decode(ErrorInfo.self) {
                self = .errorInfo(errorInfo)
            } else {
                self = .string(try container.decode(String.self))
            }
        }

        public var description: String {
            switch self {
            case .string(let str): return str
            case .errorInfo(let err): return err.message + (err.stack.map { "\n\($0)" } ?? "")
            }
        }
    }

    public struct SignpostMessage: Decodable {
        public let event: String
        public let url: String?
        public let time: Double?
        public let name: String?
        public let reason: String?
    }

    // MARK: - Properties

    public var broker: UserScriptMessageBroker?

    public var featureName: String = "debug"

    public var messageOriginPolicy: MessageOriginPolicy = .all

    /// Optional delegate for signpost/instrumentation events
    /// Set this to a TabInstrumentation instance to enable os_signpost profiling
    public weak var instrumentation: DebugLogInstrumentation?

    // MARK: - Initialization

    public init(instrumentation: DebugLogInstrumentation? = nil) {
        self.instrumentation = instrumentation
    }

    // MARK: - Subfeature

    public func handler(forMethodNamed methodName: String) -> Handler? {
        switch methodName {
        case "debugLog":
            return handleDebugLog
        case "signpost":
            return handleSignpost
        default:
            return nil
        }
    }

    // MARK: - Handlers

    /// Handle debug log messages from C-S-S features
    /// Routes to os.log with appropriate level and category for filtering in Console.app
    private func handleDebugLog(params: Any, message: WKScriptMessage) async throws -> Encodable? {
        #if DEBUG
        guard let paramsDict = params as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: paramsDict),
              let logMessage = try? JSONDecoder().decode(DebugLogMessage.self, from: jsonData) else {
            Logger.general.debug("DebugLog: Failed to decode log message")
            return nil
        }

        let formattedArgs = logMessage.args.map { $0.description }.joined(separator: " ")

        // Use OSLog categories for per-feature filtering in Console.app
        // Filter example: `subsystem:com.duckduckgo.content-scope-scripts category:trackerStats`
        let logger = Logger(
            subsystem: "com.duckduckgo.content-scope-scripts",
            category: logMessage.feature
        )

        switch logMessage.level {
        case "error":
            logger.error("[\(logMessage.feature, privacy: .public)] \(formattedArgs, privacy: .public)")
        case "warn":
            logger.warning("[\(logMessage.feature, privacy: .public)] \(formattedArgs, privacy: .public)")
        case "debug":
            logger.debug("[\(logMessage.feature, privacy: .public)] \(formattedArgs, privacy: .public)")
        default:
            logger.info("[\(logMessage.feature, privacy: .public)] \(formattedArgs, privacy: .public)")
        }
        #endif

        return nil
    }

    /// Handle signpost events for performance profiling
    /// Can be used with Instruments for os_signpost integration
    private func handleSignpost(params: Any, message: WKScriptMessage) async throws -> Encodable? {
        guard let paramsDict = params as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: paramsDict),
              let signpost = try? JSONDecoder().decode(SignpostMessage.self, from: jsonData) else {
            return nil
        }

        // Forward to instrumentation delegate if available
        switch signpost.event {
        case "Request Allowed":
            if let url = signpost.url, let time = signpost.time {
                instrumentation?.request(url: url, allowedIn: time)
            }
        case "Tracker Allowed":
            if let url = signpost.url, let time = signpost.time {
                instrumentation?.tracker(url: url, allowedIn: time, reason: signpost.reason)
            }
        case "Tracker Blocked":
            if let url = signpost.url, let time = signpost.time {
                instrumentation?.tracker(url: url, blockedIn: time)
            }
        case "Surrogate Injected":
            if let url = signpost.url, let time = signpost.time {
                instrumentation?.jsEvent(name: "surrogate:\(url)", executedIn: time)
            }
        case "Generic":
            if let name = signpost.name, let time = signpost.time {
                instrumentation?.jsEvent(name: name, executedIn: time)
            }
        default:
            break
        }

        return nil
    }
}

// MARK: - Instrumentation Protocol

/// Protocol for tab instrumentation
/// Implementations exist in iOS/Core/TabInstrumentation.swift and macOS/Common/Utilities/TabInstrumentation.swift
/// This protocol allows the shared subfeature to work with both implementations
public protocol DebugLogInstrumentation: AnyObject {
    func request(url: String, allowedIn timeInMs: Double)
    func tracker(url: String, allowedIn timeInMs: Double, reason: String?)
    func tracker(url: String, blockedIn timeInMs: Double)
    func jsEvent(name: String, executedIn timeInMs: Double)
}
