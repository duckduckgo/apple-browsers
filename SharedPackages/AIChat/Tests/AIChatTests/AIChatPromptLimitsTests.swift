//
//  AIChatPromptLimitsTests.swift
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
import Testing
@testable import AIChat

struct AIChatPromptLimitsTests {

    private let limits = AIChatPromptLimits.current

    private func text(_ count: Int, _ unit: Character = "a") -> String {
        String(repeating: unit, count: count)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func pasteConvertsAtTheThresholdAndNotBelow() {
        #expect(limits.convertsToPastedText(text(3_999)) == false)
        #expect(limits.convertsToPastedText(text(4_000)) == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [String(repeating: " ", count: 5_000), String(repeating: "\n", count: 5_000), ""])
    func blankPasteNeverConverts(_ blank: String) {
        #expect(limits.convertsToPastedText(blank) == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func pasteThresholdCountsUTF16Units() {
        let emoji = String(repeating: "😀", count: 2_000)
        #expect(emoji.count == 2_000)
        #expect(limits.convertsToPastedText(emoji) == true, "2,000 emoji are 4,000 UTF-16 units and must convert")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func typedOnlyPromptIsOverAt16001AndNotAt16000() {
        let atLimit = limits.evaluate(prompt: text(16_000), pastedTexts: [], hasImage: false, maxCharactersWithImage: nil)
        let over = limits.evaluate(prompt: text(16_001), pastedTexts: [], hasImage: false, maxCharactersWithImage: nil)
        #expect(atLimit == AIChatPromptLength(count: 16_000, limit: 16_000))
        #expect(atLimit.isOverLimit == false)
        #expect(over.count == 16_001)
        #expect(over.isOverLimit == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func countSumsPromptAndEveryPaste() {
        let pastes = [AIChatPastedText(content: text(6_000)), AIChatPastedText(content: text(6_000))]
        let atLimit = limits.evaluate(prompt: text(4_000), pastedTexts: pastes, hasImage: false, maxCharactersWithImage: nil)
        let over = limits.evaluate(prompt: text(4_001), pastedTexts: pastes, hasImage: false, maxCharactersWithImage: nil)
        #expect(atLimit.count == 16_000)
        #expect(atLimit.isOverLimit == false)
        #expect(over.count == 16_001)
        #expect(over.isOverLimit == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func promptIsCountedUntrimmed() {
        let length = limits.evaluate(prompt: "  hi \n", pastedTexts: [], hasImage: false, maxCharactersWithImage: nil)
        #expect(length.count == 6)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func emojiCountAsTwoUTF16Units() {
        let length = limits.evaluate(prompt: "😀", pastedTexts: [AIChatPastedText(content: "😀😀")], hasImage: false, maxCharactersWithImage: nil)
        #expect(length.count == 6)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func imageLowersTheLimitToTheModelValue() {
        let length = limits.evaluate(prompt: text(4_501), pastedTexts: [], hasImage: true, maxCharactersWithImage: 4_500)
        #expect(length.limit == 4_500)
        #expect(length.isOverLimit == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func imageWithoutAModelValueKeepsTheDefaultLimit() {
        let length = limits.evaluate(prompt: text(10), pastedTexts: [], hasImage: true, maxCharactersWithImage: nil)
        #expect(length.limit == 16_000)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func imageNeverRaisesTheLimitAboveTheDefault() {
        let length = limits.evaluate(prompt: text(10), pastedTexts: [], hasImage: true, maxCharactersWithImage: 20_000)
        #expect(length.limit == 16_000)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func fileDoesNotLowerTheLimit() {
        let length = limits.evaluate(prompt: text(4_501), pastedTexts: [], hasImage: false, maxCharactersWithImage: 4_500)
        #expect(length.limit == 16_000)
        #expect(length.isOverLimit == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func editingLimitIsWhatRemainsAfterTheOtherContent() {
        let paste = AIChatPastedText(content: text(5_000))
        let other = AIChatPastedText(content: text(6_000))
        let length = limits.evaluate(prompt: text(1_000), pastedTexts: [paste, other], hasImage: false, maxCharactersWithImage: nil)
        #expect(length.limit(forEditing: paste) == 9_000)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func editingLimitCanBeBelowThePasteAndBelowZero() {
        let paste = AIChatPastedText(content: text(5_000))
        let belowOwnLength = limits.evaluate(prompt: text(12_000), pastedTexts: [paste], hasImage: false, maxCharactersWithImage: nil)
        #expect(belowOwnLength.limit(forEditing: paste) == 4_000)
        let negative = limits.evaluate(prompt: text(17_000), pastedTexts: [paste], hasImage: false, maxCharactersWithImage: nil)
        #expect(negative.limit(forEditing: paste) == -1_000)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func titleIsTheFirstNonBlankLineTrimmed() {
        #expect(AIChatPastedText(content: "  Hello world  \nsecond").title == "Hello world")
        #expect(AIChatPastedText(content: "\n \n\t\n  Third line \nfourth").title == "Third line")
        #expect(AIChatPastedText(content: "\n \n\t").title == "")
        #expect(AIChatPastedText(content: "").title == "")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func lengthIsUTF16AndPayloadCarriesContentVerbatim() {
        let paste = AIChatPastedText(content: "😀\n\"quoted\"")
        #expect(paste.length == 11)
        #expect(paste.payload == AIChatNativePrompt.NativePromptPastedText(content: "😀\n\"quoted\""))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func sameContentWithDifferentIdsAreDifferentValues() {
        let a = AIChatPastedText(content: "x")
        let b = AIChatPastedText(content: "x")
        #expect(a != b, "Save creates a new value so id-based change detection sees the edit")
        #expect(AIChatPastedText(id: a.id, content: "x") == a)
    }
}
