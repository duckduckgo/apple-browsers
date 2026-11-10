//
//  AIChatLocalModelEngine.swift
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

import DDGError
import Foundation

public enum AIChatLocalModelAvailability: Equatable, Sendable {
    case available
    case appleIntelligenceNotEnabled
    case modelNotReady
    case deviceNotEligible
    case unsupportedOS

    public var isAvailable: Bool { self == .available }

    /// False when nothing the user can turn on makes the model available, such as on a device
    /// without Apple Intelligence or an older OS, so there's no point offering it.
    public var isSupportedOnDevice: Bool {
        switch self {
        case .available, .appleIntelligenceNotEnabled, .modelNotReady:
            return true
        case .deviceNotEligible, .unsupportedOS:
            return false
        }
    }
}

public struct AIChatLocalModelRunSummary: Equatable, Sendable {
    public let promptTokens: Int?
    public let outputTokens: Int?
    public let inputTruncated: Bool

    public init(promptTokens: Int?, outputTokens: Int?, inputTruncated: Bool) {
        self.promptTokens = promptTokens
        self.outputTokens = outputTokens
        self.inputTruncated = inputTruncated
    }
}

public enum AIChatLocalModelEngineEvent: Equatable, Sendable {
    /// Text added since the previous event.
    case text(String)
    case finished(AIChatLocalModelRunSummary)
}

public struct AIChatLocalModelEngineError: DDGError, Sendable {
    public let code: AIChatLocalRunChunk.ErrorCode

    public init(code: AIChatLocalRunChunk.ErrorCode) {
        self.code = code
    }

    public static let errorDomain = "com.duckduckgo.aiChat.localModel.engine"

    public var errorCode: Int {
        switch code {
        case .unavailable: return 1
        case .contentFiltered: return 2
        case .contextExceeded: return 3
        case .unsupportedLanguage: return 4
        case .rateLimited: return 5
        case .outOfMemory: return 6
        case .interrupted: return 7
        case .internal: return 8
        }
    }

    public var underlyingError: Error? { nil }
    public var description: String { "AIChatLocalModelEngineError(\(code.rawValue))" }
}

/// A model that runs Duck.ai tasks on the device. The stream ends after `.finished`, or throws an
/// `AIChatLocalModelEngineError`. Cancelling the consuming task stops the run.
public protocol AIChatLocalModelEngine: AnyObject {
    var model: AIChatLocalModelInfo { get }
    var availability: AIChatLocalModelAvailability { get }
    func run(_ request: AIChatLocalRunRequest) -> AsyncThrowingStream<AIChatLocalModelEngineEvent, Error>
}
