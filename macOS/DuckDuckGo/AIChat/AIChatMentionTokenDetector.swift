//
//  AIChatMentionTokenDetector.swift
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

/// A detected `@`-mention token in the omnibar input.
///
/// `range` is the **NSRange** of the full `@token` substring within the input (including
/// the leading `@`). `query` is the substring **after** the `@` and up to the caret — used
/// as the live filter for the mention picker.
struct AIChatMentionToken: Equatable {
    let range: NSRange
    let query: String
}

/// Pure function that decides whether the omnibar's caret is currently inside an
/// `@`-mention token. The detector is the single source of truth for the trigger rule, so
/// the rendering layer (the mention picker panel) and the unit tests share one definition.
///
/// Rules:
///
/// - The `@` must be at the **start of the input** or immediately preceded by **whitespace**.
///   That way, `foo@bar.com` does not trigger, but `summarize @goog` does.
/// - Once an `@` is the active trigger, the token extends from the `@` up to the caret,
///   **including spaces**. So `@apple plus` is a single multi-word filter query "apple plus".
///   The token only terminates at a hard line break (newline / paragraph separator) or
///   when the user dismisses the picker (Esc, click outside, etc.).
/// - The caret may be anywhere from immediately-after-the-`@` to the end of the token. The
///   `query` is the substring from the `@` (exclusive) to the caret position.
/// - When multiple valid `@`s share a line, the **closest one to the caret going backwards**
///   wins. `@foo @bar|` filters on "bar", not "foo @bar".
/// - Tokens at start-of-input or just after a newline are still valid — `\n@goo` triggers.
enum AIChatMentionTokenDetector {
    /// Returns the mention token under the caret, or `nil` if the caret is not in one.
    ///
    /// - Parameters:
    ///   - text: The full input string.
    ///   - caret: The caret position as an `NSString`-style UTF-16 offset.
    static func token(in text: String, caret: Int) -> AIChatMentionToken? {
        let nsString = text as NSString
        let length = nsString.length
        guard caret >= 0, caret <= length else { return nil }

        // Walk backwards to the nearest line boundary (newline / paragraph separator) or
        // the start of input. Spaces do NOT terminate the search — they're allowed inside
        // the token so users can search for multi-word phrases.
        var lineStart = caret
        while lineStart > 0 {
            let previous = nsString.character(at: lineStart - 1)
            if Self.isLineBoundary(previous) { break }
            lineStart -= 1
        }

        // Within that line range, scan backwards from the caret looking for an `@` whose
        // preceding character is start-of-input OR whitespace. Whichever we find first is
        // the active token's trigger. Worst-case O(line length) — bounded by `lineStart`
        // above; fine for prompt-sized input.
        var index = caret - 1
        while index >= lineStart {
            if nsString.character(at: index) == Self.atSign {
                let isAtLineStart = (index == 0)
                let isPrecededByWhitespace = index > 0 && Self.isWhitespace(nsString.character(at: index - 1))
                if isAtLineStart || isPrecededByWhitespace {
                    let queryRange = NSRange(location: index + 1, length: caret - index - 1)
                    let query = queryRange.length > 0 ? nsString.substring(with: queryRange) : ""
                    return AIChatMentionToken(
                        range: NSRange(location: index, length: caret - index),
                        query: query
                    )
                }
            }
            index -= 1
        }
        return nil
    }

    /// `@` (U+0040). Hoisted to a constant so the hot path doesn't construct a `Character`.
    private static let atSign: unichar = 0x40

    /// Hard line breaks that terminate a mention token. Spaces and tabs are intentionally
    /// excluded — they're allowed inside a multi-word query.
    private static func isLineBoundary(_ ch: unichar) -> Bool {
        switch ch {
        case 0x0A, // line feed
             0x0D, // carriage return
             0x2028, // line separator
             0x2029: // paragraph separator
            return true
        default:
            return false
        }
    }

    /// Whitespace characters that are valid as the character *immediately preceding* an
    /// `@`. (Inside a token, whitespace is allowed but doesn't terminate it.)
    private static func isWhitespace(_ ch: unichar) -> Bool {
        switch ch {
        case 0x20,   // space
             0x09,   // tab
             0x0A,   // line feed
             0x0D,   // carriage return
             0xA0,   // non-breaking space
             0x2028, // line separator
             0x2029: // paragraph separator
            return true
        default:
            return false
        }
    }
}
