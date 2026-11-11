//
//  AIChatLocalModelProtocol.swift
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

/// Payloads of the local-model messages between Duck.ai and the browser, as defined in
/// "Tech Design: Local model messaging (duck.ai and the browser)".
public enum AIChatLocalModelState: String, Codable, Equatable, Sendable {
    case unsupported
    case notSetUp = "not_set_up"
    case downloading
    case ready
}

public enum AIChatLocalModelTask: String, Codable, Equatable, Sendable, CaseIterable {
    case summarize
    case title
}

public struct AIChatLocalModelInfo: Codable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// The `localModel` field of `getAIChatNativeConfigValues`.
public struct AIChatLocalModelConfig: Codable, Equatable, Sendable {
    public let state: AIChatLocalModelState
    public let tasks: [AIChatLocalModelTask]
    public let model: AIChatLocalModelInfo
    public let downloadBytes: Int64

    public init(state: AIChatLocalModelState, tasks: [AIChatLocalModelTask], model: AIChatLocalModelInfo, downloadBytes: Int64) {
        self.state = state
        self.tasks = tasks
        self.model = model
        self.downloadBytes = downloadBytes
    }
}

/// Params of the `submitAIChatLocalModelState` push.
public struct AIChatLocalModelStateUpdate: Codable, Equatable, Sendable {
    public let state: AIChatLocalModelState

    public init(state: AIChatLocalModelState) {
        self.state = state
    }
}

/// Params of `startAIChatLocalRun`.
public struct AIChatLocalRunRequest: Codable, Equatable, Sendable {
    public let requestId: String
    public let task: AIChatLocalModelTask
    public let instruction: String
    public let content: String

    public init(requestId: String, task: AIChatLocalModelTask, instruction: String, content: String) {
        self.requestId = requestId
        self.task = task
        self.instruction = instruction
        self.content = content
    }
}

/// Reply to `startAIChatLocalRun`, sent before the first chunk.
public struct AIChatLocalRunStartReply: Codable, Equatable, Sendable {
    public let model: AIChatLocalModelInfo

    public init(model: AIChatLocalModelInfo) {
        self.model = model
    }
}

/// Params of `cancelAIChatLocalRun`.
public struct AIChatLocalRunCancelRequest: Codable, Equatable, Sendable {
    public let requestId: String

    public init(requestId: String) {
        self.requestId = requestId
    }
}

/// The error message `startAIChatLocalRun` and `startAIChatLocalModelSetup` reject with.
/// The message broker sends `errorDescription` to the page as `error.message`.
public enum AIChatLocalModelRequestError: String, DDGError, LocalizedError, Sendable {
    case unavailable
    case invalidArguments = "invalid_arguments"

    public static let errorDomain = "com.duckduckgo.aiChat.localModel.request"

    public var errorCode: Int {
        switch self {
        case .unavailable: return 1
        case .invalidArguments: return 2
        }
    }

    public var underlyingError: Error? { nil }
    public var description: String { rawValue }
    public var errorDescription: String? { rawValue }
}

/// Params of `submitAIChatLocalRunChunk`. Optional fields are left out of the JSON when nil.
public struct AIChatLocalRunChunk: Codable, Equatable, Sendable {

    public enum Status: String, Codable, Equatable, Sendable {
        case ok
        case cutOff = "cut_off"
        case cancelled
        case error
    }

    public enum ErrorCode: String, Codable, Equatable, Sendable, CaseIterable {
        case modelUnavailable = "model_unavailable"
        case refused
        case contextExceeded = "context_exceeded"
        case unsupportedLanguage = "unsupported_language"
        case rateLimited = "rate_limited"
        case outOfMemory = "out_of_memory"
        case unknown
    }

    public struct Metrics: Codable, Equatable, Sendable {
        public let timeToFirstWordMs: Int?
        public let totalMs: Int
        public let loadMs: Int?
        public let promptTokens: Int?
        public let outputTokens: Int?
        public let inputTruncated: Bool

        public init(timeToFirstWordMs: Int?, totalMs: Int, loadMs: Int?, promptTokens: Int?, outputTokens: Int?, inputTruncated: Bool) {
            self.timeToFirstWordMs = timeToFirstWordMs
            self.totalMs = totalMs
            self.loadMs = loadMs
            self.promptTokens = promptTokens
            self.outputTokens = outputTokens
            self.inputTruncated = inputTruncated
        }
    }

    public let requestId: String
    public let seq: Int
    public let text: String
    public let done: Bool?
    public let status: Status?
    public let errorCode: ErrorCode?
    public let metrics: Metrics?

    public init(requestId: String,
                seq: Int,
                text: String,
                done: Bool? = nil,
                status: Status? = nil,
                errorCode: ErrorCode? = nil,
                metrics: Metrics? = nil) {
        self.requestId = requestId
        self.seq = seq
        self.text = text
        self.done = done
        self.status = status
        self.errorCode = errorCode
        self.metrics = metrics
    }
}
