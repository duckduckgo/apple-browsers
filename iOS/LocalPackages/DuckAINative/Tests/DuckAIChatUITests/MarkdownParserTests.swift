//
//  MarkdownParserTests.swift
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

import Testing
@testable import DuckAIChatUI

@Suite struct MarkdownParserTests {

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func headingsAndParagraphs() {
        let blocks = MarkdownParser.blocks(from: "# Title\n\nFirst line\nsecond line\n\n### Small\nAfter")

        #expect(blocks == [
            .heading(level: 1, text: "Title"),
            .paragraph("First line\nsecond line"),
            .heading(level: 3, text: "Small"),
            .paragraph("After")
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func unorderedAndOrderedLists() {
        let blocks = MarkdownParser.blocks(from: "- one\n- **two**\n\n3. three\n4. four")

        #expect(blocks == [
            .list(ordered: false, start: 1, items: ["one", "**two**"]),
            .list(ordered: true, start: 3, items: ["three", "four"])
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func fencedCodeKeepsItsLanguageAndWhitespace() {
        let blocks = MarkdownParser.blocks(from: "Look:\n```swift\nlet a = 1\n  let b = 2\n```\nDone")

        #expect(blocks == [
            .paragraph("Look:"),
            .codeBlock(language: "swift", code: "let a = 1\n  let b = 2"),
            .paragraph("Done")
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func blockquoteContentIsParsedAsBlocks() {
        let blocks = MarkdownParser.blocks(from: "> # Note\n> Ducks float.")

        #expect(blocks == [.blockquote([.heading(level: 1, text: "Note"), .paragraph("Ducks float.")])])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func tableWithHeaderAndRows() {
        let blocks = MarkdownParser.blocks(from: "| Duck | Habitat |\n| --- | :---: |\n| Mallard | Ponds |\n| Eider | Coasts |")

        #expect(blocks == [.table(header: ["Duck", "Habitat"], rows: [["Mallard", "Ponds"], ["Eider", "Coasts"]])])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func thematicBreakBetweenParagraphs() {
        #expect(MarkdownParser.blocks(from: "Above\n\n---\n\nBelow") == [.paragraph("Above"), .thematicBreak, .paragraph("Below")])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func streamingClosesAnOpenFence() {
        #expect(MarkdownParser.blocks(from: "```python\nprint(1)", isStreaming: true) == [.codeBlock(language: "python", code: "print(1)")])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func streamingClosesUnmatchedEmphasisInTheLastBlockOnly() {
        #expect(MarkdownParser.blocks(from: "Hello **wor", isStreaming: true) == [.paragraph("Hello **wor**")])
        #expect(MarkdownParser.blocks(from: "Say `co", isStreaming: true) == [.paragraph("Say `co`")])
        #expect(MarkdownParser.blocks(from: "Hello **wor") == [.paragraph("Hello **wor")])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func streamingShowsAnUnfinishedLinkAsItsText() {
        #expect(MarkdownParser.blocks(from: "See [Ducks](https://exa", isStreaming: true) == [.paragraph("See Ducks")])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func emptyInputHasNoBlocks() {
        #expect(MarkdownParser.blocks(from: "").isEmpty)
        #expect(MarkdownParser.blocks(from: "\n\n  \n").isEmpty)
    }
}
