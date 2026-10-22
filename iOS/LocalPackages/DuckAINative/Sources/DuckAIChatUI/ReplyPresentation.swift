//
//  ReplyPresentation.swift
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

import DuckAIChatCore
import Foundation

struct AssistantReplySnapshot: Identifiable, Equatable {
    enum Phase: Equatable {
        case receiving(LoadingStage)
        case ended(ReplyEnding)
    }

    let id: MessageID
    let parts: [AssistantPart]
    let phase: Phase

    var isReceiving: Bool {
        if case .receiving = phase { return true }
        return false
    }
}

struct PresentedReply: Equatable {
    var parts: [AssistantPart] = []
    var documents: [Int: [PresentedMarkdownBlock]] = [:]
    var isRevealing = true
}

struct ReplyPresentation {
    private(set) var target: AssistantReplySnapshot
    private(set) var rendered = PresentedReply()
    private var documents: [Int: IncrementalMarkdown] = [:]
    private var credit = 0.0
    private static let maximumFrameInterval = 0.05
    private static let catchUpInterval = 0.35
    private static let minimumCharactersPerSecond = 80.0

    init(_ reply: AssistantReplySnapshot) {
        target = reply
        if !reply.isReceiving { flush() }
    }

    var needsFrame: Bool {
        rendered.parts != target.parts || rendered.isRevealing != target.isReceiving
    }

    mutating func receive(_ reply: AssistantReplySnapshot, settle: Bool = false) {
        if reply.id != target.id {
            self = ReplyPresentation(reply)
            return
        }
        target = reply
        switch reply.phase {
        case .ended(.stopped), .ended(.interrupted): flush()
        default:
            if settle { flush() }
        }
    }

    mutating func flush() {
        credit = 0
        publish(target.parts, isRevealing: target.isReceiving)
    }

    mutating func advance(by elapsed: TimeInterval) {
        guard needsFrame, elapsed > 0 else { return }
        let backlog = target.parts.enumerated().reduce(0) { count, entry in
            guard case .text(let text) = entry.element else { return count }
            return count + max(0, text.count - visibleText(at: entry.offset).count)
        }
        credit += min(elapsed, Self.maximumFrameInterval) * max(Self.minimumCharactersPerSecond, Double(backlog) / Self.catchUpInterval)
        var allowance = Int(credit)
        credit -= Double(allowance)
        var parts: [AssistantPart] = []
        for (index, part) in target.parts.enumerated() {
            guard case .text(let text) = part else {
                parts.append(part)
                continue
            }
            let previous = visibleText(at: index)
            let count = text.hasPrefix(previous) ? previous.count : 0
            let added = min(allowance, max(0, text.count - count))
            allowance -= added
            let visible = String(text.prefix(count + added))
            parts.append(.text(visible))
            if visible != text { break }
        }
        let revealing = target.isReceiving || parts != target.parts
        publish(parts, isRevealing: revealing)
        if parts == target.parts { credit = 0 }
    }

    private func visibleText(at index: Int) -> String {
        guard rendered.parts.indices.contains(index), case .text(let text) = rendered.parts[index] else { return "" }
        return text
    }

    private mutating func publish(_ parts: [AssistantPart], isRevealing: Bool) {
        var blocks: [Int: [PresentedMarkdownBlock]] = [:]
        for (index, part) in parts.enumerated() {
            guard case .text(let text) = part else { continue }
            var document = documents[index] ?? IncrementalMarkdown()
            document.update(text, isStreaming: isRevealing && index == parts.count - 1)
            documents[index] = document
            blocks[index] = document.blocks
        }
        rendered = PresentedReply(parts: parts, documents: blocks, isRevealing: isRevealing)
    }
}
