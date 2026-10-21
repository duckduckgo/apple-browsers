//
//  EvalSet.swift
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

public enum EvalSet {
    public static let articles: [(language: String, title: String)] = [
        (language: "en", title: "Photosynthesis"),
        (language: "en", title: "Roman Empire"),
        (language: "en", title: "Coffee"),
        (language: "en", title: "Volcano"),
        (language: "en", title: "Bicycle"),
        (language: "en", title: "Internet"),
        (language: "de", title: "Photosynthese"),
        (language: "fr", title: "Tour Eiffel"),
        (language: "es", title: "Café"),
        (language: "ja", title: "富士山")
    ]

    public static func make(articles: [(language: String, title: String, text: String)]) -> [EvalCase] {
        articles.flatMap { article in
            let slug = "\(article.language)-\(article.title)"
            let url = URL(string: "https://\(article.language).wikipedia.org/wiki/\(article.title)")
            let page = EvalPage(title: article.title, url: url, content: String(article.text.prefix(9_500)), language: article.language)
            let shortPage = EvalPage(title: article.title, url: url, content: String(article.text.prefix(3_000)), language: article.language)
            let targetLanguage = article.language == "en" ? "German" : "English"
            return [
                EvalCase(id: "\(slug)/summarize-page", task: .summarizePage, page: page, selection: nil, languageName: nil),
                EvalCase(id: "\(slug)/summarize-page-short", task: .summarizePage, page: shortPage, selection: nil, languageName: nil),
                EvalCase(id: "\(slug)/summarize-selection", task: .summarizeSelection, page: page,
                         selection: excerpt(of: article.text, maxCharacters: 1_200), languageName: nil),
                EvalCase(id: "\(slug)/suggest-prompts", task: .suggestPrompts, page: page, selection: nil, languageName: "English"),
                EvalCase(id: "\(slug)/translate-page", task: .translatePage, page: shortPage, selection: nil, languageName: targetLanguage),
                EvalCase(id: "\(slug)/translate-selection", task: .translateSelection, page: page,
                         selection: excerpt(of: article.text, maxCharacters: 800), languageName: targetLanguage)
            ]
        }
    }

    private static func excerpt(of text: String, maxCharacters: Int) -> String {
        let paragraphs = text.components(separatedBy: "\n").filter { $0.count > 80 }
        var result = ""
        for paragraph in paragraphs.dropFirst() {
            if !result.isEmpty, result.count + paragraph.count + 1 > maxCharacters { break }
            result += result.isEmpty ? paragraph : "\n" + paragraph
        }
        return String((result.isEmpty ? text : result).prefix(maxCharacters))
    }
}
