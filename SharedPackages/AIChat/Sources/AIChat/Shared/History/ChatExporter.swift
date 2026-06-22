//
//  ChatExporter.swift
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

/// Formats a Duck.ai chat (FE-owned JSON blob) into the cross-platform plain-text shape.
/// Pure — no I/O, no DI. Inject a `TimeZone` to keep tests deterministic across machine
/// timezones.
public struct ChatExporter {

    private let timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    /// Convert a chat's raw JSON into an `ExportResult`. Throws when the JSON can't be parsed.
    /// - Parameters:
    ///   - rawJson: The raw JSON data exactly as stored in the native data store.
    ///   - chatType: Determines the export shape (text for discussion/voice, zip for image).
    ///   - fileRefs: UUIDs of files referenced by image-generation chats, in turn order.
    ///   - modelDisplay: Resolved model display metadata. When `nil`, the model id is used
    ///     verbatim and no provider attribution is included.
    public func export(
        rawJson: Data,
        chatType: ChatType = .discussion,
        fileRefs: [String] = [],
        modelDisplay: ModelDisplay? = nil
    ) throws -> ExportResult {
        guard let json = try JSONSerialization.jsonObject(with: rawJson) as? [String: Any] else {
            throw ExportError.invalidJSON
        }

        let display = modelDisplay ?? Self.rawIdFallback(modelId: json["model"] as? String ?? "")
        let turns = Self.extractTurns(messages: json["messages"] as? [[String: Any]] ?? [])

        switch chatType {
        case .discussion:
            return .text(renderDiscussion(display: display, turns: turns))
        case .voice:
            return .text(renderVoice(display: display, turns: turns))
        case .imageGeneration:
            return renderImage(display: display, turns: turns, fileRefs: fileRefs)
        }
    }

    // MARK: - Renderers

    private func renderDiscussion(display: ModelDisplay, turns: [Turn]) -> String {
        buildContent(display: display, turns: turns) { _, turn in
            "\(display.shortName):\n\(turn.assistantText)"
        }
    }

    private func renderVoice(display: ModelDisplay, turns: [Turn]) -> String {
        buildContent(display: display, turns: turns) { _, turn in
            turn.assistantText.isBlankOrEmpty ? "" : "Voice Chat:\n\(turn.assistantText)"
        }
    }

    private func renderImage(display: ModelDisplay, turns: [Turn], fileRefs: [String]) -> ExportResult {
        var consumed: [String] = []
        let text = buildContent(display: display, turns: turns) { index, _ in
            if index < fileRefs.count {
                consumed.append(fileRefs[index])
                return "\(display.shortName):\n\n[Generated image: image-\(consumed.count).jpeg]"
            } else {
                return "\(display.shortName):"
            }
        }
        return .zip(content: text, imageFileRefs: consumed)
    }

    private func buildContent(
        display: ModelDisplay,
        turns: [Turn],
        assistantBlock: (Int, Turn) -> String
    ) -> String {
        var out = ""
        out.append(header(display: display))
        out.append("\n")
        out.append("\n")
        out.append(Constants.separator)
        for (index, turn) in turns.enumerated() {
            if index > 0 {
                // Two newlines terminate the previous turn's assistant text and emit a
                // blank line, then the separator line + its terminator.
                out.append("\n")
                out.append("\n")
                out.append(Constants.turnSeparator)
                out.append("\n")
            } else {
                // Single newline terminates the section separator line above.
                out.append("\n")
            }
            // Blank line before the user prompt header, then the header itself.
            out.append("\n")
            out.append("User prompt \(index + 1) of \(turns.count) - \(formatTimestamp(turn.createdAt)):")
            out.append("\n")
            out.append(turn.userText)
            let assistant = assistantBlock(index, turn)
            if !assistant.isEmpty {
                out.append("\n")
                out.append("\n")
                out.append(assistant)
            }
        }
        return out
    }

    // MARK: - Turn extraction

    private static func extractTurns(messages: [[String: Any]]) -> [Turn] {
        guard !messages.isEmpty else { return [] }
        var turns: [Turn] = []
        var index = 0
        while index < messages.count {
            let message = messages[index]
            if (message["role"] as? String) == "user" {
                let createdAt = message["createdAt"] as? String ?? ""
                let userText = (message["content"] as? String) ?? ""
                let nextIsAssistant = index + 1 < messages.count
                    && (messages[index + 1]["role"] as? String) == "assistant"
                let assistantText = nextIsAssistant ? extractAssistantText(message: messages[index + 1]) : ""
                turns.append(Turn(createdAt: createdAt, userText: userText, assistantText: assistantText))
                index += nextIsAssistant ? 2 : 1
            } else {
                index += 1
            }
        }
        return turns
    }

    private static func extractAssistantText(message: [String: Any]) -> String {
        if let parts = message["parts"] as? [[String: Any]], !parts.isEmpty {
            let textParts = parts.compactMap { part -> String? in
                guard (part["type"] as? String) == "text" else { return nil }
                return part["text"] as? String
            }
            if !textParts.isEmpty {
                return textParts.joined()
            }
        }
        return (message["content"] as? String) ?? ""
    }

    // MARK: - Helpers

    private func formatTimestamp(_ iso: String) -> String {
        // FE supplies ISO-8601 with millisecond precision (e.g. "2026-04-01T21:31:54.260Z").
        // The export format wants `M/d/yyyy, h:mm:ss a` in the local zone; on parse failure
        // we fall back to the raw string so the export still includes the FE-stored value.
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: iso) else {
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            guard let date = fallback.date(from: iso) else { return iso }
            return Self.outputFormatter(timeZone: timeZone).string(from: date)
        }
        return Self.outputFormatter(timeZone: timeZone).string(from: date)
    }

    private static func outputFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "M/d/yyyy, h:mm:ss a"
        return formatter
    }

    /// Used when the caller didn't supply a resolved `ModelDisplay` — renders the raw model id with no provider.
    private static func rawIdFallback(modelId: String) -> ModelDisplay {
        let trimmed = modelId.trimmingCharacters(in: .whitespaces)
        let nonEmpty = trimmed.isEmpty ? nil : trimmed
        return ModelDisplay(
            fullName: nonEmpty,
            shortName: nonEmpty ?? "AI",
            providerPossessive: nil
        )
    }

    private func header(display: ModelDisplay) -> String {
        let using: String
        if let provider = display.providerPossessive, let full = display.fullName {
            using = "using \(provider) \(full) Model"
        } else if let full = display.fullName {
            using = "using the \(full) Model"
        } else {
            using = "using an AI Model"
        }
        return "This conversation was generated with Duck.ai (https://duck.ai) \(using). "
            + "AI chats may display inaccurate or offensive information "
            + "(see https://duckduckgo.com/duckai/privacy-terms for more info)."
    }

    // MARK: - Types

    public enum ExportResult: Equatable {
        case text(String)
        case zip(content: String, imageFileRefs: [String])

        public var content: String {
            switch self {
            case .text(let content): return content
            case .zip(let content, _): return content
            }
        }
    }

    public enum ExportError: Error, Equatable {
        case invalidJSON
    }

    private struct Turn {
        let createdAt: String
        let userText: String
        let assistantText: String
    }

    private enum Constants {
        static let separator = "===================="
        static let turnSeparator = "--------------------"
    }
}

private extension String {
    /// True for empty AND whitespace-only strings.
    var isBlankOrEmpty: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
