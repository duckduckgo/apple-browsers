//
//  ReaderModeExtractor.swift
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
import Trafilatura

public struct ReaderArticle: Equatable, Sendable {
    public let url: URL
    public let title: String
    public let siteName: String?
    public let contentHTML: String
    public let textLength: Int

    public init(url: URL, title: String, siteName: String?, contentHTML: String, textLength: Int) {
        self.url = url
        self.title = title
        self.siteName = siteName
        self.contentHTML = contentHTML
        self.textLength = textLength
    }
}

public struct ReaderModeExtractor: Sendable {

    public init() {}

    /// Returns `nil` when the page is not eligible for Reader Mode.
    public func article(fromHTML html: String, url: URL) -> ReaderArticle? {
        var options = defaultOptions()
        options.originalUrl = url.absoluteString
        options.includeImages = true
        options.includeLinks = true

        guard let result = try? extract(html: html, options: options) else {
            return nil
        }
        let measurement = Eligibility.Measurement(extractedText: result.contentText, pageHTML: html)
        guard Eligibility.isEligible(measurement) else {
            return nil
        }

        let title = result.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let siteName = result.metadata.sitename.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReaderArticle(url: url,
                             title: title.isEmpty ? (url.host ?? url.absoluteString) : title,
                             siteName: siteName.isEmpty ? nil : siteName,
                             contentHTML: result.contentHtml,
                             textLength: measurement.extractedTextLength)
    }
}

/// Trafilatura has no "readerable" check: it returns content for any page, including link listings
/// such as a news aggregator front page, which it flattens into a single paragraph with the links removed.
/// The extracted content can't tell those apart from an article, so link density is measured on the whole page.
enum Eligibility {

    static let minimumTextLength = 500

    /// Share of the page's visible text that sits inside links.
    /// Measured: Wikipedia article 0.18, swift.org blog post 0.10, Hacker News front page 0.79.
    static let maximumPageLinkTextRatio = 0.5

    struct Measurement: Equatable {
        let extractedTextLength: Int
        let pageTextLength: Int
        let pageLinkTextLength: Int

        var pageLinkTextRatio: Double {
            pageTextLength == 0 ? 1 : Double(pageLinkTextLength) / Double(pageTextLength)
        }

        init(extractedTextLength: Int, pageTextLength: Int, pageLinkTextLength: Int) {
            self.extractedTextLength = extractedTextLength
            self.pageTextLength = pageTextLength
            self.pageLinkTextLength = pageLinkTextLength
        }

        init(extractedText: String, pageHTML: String) {
            let markup = Self.visibleMarkup(of: pageHTML)
            self.init(extractedTextLength: extractedText.count,
                      pageTextLength: Self.text(of: markup).count,
                      pageLinkTextLength: Self.linkTextLength(in: markup))
        }

        // swiftlint:disable force_try
        private static let invisibleRegex = try! NSRegularExpression(pattern: "<(script|style|noscript|template)\\b[\\s\\S]*?</\\1\\s*>|<!--[\\s\\S]*?-->",
                                                                     options: .caseInsensitive)
        private static let anchorRegex = try! NSRegularExpression(pattern: "<a\\b[^>]*>([\\s\\S]*?)</a\\s*>", options: .caseInsensitive)
        private static let tagRegex = try! NSRegularExpression(pattern: "<[^>]*>")
        private static let whitespaceRegex = try! NSRegularExpression(pattern: "\\s+")
        // swiftlint:enable force_try

        private static func visibleMarkup(of html: String) -> String {
            let body = html.range(of: "<body", options: .caseInsensitive).map { String(html[$0.lowerBound...]) } ?? html
            return replacing(invisibleRegex, in: body, with: "")
        }

        private static func text(of markup: String) -> String {
            replacing(whitespaceRegex, in: replacing(tagRegex, in: markup, with: ""), with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private static func linkTextLength(in markup: String) -> Int {
            let nsMarkup = markup as NSString
            return anchorRegex.matches(in: markup, range: NSRange(location: 0, length: nsMarkup.length)).reduce(0) { total, match in
                total + text(of: nsMarkup.substring(with: match.range(at: 1))).count
            }
        }

        private static func replacing(_ regex: NSRegularExpression, in string: String, with template: String) -> String {
            regex.stringByReplacingMatches(in: string, range: NSRange(location: 0, length: (string as NSString).length), withTemplate: template)
        }
    }

    static func isEligible(_ measurement: Measurement) -> Bool {
        measurement.extractedTextLength >= minimumTextLength && measurement.pageLinkTextRatio <= maximumPageLinkTextRatio
    }
}
