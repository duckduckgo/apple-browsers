//
//  LocalAIMarkdownTests.swift
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
import Testing
@testable import LocalAI

@Suite("Markdown blocks for model replies")
struct LocalAIMarkdownTests {

    @available(iOS 16, macOS 13, *)
    @Test("A summary splits into an overview paragraph and a bullet list", .timeLimit(.minutes(1)))
    func summaryShape() {
        let text = """
        Coffee is a drink made from roasted beans.

        - It is grown in **over 50** countries.
        * It contains caffeine.
        """

        #expect(LocalAIMarkdown.blocks(from: text) == [
            .paragraph("Coffee is a drink made from roasted beans."),
            .bulletList(["It is grown in **over 50** countries.", "It contains caffeine."])
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Headings, numbered lists and paragraph lines are kept apart", .timeLimit(.minutes(1)))
    func mixedBlocks() {
        let text = """
        ## History
        First line
        second line
        1. One
        2) Two
        """

        #expect(LocalAIMarkdown.blocks(from: text) == [
            .heading(level: 2, text: "History"),
            .paragraph("First line\nsecond line"),
            .numberedList(["One", "Two"])
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A code fence still streaming in runs to the end of the text", .timeLimit(.minutes(1)))
    func unclosedCodeFence() {
        #expect(LocalAIMarkdown.blocks(from: "Run this:\n```\nlet a = 1\n") == [
            .paragraph("Run this:"),
            .code("let a = 1\n")
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Hashes without a space and text inside code stay literal", .timeLimit(.minutes(1)))
    func literals() {
        #expect(LocalAIMarkdown.blocks(from: "#hashtag\n```\n- not a list\n```") == [
            .paragraph("#hashtag"),
            .code("- not a list")
        ])
    }
}
