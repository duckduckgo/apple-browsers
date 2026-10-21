//
//  Message.swift
//  DuckDuckGo
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

/// Minted by `ChatState` from a counter and never reused, so a late event from a stopped reply cannot land on a newer one.
/// A live reply's id becomes its message's id.
public struct MessageID: Hashable, Comparable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: MessageID, rhs: MessageID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A finished message. The reply being generated is `ChatState.liveReply`, never a `Message`.
public enum Message: Identifiable, Equatable, Sendable {
    case user(UserMessage)
    case assistant(AssistantMessage)

    public var id: MessageID {
        switch self {
        case .user(let message): message.id
        case .assistant(let message): message.id
        }
    }
}

public struct UserMessage: Identifiable, Equatable, Sendable {
    public let id: MessageID
    public let createdAt: Date
    /// Context parts first, then attachments, then text.
    public let parts: [UserPart]

    public init(id: MessageID, createdAt: Date, parts: [UserPart]) {
        self.id = id
        self.createdAt = createdAt
        self.parts = parts
    }
}

public struct AssistantMessage: Identifiable, Equatable, Sendable {
    public let id: MessageID
    public let createdAt: Date
    /// Never empty. An empty reply is dropped, not committed.
    public let parts: [AssistantPart]
    public let ending: ReplyEnding

    public init(id: MessageID, createdAt: Date, parts: [AssistantPart], ending: ReplyEnding) {
        self.id = id
        self.createdAt = createdAt
        self.parts = parts
        self.ending = ending
    }
}

public enum ReplyEnding: Equatable, Sendable {
    case completed(GenerationStats?)
    case stopped
    /// The provider failed after some output. The error itself is `ChatStatus.error`.
    case interrupted
}

public enum UserPart: Equatable, Sendable {
    case text(String)
    case context(ContextPart)
    case attachment(Attachment)
}

public enum ContextPart: Equatable, Sendable {
    case page(PageContext)
    case selection(Selection)
    case pastedText(String)
    case request(ChatRequest)
}

public struct Attachment: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case image(format: String)
        case file(name: String, mimeType: String)
    }

    public let id: String
    public let kind: Kind
    public let data: Data

    public init(id: String, kind: Kind, data: Data) {
        self.id = id
        self.kind = kind
        self.data = data
    }
}

public enum AssistantPart: Equatable, Sendable {
    /// Adjacent text deltas extend the trailing `.text`. Text after reasoning starts a new one.
    case text(String)
    case reasoning(Reasoning)
    case toolCall(ToolCall)
    case toolResult(ToolResult)
    case source(Source)
    case refusal(Refusal)
}

public struct Reasoning: Equatable, Sendable {
    public enum Timing: Equatable, Sendable {
        /// Only inside a live reply.
        case thinking(since: Date)
        case done(Duration)
    }

    public var text: String
    public var timing: Timing

    public init(text: String, timing: Timing) {
        self.text = text
        self.timing = timing
    }

    /// The frontend's pill shows at least one second, rounded up.
    public var displaySeconds: Int? {
        guard case .done(let duration) = timing else { return nil }
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return max(1, Int(seconds.rounded(.up)))
    }
}

public struct ToolCall: Equatable, Sendable {
    public let id: String
    public let name: String
    /// Raw JSON, as the frontend stores it.
    public let arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct ToolResult: Equatable, Sendable {
    public let callID: String
    public let result: String

    public init(callID: String, result: String) {
        self.callID = callID
        self.result = result
    }
}

public struct Source: Equatable, Sendable {
    public let url: URL
    public let title: String
    public let site: String?

    public init(url: URL, title: String, site: String?) {
        self.url = url
        self.title = title
        self.site = site
    }
}

public struct Refusal: Equatable, Sendable {
    public let detectedBy: String?

    public init(detectedBy: String?) {
        self.detectedBy = detectedBy
    }
}

public struct GenerationStats: Equatable, Sendable {
    public let promptTokens: Int?
    public let generatedTokens: Int
    public let loadTime: Duration?
    public let promptTime: Duration?
    public let generateTime: Duration?

    public init(promptTokens: Int?, generatedTokens: Int, loadTime: Duration?, promptTime: Duration?, generateTime: Duration?) {
        self.promptTokens = promptTokens
        self.generatedTokens = generatedTokens
        self.loadTime = loadTime
        self.promptTime = promptTime
        self.generateTime = generateTime
    }
}
