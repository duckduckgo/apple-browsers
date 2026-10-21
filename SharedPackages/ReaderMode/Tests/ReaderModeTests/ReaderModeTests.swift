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

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func extractsRealArticle() async throws {
        let article = try #require(await ReaderExtractor().extract(html: fixture("article"), sourceURL: sourceURL, theme: theme))
        #expect(article.title == "A mountain journey")
        #expect(article.author == "Alex Walker")
        let document = try SwiftSoup.parse(article.renderedHTML)
        #expect(try document.select(".byline").text() == "Alex Walker")
        #expect(try document.select("p").filter { try $0.text() == "Alex Walker" }.count == 1)
        #expect(try document.select("article p").first()?.text().hasPrefix("Paragraph 1.") == true)
        #expect(try SwiftSoup.parse(article.renderedHTML).select("h1").size() == 1)
        #expect(article.renderedHTML.contains("Paragraph 8"))
        #expect(article.renderedHTML.contains("https://example.com/mountain.jpg"))
        #expect(article.renderedHTML.contains("let x = 42"))
        #expect(article.renderedHTML.contains("<table>"))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func rejectsNonArticleAndOversizedInput() async throws {
        let extractor = ReaderExtractor()
        #expect(try await extractor.extract(html: fixture("index"), sourceURL: sourceURL, theme: theme) == nil)
        #expect(try await extractor.extract(html: String(repeating: "x", count: 1_048_577), sourceURL: sourceURL, theme: theme) == nil)
        #expect(try await extractor.extract(html: fixture("article"), sourceURL: URL(string: "file:///secret")!, theme: theme) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func sanitizesContentAndEscapesMetadata() throws {
        let html = try ReaderHTML.render(content: fixture("hostile"), title: "<script>title</script>",
                                         author: "<img src=x onerror=bad>", sourceURL: sourceURL, theme: theme)
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
        let distinct = try ReaderHTML.render(content: "<h1>Different heading</h1><p>Text</p>", title: "Title", author: nil, sourceURL: sourceURL, theme: theme)
        #expect(distinct.contains("Different heading"))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func preservesArticleParagraphsWhenDeduplicatingByline() throws {
        let content = "<p>Alex Walker followed the trail.</p><p>Alex Walker</p>"
        let html = try ReaderHTML.render(content: content, title: "Title", author: "Alex Walker", sourceURL: sourceURL, theme: theme)
        let paragraphs = try SwiftSoup.parse(html).select("article p").map { try $0.text() }
        #expect(paragraphs == ["Alex Walker followed the trail.", "Alex Walker"])

        let withoutAuthor = try ReaderHTML.render(content: "<p>Alex Walker</p>", title: "Title", author: nil, sourceURL: sourceURL, theme: theme)
        #expect(try SwiftSoup.parse(withoutAuthor).select("article p").text() == "Alex Walker")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func rendersThemeColorsAsClampedHex() throws {
        let html = try ReaderHTML.render(content: "<p>Text</p>", title: "Title", author: nil, sourceURL: sourceURL, theme: theme)
        #expect(html.contains("background: light-dark(#FFFFFFFF,#000000FF)"))
        #expect(html.contains("a { color: light-dark(#0000FFFF,#8080FFFF); }"))
        #expect(html.contains("border: 1px solid light-dark(#FF000080,#808080FF)"))
    }

    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }
}
