//
//  ReaderExtractor.swift
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
import Trafilatura

/// Serializes the synchronous native extractor away from the main actor.
public actor ReaderExtractor {
    public static let shared = ReaderExtractor()

    public init() {}

    /// Returns nil for unsupported, oversized or non-article pages. Content stays on device.
    public func extract(html: String, sourceURL: URL, theme: ReaderTheme) async throws -> ReaderArticle? {
        try Task.checkCancellation()
        guard ["http", "https"].contains(sourceURL.scheme?.lowercased() ?? ""),
              html.utf8.count <= 1_048_576 else { return nil }
        var options = defaultOptions()
        options.originalUrl = sourceURL.absoluteString
        options.includeImages = true
        options.includeLinks = true
        options.excludeComments = true
        options.excludeTables = false
        let result: ExtractResult
        do {
            result = try Trafilatura.extract(html: html, options: options)
        } catch TrafilaturaError.InsufficientContent {
            return nil
        }
        try Task.checkCancellation()
        let body = try SwiftSoup.parseBodyFragment(result.contentHtml)
        guard result.contentText.count >= 500,
              try body.select("p").size() >= 2 else { return nil }
        let title = result.metadata.title.isEmpty ? (sourceURL.host ?? "") : result.metadata.title
        let author = result.metadata.author.isEmpty ? nil : result.metadata.author
        let rendered = try ReaderHTML.render(content: result.contentHtml, title: title, author: author, sourceURL: sourceURL, theme: theme)
        return ReaderArticle(title: title, author: author, sourceURL: sourceURL, renderedHTML: rendered)
    }
}
