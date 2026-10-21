//
//  ReaderModeExtractorTests.swift
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
@testable import ReaderMode

struct ReaderModeExtractorTests {

    private let extractor = ReaderModeExtractor()
    private let url = URL(string: "https://example.com/article")!

    @available(macOS 13, *)
    @Test("Wikipedia article is eligible", .timeLimit(.minutes(1)))
    func wikipediaArticleIsEligible() throws {
        let article = try #require(extractor.article(fromHTML: try fixture("wiki"), url: url))
        #expect(article.title == "Swift (programming language) - Wikipedia")
        #expect(article.textLength >= Eligibility.minimumTextLength)
        #expect(article.url == url)
    }

    @available(macOS 13, *)
    @Test("Blog post is eligible", .timeLimit(.minutes(1)))
    func blogPostIsEligible() throws {
        let article = try #require(extractor.article(fromHTML: try fixture("blog"), url: url))
        #expect(article.title == "Swift 6.2 Released")
        #expect(article.siteName == "Swift.org")
        #expect(article.contentHTML.contains("<p>"))
    }

    @available(macOS 13, *)
    @Test("Link listing front page is not eligible", .timeLimit(.minutes(1)))
    func linkListingIsNotEligible() throws {
        #expect(extractor.article(fromHTML: try fixture("hn"), url: url) == nil)
    }

    @available(macOS 13, *)
    @Test("Page with almost no text is not eligible", .timeLimit(.minutes(1)))
    func tinyPageIsNotEligible() {
        #expect(extractor.article(fromHTML: "<html><body><p>Hi</p></body></html>", url: url) == nil)
        #expect(extractor.article(fromHTML: "", url: url) == nil)
    }

    @available(macOS 13, *)
    @Test("Page link text counts only visible anchor text", .timeLimit(.minutes(1)))
    func linkTextMeasurement() {
        let html = """
        <html><head><title>x</title></head><body>
        <script>var a = "<a href='/x'>hidden</a>";</script>
        <p>Read the <a href="/d"><b>docs</b></a> here</p>
        </body></html>
        """
        let measurement = Eligibility.Measurement(extractedText: "", extractedHTML: "", pageHTML: html)
        #expect(measurement.pageTextLength == "Read the docs here".count)
        #expect(measurement.pageLinkTextLength == "docs".count)
    }

    @available(macOS 13, *)
    @Test("Eligibility needs enough text in several paragraphs and a page that is not mostly links", .timeLimit(.minutes(1)))
    func eligibilityRule() {
        #expect(Eligibility.isEligible(.init(extractedTextLength: 2000, extractedParagraphCount: 4, pageTextLength: 4000, pageLinkTextLength: 800)))
        #expect(!Eligibility.isEligible(.init(extractedTextLength: 2000, extractedParagraphCount: 4, pageTextLength: 4000, pageLinkTextLength: 3000)))
        #expect(!Eligibility.isEligible(.init(extractedTextLength: Eligibility.minimumTextLength - 1, extractedParagraphCount: 4, pageTextLength: 4000, pageLinkTextLength: 0)))
        #expect(!Eligibility.isEligible(.init(extractedTextLength: 2000, extractedParagraphCount: 1, pageTextLength: 4000, pageLinkTextLength: 0)))
    }

    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }
}
