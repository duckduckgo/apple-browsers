//
//  ReaderModeTests.swift
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
import SwiftSoup
import Testing
@testable import ReaderMode

struct ReaderModeTests {
    private let sourceURL = URL(string: "https://example.com/stories/article")!
    private let theme = ReaderTheme(
        background: .init(light: .init(red: 1, green: 1, blue: 1, alpha: 1), dark: .init(red: 0, green: 0, blue: 0, alpha: 1)),
        text: .init(light: .init(red: 0, green: 0, blue: 0, alpha: 1), dark: .init(red: 1, green: 1, blue: 1, alpha: 1)),
        secondaryText: .init(light: .init(red: 0.4, green: 0.4, blue: 0.4, alpha: 1), dark: .init(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)),
        link: .init(light: .init(red: 0, green: 0, blue: 1, alpha: 1), dark: .init(red: 0.5, green: 0.5, blue: 1, alpha: 1)),
        codeBackground: .init(light: .init(red: 0.9, green: 0.9, blue: 0.9, alpha: 1), dark: .init(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)),
        border: .init(light: .init(red: 2, green: -1, blue: .nan, alpha: 0.5), dark: .init(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)))

    private let contentParagraphs = "article p:not(.site):not(.byline)"

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func extractsRealArticle() throws {
        let article = try #require(ReaderModeExtractor().article(fromHTML: fixture("article"), url: sourceURL))
        #expect(article.title == "A mountain journey")
        #expect(article.author == "Alex Walker")
        let html = ReaderDocument.html(for: article, theme: theme)
        let document = try SwiftSoup.parse(html)
        #expect(try document.select(".byline").text() == "Alex Walker")
        #expect(try document.select("p").filter { try $0.text() == "Alex Walker" }.count == 1)
        #expect(try document.select(contentParagraphs).first()?.text().hasPrefix("Paragraph 1.") == true)
        #expect(try document.select("h1").size() == 1)
        #expect(html.contains("Paragraph 8"))
        #expect(html.contains("https://example.com/mountain.jpg"))
        #expect(html.contains("let x = 42"))
        #expect(html.contains("<table>"))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func rejectsNonArticleAndOversizedInput() throws {
        let extractor = ReaderModeExtractor()
        #expect(extractor.article(fromHTML: try fixture("index"), url: sourceURL) == nil)
        #expect(extractor.article(fromHTML: String(repeating: "x", count: 1_048_577), url: sourceURL) == nil)
        #expect(extractor.article(fromHTML: try fixture("article"), url: URL(string: "file:///secret")!) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func sanitizesContentAndEscapesMetadata() throws {
        let html = ReaderDocument.html(for: article(content: try fixture("hostile"), title: "<script>title</script>",
                                                    author: "<img src=x onerror=bad>"), theme: theme)
        let document = try SwiftSoup.parse(html)
        #expect(try document.select("script, iframe, form, input, base, [onclick], [onerror], [srcset], [target]").isEmpty())
        #expect(try document.select("meta[http-equiv=refresh]").isEmpty())
        #expect(try document.select("article [style]").isEmpty())
        #expect(try document.select("a[href^=javascript], img[src^=data]").isEmpty())
        #expect(try document.select("a[href=https://example.com/next]").size() == 1)
        #expect(try document.select("img[src=https://example.com/photo.jpg]").size() == 1)
        #expect(try document.select("pre code").text().contains("let x = 1"))
        #expect(try document.select("pre code").html().contains("\n  print(x)"))
        #expect(try document.select("table td").text() == "Value")
        #expect(try document.title() == "<script>title</script>")
        #expect(html.contains("default-src 'none'"))
        #expect(html.contains("no-referrer"))
        let distinct = ReaderDocument.html(for: article(content: "<h1>Different heading</h1><p>Text</p>"), theme: theme)
        #expect(distinct.contains("Different heading"))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func preservesArticleParagraphsWhenDeduplicatingByline() throws {
        let content = "<p>Alex Walker followed the trail.</p><p>Alex Walker</p>"
        let html = ReaderDocument.html(for: article(content: content, author: "Alex Walker"), theme: theme)
        let paragraphs = try SwiftSoup.parse(html).select(contentParagraphs).map { try $0.text() }
        #expect(paragraphs == ["Alex Walker followed the trail.", "Alex Walker"])

        let withoutAuthor = ReaderDocument.html(for: article(content: "<p>Alex Walker</p>"), theme: theme)
        #expect(try SwiftSoup.parse(withoutAuthor).select(contentParagraphs).text() == "Alex Walker")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func rendersThemeColorsAsClampedHex() {
        let html = ReaderDocument.html(for: article(content: "<p>Text</p>"), theme: theme)
        #expect(html.contains("--background: #FFFFFFFF;"))
        #expect(html.contains("--link: #8080FFFF;"))
        #expect(html.contains("--rule: #FF000080;"))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func keepsElementIDsForInPageLinks() throws {
        let html = ReaderDocument.html(for: article(content: "<p><a href=\"#notes\">notes</a></p><h2 id=\"notes\">Notes</h2>"), theme: theme)
        let document = try SwiftSoup.parse(html)
        #expect(try document.select("h2#notes").size() == 1)
        #expect(try document.select("a[href=https://example.com/stories/article#notes]").size() == 1)
    }

    private func article(content: String, title: String = "Title", author: String? = nil) -> ReaderArticle {
        ReaderArticle(url: sourceURL, title: title, author: author, siteName: nil, contentHTML: content, textLength: 0)
    }

    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }
}
