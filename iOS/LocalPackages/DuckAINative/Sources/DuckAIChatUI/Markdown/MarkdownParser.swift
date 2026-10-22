//
//  MarkdownParser.swift
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

/// The block structure of a reply, matching the Markdown the Duck.ai frontend renders with Streamdown.
/// Inline text stays as Markdown source; views style it with `AttributedString(markdown:)`.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list(ordered: Bool, start: Int, items: [String])
    case codeBlock(language: String?, code: String)
    case blockquote([MarkdownBlock])
    case table(header: [String], rows: [[String]])
    case thematicBreak
}

public enum MarkdownParser {

    /// Splits Markdown into blocks.
    ///
    /// - Paragraphs end at a blank line or where another block starts. Lines inside one paragraph join with "\n".
    /// - Headings are `#` to `######` followed by a space.
    /// - Lists: `-`, `*` or `+` items are unordered; `N.` items are ordered and `start` is the first number. Item text
    ///   continues on indented lines. Nested lists are flattened into the item's text.
    /// - Fenced code uses three or more backticks; the info string's first word is the language. Indented code is not
    ///   a block (as in the frontend).
    /// - Blockquote lines start with `>`; their content is parsed as blocks.
    /// - Tables need a header row and a `---` delimiter row; cells are trimmed.
    /// - `---`, `***` or `___` alone on a line is a thematic break.
    /// - When `isStreaming` is true the text may stop mid-block, as Streamdown's incomplete-Markdown repair assumes:
    ///   an unclosed fence is a code block holding what has arrived; in the last block, unmatched trailing `**`, `*`,
    ///   `__`, `_`, `~~` and backticks are closed, and a trailing unfinished link `[text](url` shows as its text.
    public static func blocks(from markdown: String, isStreaming: Bool = false) -> [MarkdownBlock] {
        scan(normalize(markdown), isStreaming: isStreaming).map(\.block)
    }

    struct ParsedBlock {
        let start: Int
        let end: Int
        let block: MarkdownBlock
        let isStable: Bool
    }

    static func normalize(_ source: String) -> String {
        source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    private static let boundaryLookaheadLines = 2

    static func scan(_ source: String, isStreaming: Bool) -> [ParsedBlock] {
        let lines = source.components(separatedBy: "\n")
        var offsets = [0]
        for line in lines { offsets.append(offsets.last! + line.utf8.count + 1) }
        var result: [ParsedBlock] = []
        var index = 0
        while index < lines.count {
            let start = index
            let line = lines[index]
            let block: MarkdownBlock
            if trimmed(line).isEmpty {
                index += 1
                continue
            } else if let fence = fenceOpening(line) {
                block = parseCode(lines, index: &index, fence: fence)
            } else if let heading = heading(line) {
                block = .heading(level: heading.level, text: heading.text)
                index += 1
            } else if isThematicBreak(line) {
                block = .thematicBreak
                index += 1
            } else if quoteContent(line) != nil {
                block = parseQuote(lines, index: &index)
            } else if isTableStart(lines, at: index) {
                block = parseTable(lines, index: &index)
            } else if let first = listItem(line) {
                block = parseList(lines, index: &index, first: first)
            } else {
                block = parseParagraph(lines, index: &index)
            }
            let stable = !isStreaming || index + boundaryLookaheadLines < lines.count
            result.append(ParsedBlock(start: offsets[start], end: min(offsets[index], source.utf8.count),
                                      block: block, isStable: stable))
        }
        if isStreaming, let last = result.popLast() {
            result.append(ParsedBlock(start: last.start, end: last.end, block: repair(last.block), isStable: false))
        }
        return result
    }

    private static func parseCode(_ lines: [String], index: inout Int, fence: (length: Int, language: String?)) -> MarkdownBlock {
        index += 1
        var code: [String] = []
        while index < lines.count && !isFenceClosing(lines[index], length: fence.length) {
            code.append(lines[index])
            index += 1
        }
        if index < lines.count { index += 1 }
        return .codeBlock(language: fence.language, code: code.joined(separator: "\n"))
    }

    private static func parseQuote(_ lines: [String], index: inout Int) -> MarkdownBlock {
        var quoted: [String] = []
        while index < lines.count, let content = quoteContent(lines[index]) {
            quoted.append(content)
            index += 1
        }
        return .blockquote(blocks(from: quoted.joined(separator: "\n")))
    }

    private static func parseTable(_ lines: [String], index: inout Int) -> MarkdownBlock {
        let header = tableCells(lines[index])
        index += 2
        var rows: [[String]] = []
        while index < lines.count && !trimmed(lines[index]).isEmpty && lines[index].contains("|") {
            rows.append(tableCells(lines[index]))
            index += 1
        }
        return .table(header: header, rows: rows)
    }

    private static func parseParagraph(_ lines: [String], index: inout Int) -> MarkdownBlock {
        var paragraph = [lines[index]]
        index += 1
        while index < lines.count && !trimmed(lines[index]).isEmpty && !startsBlock(lines, at: index) {
            paragraph.append(lines[index])
            index += 1
        }
        return .paragraph(paragraph.joined(separator: "\n"))
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let text = trimmed(line)
        let hashes = text.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), text.dropFirst(hashes).first == " " else { return nil }
        return (hashes, trimmed(String(text.dropFirst(hashes + 1))))
    }

