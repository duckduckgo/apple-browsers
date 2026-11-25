//
//  PageTranslationBatchesTests.swift
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
@testable import WebPageTranslation

@Suite
struct PageTranslationBatchesTests {

    private static func unit(_ id: Int, _ text: String, html: Bool = false, visible: Bool = true) -> PageTranslationUnit {
        PageTranslationUnit(id: id, text: text, html: html, vp: visible ? 1 : 0)
    }

    private static func ids(_ batches: [[PageTranslationUnit]]) -> [[Int]] {
        batches.map { $0.map(\.id) }
    }

    @available(iOS 16, macOS 13, *)
    @Test("visible units come first, then the rest, each in page order", .timeLimit(.minutes(1)))
    func visibleUnitsComeFirst() {
        let units = [Self.unit(1, "a", visible: false), Self.unit(2, "b"), Self.unit(3, "c", visible: false), Self.unit(4, "d")]

        #expect(Self.ids(PageTranslationBatches.make(units, characterLimit: 100)) == [[2, 4], [1, 3]])
    }

    @available(iOS 16, macOS 13, *)
    @Test("visible HTML isn't held behind a plain batch that carries off-screen units", .timeLimit(.minutes(1)))
    func visibleAndOffscreenUnitsNeverShareABatch() {
        let units = [Self.unit(1, "a"), Self.unit(2, "<b>b</b>", html: true), Self.unit(3, "c", visible: false)]

        #expect(Self.ids(PageTranslationBatches.make(units, characterLimit: 100)) == [[1], [2], [3]])
    }

    @available(iOS 16, macOS 13, *)
    @Test("a batch takes units until the next one would pass the character limit", .timeLimit(.minutes(1)))
    func chunksByCharacters() {
        let units = [Self.unit(1, "aaaaaa"), Self.unit(2, "bbbbbb"), Self.unit(3, "cccccc"), Self.unit(4, "ddd")]

        #expect(Self.ids(PageTranslationBatches.make(units, characterLimit: 12)) == [[1, 2], [3, 4]])
    }

    @available(iOS 16, macOS 13, *)
    @Test("a unit longer than the limit goes in a batch by itself, unsplit", .timeLimit(.minutes(1)))
    func oversizedUnitGoesAlone() {
        let long = String(repeating: "x", count: 20)
        let batches = PageTranslationBatches.make([Self.unit(1, "aaa"), Self.unit(2, long), Self.unit(3, "bbb")], characterLimit: 10)

        #expect(Self.ids(batches) == [[1], [2], [3]])
        #expect(batches[1].first?.text == long)
    }

    @available(iOS 16, macOS 13, *)
    @Test("plain and HTML units never share a batch", .timeLimit(.minutes(1)))
    func plainAndHtmlNeverShareABatch() {
        let units = [Self.unit(1, "a"), Self.unit(2, "<b>b</b>", html: true), Self.unit(3, "c"), Self.unit(4, "<i>d</i>", html: true)]
        let batches = PageTranslationBatches.make(units, characterLimit: 100)

        #expect(Self.ids(batches) == [[1, 3], [2, 4]])
        #expect(batches.allSatisfy { batch in batch.allSatisfy { $0.html == batch[0].html } })
    }

    @available(iOS 16, macOS 13, *)
    @Test("HTML units count only their text, without tags", .timeLimit(.minutes(1)))
    func htmlCountsTextWithoutTags() {
        let link = #"<a href="https://example.com/a/long/path">abc</a>"#
        let batches = PageTranslationBatches.make([Self.unit(1, link, html: true), Self.unit(2, link + " ", html: true)], characterLimit: 7)

        #expect(Self.ids(batches) == [[1, 2]])
    }

    @available(iOS 16, macOS 13, *)
    @Test("no units make no batches", .timeLimit(.minutes(1)))
    func emptyUnitsMakeNoBatches() {
        #expect(PageTranslationBatches.make([], characterLimit: 100).isEmpty)
    }
}
