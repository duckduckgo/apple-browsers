//
//  IncrementalMarkdownTests.swift
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

@Suite struct IncrementalMarkdownTests {
    private let fixtures = [
        "# Heading\n\nParagraph **bold** and [link](https://example.com).\nnext\n\nDone",
        "- one\n  continued\n- two\n\n3. three\n4. four\n\nDone",
        "> # Heading\n> quoted\n>\n> next\n\nDone",
        "prefix\n```swift\nline\n\nmore\n```\n\nDone",
        "| A | B |\n| --- | :---: |\n| a | b |\n\nDone",
        "First\r\n\r\nSecond\r\n---\r\n\r\nDone",
        "First\nheader | cell\n--- | ---\nvalue | value\n\nEnd",
        "**unfinished", "```swift\n\nopen", "First\n```\ncode\n```x\nmore"
    ]

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func everyScalarAppendHasTheSameGrammarAsOneShotParsing() {
        for source in fixtures {
            var document = IncrementalMarkdown()
            var prefix = ""
            for scalar in source.unicodeScalars {
                prefix.unicodeScalars.append(scalar)
                let frozen = document.blocks.filter { !$0.isStreaming }
                document.update(prefix, isStreaming: true)
                #expect(document.blocks.map(\.block) == MarkdownParser.blocks(from: prefix, isStreaming: true))
                #expect(Array(document.blocks.prefix(frozen.count)) == frozen)
            }
            document.update(source, isStreaming: false)
            #expect(document.blocks.map(\.block) == MarkdownParser.blocks(from: source))
            #expect(document.blocks.allSatisfy { !$0.isStreaming })
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func completedParagraphsKeepIdentityAndAreNotReparsed() {
        let prefix = String(repeating: "A finished paragraph.\n\n", count: 100)
        var document = IncrementalMarkdown()
        document.update(prefix + "Tail\n\nNext", isStreaming: true)
        let frozen = document.blocks.filter { !$0.isStreaming }
        #expect(frozen.count >= 100)
        let consumed = document.consumedUTF8
        document.update(prefix + "Tail\n\nNext grows", isStreaming: true)
        #expect(document.consumedUTF8 >= consumed)
        #expect(document.lastParsedUTF8 < 50)
        #expect(Array(document.blocks.prefix(frozen.count)) == frozen)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func repairHidesOpenMarkersAndLinksWithoutChangingFinalSource() {
        let examples: [(String, MarkdownBlock)] = [
            ("**", .paragraph("")), ("`", .paragraph("")), ("Hello **", .paragraph("Hello ")),
            ("```sw", .codeBlock(language: "sw", code: "")),
            ("[Duc", .paragraph("Duc")), ("See [Duck](https://ex", .paragraph("See Duck")),
            ("**bold", .paragraph("**bold**")), ("`code", .paragraph("`code`"))
        ]
        for (source, expected) in examples {
            var document = IncrementalMarkdown()
            document.update(source, isStreaming: true)
            #expect(document.blocks.map(\.block) == [expected])
            document.update(source, isStreaming: false)
            #expect(document.blocks.map(\.block) == MarkdownParser.blocks(from: source))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func replacementInvalidatesOnlyItsOwnDocument() {
        var document = IncrementalMarkdown()
        document.update("Old\n\nText\n\nTail", isStreaming: true)
        document.update("# Replacement", isStreaming: false)
        #expect(document.blocks.map(\.block) == [.heading(level: 1, text: "Replacement")])
        #expect(document.blocks.first?.id == 0)
    }
}
