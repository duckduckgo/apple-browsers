//
//  AIChatPromptLimits.swift
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

public struct AIChatPromptLimits: Equatable, Sendable {
    public static let current = AIChatPromptLimits(maxCharacters: 16_000, pasteConversionThreshold: 4_000)

    public let maxCharacters: Int
    public let pasteConversionThreshold: Int

    public init(maxCharacters: Int, pasteConversionThreshold: Int) {
        self.maxCharacters = maxCharacters
        self.pasteConversionThreshold = pasteConversionThreshold
    }

    public static func isBlank(_ text: String) -> Bool {
        text.allSatisfy { $0.isWhitespace || $0.isNewline }
    }

    public func convertsToPastedText(_ insertedText: String) -> Bool {
        insertedText.utf16.count >= pasteConversionThreshold && !Self.isBlank(insertedText)
    }

    public func evaluate(prompt: String,
                         pastedTexts: [AIChatPastedText],
                         hasImage: Bool,
                         maxCharactersWithImage: Int?) -> AIChatPromptLength {
        let count = prompt.utf16.count + pastedTexts.reduce(0) { $0 + $1.length }
        let limit: Int
        if hasImage, let maxCharactersWithImage {
            limit = min(maxCharactersWithImage, maxCharacters)
        } else {
            limit = maxCharacters
        }
        return AIChatPromptLength(count: count, limit: limit)
    }
}

public struct AIChatPromptLength: Equatable, Sendable {
    public let count: Int
    public let limit: Int

    public init(count: Int, limit: Int) {
        self.count = count
        self.limit = limit
    }

    public var isOverLimit: Bool { count > limit }

    public func limit(forEditing paste: AIChatPastedText) -> Int {
        limit - (count - paste.length)
    }
}