    private static func fenceOpening(_ line: String) -> (length: Int, language: String?)? {
        let text = trimmed(line)
        let length = text.prefix { $0 == "`" }.count
        guard length >= 3 else { return nil }
        let info = text.dropFirst(length)
        guard !info.contains("`") else { return nil }
        return (length, info.split(whereSeparator: { $0.isWhitespace }).first.map(String.init))
    }

    private static func isFenceClosing(_ line: String, length: Int) -> Bool {
        let text = trimmed(line)
        let count = text.prefix { $0 == "`" }.count
        return count >= length && trimmed(String(text.dropFirst(count))).isEmpty
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        ["---", "***", "___"].contains(trimmed(line))
    }

    private static func quoteContent(_ line: String) -> String? {
        let text = line.drop(while: { $0.isWhitespace })
        guard text.first == ">" else { return nil }
        let content = text.dropFirst()
        return String(content.first == " " ? content.dropFirst() : content)
    }

    private struct ListItem {
        let ordered: Bool
        let number: Int
        let indentation: Int
        let text: String
    }

    private static func listItem(_ line: String) -> ListItem? {
        let content = line.drop(while: { $0.isWhitespace })
        let indentation = line.count - content.count
        if let marker = content.first, "-*+".contains(marker), content.dropFirst().first?.isWhitespace == true {
            return ListItem(ordered: false, number: 1, indentation: indentation, text: trimmed(String(content.dropFirst())))
        }
        let digits = content.prefix { $0.isASCII && $0.isNumber }
        let suffix = content.dropFirst(digits.count)
        guard let number = Int(digits), suffix.first == ".", suffix.dropFirst().first?.isWhitespace == true else { return nil }
        return ListItem(ordered: true, number: number, indentation: indentation, text: trimmed(String(suffix.dropFirst())))
    }

    private static func parseList(_ lines: [String], index: inout Int, first: ListItem) -> MarkdownBlock {
        var items = [first.text]
        index += 1
        while index < lines.count && !trimmed(lines[index]).isEmpty {
            let line = lines[index]
            let indentation = line.prefix { $0.isWhitespace }.count
            if indentation > first.indentation {
                items[items.count - 1] += "\n" + trimmed(line)
            } else if let item = listItem(line), item.ordered == first.ordered, item.indentation == first.indentation,
                      !isThematicBreak(line) {
                items.append(item.text)
            } else {
                break
            }
            index += 1
        }
        return .list(ordered: first.ordered, start: first.number, items: items)
    }

