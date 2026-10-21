//
//  LocalAIMarkdown.swift
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

/// The block-level Markdown a model reply uses: enough to lay out summaries and translations.
/// Inline styling (bold, italics, code, links) is left in the text for `AttributedString` to handle.
public enum LocalAIMarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulletList([String])
    case numberedList([String])
    case code(String)
}

public enum LocalAIMarkdown {

    /// Parses `text`, which may be a reply still streaming in: an unclosed code fence runs to the end.
    public static func blocks(from text: String) -> [LocalAIMarkdownBlock] {
        var builder = BlockBuilder()
        text.components(separatedBy: "\n").forEach { builder.consume($0) }
        return builder.finish()
    }

    private struct BlockBuilder {
        private var blocks: [LocalAIMarkdownBlock] = []
        private var paragraph: [String] = []
        private var bullets: [String] = []
        private var numbered: [String] = []
        private var code: [String]?

        mutating func consume(_ rawLine: String) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                toggleCodeFence()
            } else if code != nil {
                code?.append(rawLine)
            } else if line.isEmpty {
                flush()
            } else if let heading = LocalAIMarkdown.heading(in: line) {
                flush()
                blocks.append(heading)
            } else if let item = LocalAIMarkdown.bulletItem(in: line) {
                if bullets.isEmpty { flush() }
                bullets.append(item)
            } else if let item = LocalAIMarkdown.numberedItem(in: line) {
                if numbered.isEmpty { flush() }
                numbered.append(item)
            } else if rawLine.hasPrefix("  "), continueListItem(with: line) {
                return
            } else {
                if !bullets.isEmpty || !numbered.isEmpty { flush() }
                paragraph.append(line)
            }
        }

        mutating func finish() -> [LocalAIMarkdownBlock] {
            if let open = code {
                blocks.append(.code(open.joined(separator: "\n")))
                code = nil
            }
            flush()
            return blocks
        }

        private mutating func toggleCodeFence() {
            if let open = code {
                blocks.append(.code(open.joined(separator: "\n")))
                code = nil
            } else {
                flush()
                code = []
            }
        }

        /// An indented line right after a list item continues that item.
        private mutating func continueListItem(with line: String) -> Bool {
            if !bullets.isEmpty {
                bullets[bullets.count - 1] += " " + line
            } else if !numbered.isEmpty {
                numbered[numbered.count - 1] += " " + line
            } else {
                return false
            }
            return true
        }

        private mutating func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            if !bullets.isEmpty { blocks.append(.bulletList(bullets)) }
            if !numbered.isEmpty { blocks.append(.numberedList(numbered)) }
            paragraph = []
            bullets = []
            numbered = []
        }
    }

    fileprivate static func heading(in line: String) -> LocalAIMarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return .heading(level: hashes, text: line.dropFirst(hashes + 1).trimmingCharacters(in: .whitespaces))
    }

    fileprivate static func bulletItem(in line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    fileprivate static func numberedItem(in line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2))
    }
}
