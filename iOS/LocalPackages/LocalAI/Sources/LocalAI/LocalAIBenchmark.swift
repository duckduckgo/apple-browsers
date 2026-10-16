//
//  LocalAIBenchmark.swift
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

public struct LocalAIBenchmarkCase: Codable, Equatable, Sendable {
    public let id: String
    public let request: LocalAIRequest
}

/// A fixed set of ~30 requests built from Wikipedia articles in five languages, with page and selection
/// inputs of mixed lengths. Articles are fetched once (needs network) and cached, so later runs work
/// offline and every run sees identical input.
public enum LocalAIBenchmarkSet {

    struct Article {
        let language: String
        let title: String
    }

    static let articles = [
        Article(language: "en", title: "Photosynthesis"),
        Article(language: "en", title: "Roman Empire"),
        Article(language: "en", title: "Coffee"),
        Article(language: "en", title: "Volcano"),
        Article(language: "en", title: "Bicycle"),
        Article(language: "en", title: "Internet"),
        Article(language: "de", title: "Photosynthese"),
        Article(language: "fr", title: "Tour Eiffel"),
        Article(language: "es", title: "Café"),
        Article(language: "ja", title: "富士山")
    ]

    /// Same cap as the page-context script.
    static let pageCharacterLimit = 9_500
    static let shortPageCharacterLimit = 3_000
    static let selectionCharacterLimit = 1_200
    static let translationSelectionCharacterLimit = 800

    public static func cases(language: String = "English", cacheDirectory: URL,
                             session: URLSession = .shared) async throws -> [LocalAIBenchmarkCase] {
        let texts = try await articleTexts(cacheDirectory: cacheDirectory, session: session)
        return makeCases(texts: texts, language: language)
    }

    static func makeCases(texts: [(article: Article, text: String)], language: String) -> [LocalAIBenchmarkCase] {
        var cases: [LocalAIBenchmarkCase] = []
        for (index, entry) in texts.enumerated() {
            let slug = "\(entry.article.language)-\(entry.article.title)"
            let pageLimit = index.isMultiple(of: 2) ? pageCharacterLimit : shortPageCharacterLimit
            let page = LocalAIPage(title: entry.article.title,
                                   url: "https://\(entry.article.language).wikipedia.org/wiki/\(entry.article.title)",
                                   content: String(entry.text.prefix(pageLimit)))
            let selection = excerpt(of: entry.text, maxCharacters: selectionCharacterLimit)
            cases.append(LocalAIBenchmarkCase(id: "\(slug)/summarize-page-\(pageLimit)",
                                              request: LocalAIRequest(task: .summarize, source: .page(page), language: language)))
            cases.append(LocalAIBenchmarkCase(id: "\(slug)/summarize-selection",
                                              request: LocalAIRequest(task: .summarize, source: .selection([selection]), language: language)))
            guard entry.article.language != "en" else { continue }
            let translation = excerpt(of: entry.text, maxCharacters: translationSelectionCharacterLimit)
            cases.append(LocalAIBenchmarkCase(id: "\(slug)/translate-selection",
                                              request: LocalAIRequest(task: .translate, source: .selection([translation]), language: language)))
            cases.append(LocalAIBenchmarkCase(id: "\(slug)/translate-page-\(pageLimit)",
                                              request: LocalAIRequest(task: .translate, source: .page(page), language: language)))
        }
        return cases
    }

    /// Whole paragraphs from the second paragraph on (the first is usually the lead the page summary
    /// already covers), up to `maxCharacters`.
    static func excerpt(of text: String, maxCharacters: Int) -> String {
        let paragraphs = text.components(separatedBy: "\n").filter { $0.count > 80 }
        var result = ""
        for paragraph in paragraphs.dropFirst() {
            if !result.isEmpty, result.count + paragraph.count + 1 > maxCharacters { break }
            result += result.isEmpty ? paragraph : "\n" + paragraph
        }
        return String((result.isEmpty ? text : result).prefix(maxCharacters))
    }

    private struct ExtractResponse: Decodable {
        struct Query: Decodable {
            struct Page: Decodable { let extract: String? }
            let pages: [String: Page]
        }
        let query: Query
    }

    private static func articleTexts(cacheDirectory: URL, session: URLSession) async throws -> [(article: Article, text: String)] {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        var result: [(article: Article, text: String)] = []
        for article in articles {
            let cached = cacheDirectory.appendingPathComponent("\(article.language)-\(article.title).txt")
            if let text = try? String(contentsOf: cached, encoding: .utf8) {
                result.append((article, text))
                continue
            }
            var components = URLComponents(string: "https://\(article.language).wikipedia.org/w/api.php")!
            components.queryItems = [
                URLQueryItem(name: "action", value: "query"),
                URLQueryItem(name: "prop", value: "extracts"),
                URLQueryItem(name: "explaintext", value: "1"),
                URLQueryItem(name: "redirects", value: "1"),
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "titles", value: article.title)
            ]
            let (data, _) = try await session.data(from: components.url!)
            let response = try JSONDecoder().decode(ExtractResponse.self, from: data)
            guard let text = response.query.pages.values.first?.extract, !text.isEmpty else {
                throw URLError(.cannotParseResponse)
            }
            try text.write(to: cached, atomically: true, encoding: .utf8)
            result.append((article, text))
        }
        return result
    }
}

public struct LocalAIBenchmarkReport: Codable, Sendable {
    public let startedAt: Date
    public let device: String
    public let osVersion: String
    public let physicalMemoryBytes: UInt64
    public let engine: LocalAIEngineKind
    public let model: String
    public let interruptedGenerationsBefore: Int
    /// Loading the model and one short generation, before the measured runs.
    public var warmUpTime: TimeInterval?
    public var records: [LocalAIRunRecord] = []
}

@MainActor
public final class LocalAIBenchmarkRunner {

    public static let runsPerCase = 3

    public init() {}

    /// Runs every case `runsPerCase` times through `engine`, reporting progress as (done, total), and
    /// writes the report as JSON into `outputDirectory`. Returns the file.
    public func run(cases: [LocalAIBenchmarkCase], engine: LocalAIEngine, device: String, osVersion: String,
                    outputDirectory: URL, progress: (Int, Int) -> Void) async throws -> URL {
        var report = LocalAIBenchmarkReport(startedAt: Date(), device: device, osVersion: osVersion,
                                            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                                            engine: engine.kind, model: engine.modelName,
                                            interruptedGenerationsBefore: LocalAIInterruptedRunTracker.interruptedCount())
        let warmUpStart = Date()
        let warmUp = LocalAIRequest(task: .summarize, source: .selection(["The quick brown fox jumps over the lazy dog."]), language: "English")
        _ = await LocalAIRunner.run(warmUp, engine: engine)
        report.warmUpTime = Date().timeIntervalSince(warmUpStart)

        let total = cases.count * Self.runsPerCase
        var done = 0
        for benchmarkCase in cases {
            for run in 1...Self.runsPerCase {
                try Task.checkCancellation()
                let (record, _) = await LocalAIRunner.run(benchmarkCase.request, engine: engine, caseID: benchmarkCase.id, run: run)
                report.records.append(record)
                done += 1
                progress(done, total)
            }
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime]
        let file = outputDirectory.appendingPathComponent("benchmark-\(engine.kind.rawValue)-\(formatter.string(from: report.startedAt)).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: file)
        return file
    }
}