    private static func tableCells(_ line: String) -> [String] {
        var text = trimmed(line)
        if text.first == "|" { text.removeFirst() }
        if text.last == "|" { text.removeLast() }
        return text.components(separatedBy: "|").map(trimmed)
    }

    private static func isTableStart(_ lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count, lines[index].contains("|") else { return false }
        let cells = tableCells(lines[index + 1])
        return cells.count == tableCells(lines[index]).count && cells.allSatisfy { cell in
            var delimiter = cell[...]
            if delimiter.first == ":" { delimiter = delimiter.dropFirst() }
            if delimiter.last == ":" { delimiter = delimiter.dropLast() }
            return delimiter.count >= 3 && delimiter.allSatisfy { $0 == "-" }
        }
    }

    private static func startsBlock(_ lines: [String], at index: Int) -> Bool {
        let line = lines[index]
        return heading(line) != nil || fenceOpening(line) != nil || isThematicBreak(line)
            || quoteContent(line) != nil || listItem(line) != nil || isTableStart(lines, at: index)
    }

    private static func repair(_ block: MarkdownBlock) -> MarkdownBlock {
        switch block {
        case .paragraph(let text):
            return .paragraph(repairInline(text))
        case .heading(let level, let text):
            return .heading(level: level, text: repairInline(text))
        case .list(let ordered, let start, var items):
            if let last = items.popLast() { items.append(repairInline(last)) }
            return .list(ordered: ordered, start: start, items: items)
        case .blockquote(var blocks):
            if let last = blocks.popLast() { blocks.append(repair(last)) }
            return .blockquote(blocks)
        case .table(var header, var rows):
            if var row = rows.popLast() {
                if let cell = row.popLast() { row.append(repairInline(cell)) }
                rows.append(row)
            } else if let cell = header.popLast() {
                header.append(repairInline(cell))
            }
            return .table(header: header, rows: rows)
        case .codeBlock, .thematicBreak:
            return block
        }
    }

    private static func repairInline(_ text: String) -> String {
        var result = ""
        var open: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "\\", next < text.endIndex {
                let end = text.index(after: next)
                result += text[index..<end]
                index = end
                continue
            }
            if open.last?.first != "`", character == "[",
               let labelEnd = text[next...].firstIndex(of: "]") {
                let afterLabel = text.index(after: labelEnd)
                if afterLabel == text.endIndex || (text[afterLabel] == "(" && !text[afterLabel...].contains(")")) {
                    result += text[next..<labelEnd]
                    break
                }
            }
            if character == "[", open.last?.first != "`", !text[next...].contains("]") {
                result += text[next...]
                break
            }
            if "*_~`".contains(character) {
                let run = text[index...].prefix { $0 == character }
                let token = String(run)
                let previous = open
                updateDelimiters(token, open: &open)
                if text.index(index, offsetBy: run.count) == text.endIndex, open.count > previous.count {
                    open = previous
                    break
                }
                result += token
                index = text.index(index, offsetBy: run.count)
            } else {
                result.append(character)
                index = next
            }
        }
        return result + open.reversed().joined()
    }

    private static func updateDelimiters(_ token: String, open: inout [String]) {
        if let code = open.last, code.first == "`" {
            if token == code { open.removeLast() }
            return
        }
        if token.first == "`" || token == "~~" {
            if open.last == token {
                open.removeLast()
            } else {
                open.append(token)
            }
            return
        }
        guard let marker = token.first, marker == "*" || marker == "_" else { return }
        var remaining = token.count
        while let last = open.last, last.first == marker, last.count <= remaining {
            remaining -= last.count
            open.removeLast()
        }
        while remaining > 0 {
            let count = min(2, remaining)
            open.append(String(repeating: marker, count: count))
            remaining -= count
        }
    }

}
