//
//  EvalArticles.swift
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

/// Fetches the plain text of `EvalSet.articles` from Wikipedia once and caches it, so later runs read the same input.
public enum EvalArticles {

    public static func fetch(cacheDirectory: URL, session: URLSession = .shared) async throws -> [(language: String, title: String, text: String)] {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        var result: [(language: String, title: String, text: String)] = []
        for article in EvalSet.articles {
            let cached = cacheDirectory.appendingPathComponent("\(article.language)-\(article.title).txt")
            if let text = try? String(contentsOf: cached, encoding: .utf8) {
                result.append((article.language, article.title, text))
                continue
            }
            let text = try await extract(article.title, language: article.language, session: session)
            try text.write(to: cached, atomically: true, encoding: .utf8)
            result.append((article.language, article.title, text))
        }
        return result
    }

    private static func extract(_ title: String, language: String, session: URLSession) async throws -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "\(language).wikipedia.org"
        components.path = "/w/api.php"
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "prop", value: "extracts"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "titles", value: title)
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(ExtractResponse.self, from: data)
        guard let text = response.query.pages.values.first?.extract, !text.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return text
    }

    private struct ExtractResponse: Decodable {
        struct Query: Decodable {
            let pages: [String: Page]
        }
        struct Page: Decodable {
            let extract: String?
        }
        let query: Query
    }
}
