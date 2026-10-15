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

    /// The backend rejects any single pasted text longer than this, whatever else the message holds.
    public static let maxPastedTextCharacters = 16_000

    public let id: UUID
    public let content: String

    public init(id: UUID = UUID(), content: String) {
        self.id = id
        self.content = content
    }

    public var length: Int { content.utf16.count }

    /// First non-blank line, trimmed. The chip label truncates it to fit.
    public var title: String {
        content
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }

    /// Typed text never converts; only a single insertion this long does. Blank text stays inline.
    public static func shouldConvert(_ text: String) -> Bool {
        text.utf16.count >= conversionThreshold && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What one chip may grow to while editing: everything else in the message counts against it,
    /// but a chip that is already over is never told its limit is below its own length.
    public static func editLimit(ownLength: Int, otherContentLength: Int, maxInputCharacters: Int = maxInputCharacters) -> Int {
        min(maxPastedTextCharacters, max(ownLength, maxInputCharacters - otherContentLength))
    }

    public var payload: AIChatNativePrompt.NativePromptPastedText {
        .init(content: content)
    }
}

/// A message carrying pasted text that is over its text limit. One reason covers every case (a long
/// prompt, a single paste over the backend cap, pasted text with an image), as on the FE.
/// Only evaluated when pasted text is present, so typed-only prompts keep today's behaviour.
public struct AIChatPastedTextLimitViolation: Equatable, Sendable {
    /// UTF-16 units of the typed prompt plus every pasted text.
    public let count: Int
    public let limit: Int

    public init(count: Int, limit: Int) {
        self.count = count
        self.limit = limit
    }
}

/// The text-length facts of a draft message, in UTF-16 units.
public struct AIChatPastedTextMessage: Equatable, Sendable {
    public let promptLength: Int
    public let pastedTextLengths: [Int]
    public let hasImage: Bool
    public let maxInputCharsWithImages: Int?

    public init(prompt: String,
                pastedTextLengths: [Int],
                hasImage: Bool = false,
                maxInputCharsWithImages: Int? = nil) {
        self.promptLength = prompt.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
        self.pastedTextLengths = pastedTextLengths
        self.hasImage = hasImage
        self.maxInputCharsWithImages = maxInputCharsWithImages
    }

    public var totalLength: Int { promptLength + pastedTextLengths.reduce(0, +) }

    /// The FE lowers the limit only when an image is attached; a file keeps the input limit.
    public var effectiveLimit: Int {
        if hasImage, let maxInputCharsWithImages {
            return min(maxInputCharsWithImages, AIChatPastedText.maxInputCharacters)
        }
        return AIChatPastedText.maxInputCharacters
    }

    /// A single paste over the backend's 16,000 cap always puts the total over the limit too, so the total covers it.
    public var violation: AIChatPastedTextLimitViolation? {
        guard !pastedTextLengths.isEmpty, totalLength > effectiveLimit else { return nil }
        return AIChatPastedTextLimitViolation(count: totalLength, limit: effectiveLimit)
    }
}
