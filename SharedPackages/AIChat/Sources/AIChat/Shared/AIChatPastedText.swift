//
//  AIChatPastedText.swift
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

/// A long plain-text paste kept as an attachment chip rather than inline prompt text. Lengths are
/// UTF-16 code units because that is what the duck.ai FE (`String.length`) measures.
public struct AIChatPastedText: Identifiable, Equatable, Sendable {

    /// A paste at least this long becomes a chip. Applies at paste time only, so editing below it keeps the chip.
    public static let conversionThreshold = 5_000

    /// The FE's per-model `inputCharLimit`; `/models` doesn't carry it yet, so it is hardcoded here.
    public static let maxInputCharacters = 16_000

    public static let maxTitleLength = 60

    public let id: UUID
    public let content: String

    public init(id: UUID = UUID(), content: String) {
        self.id = id
        self.content = content
    }

    public var length: Int { content.utf16.count }

    /// First non-empty line, trimmed, cut to `maxTitleLength` with an ellipsis.
    public var title: String {
        let firstLine = content
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard firstLine.count > Self.maxTitleLength else { return firstLine }
        return String(firstLine.prefix(Self.maxTitleLength)) + "…"
    }

    public static func shouldConvert(_ text: String) -> Bool {
        text.utf16.count >= conversionThreshold
    }

    /// What one chip may grow to while editing: everything else in the message counts against it,
    /// but a chip that is already over is never told its limit is below its own length.
    public static func editLimit(ownLength: Int, otherContentLength: Int, maxInputCharacters: Int = maxInputCharacters) -> Int {
        max(ownLength, maxInputCharacters - otherContentLength)
    }

    public var payload: AIChatNativePrompt.NativePromptPastedText {
        .init(content: content)
    }
}
