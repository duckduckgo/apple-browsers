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
        fatalError("not implemented")
    }
}
