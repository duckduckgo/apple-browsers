//
//  SearchDownloadsBrowserToolTests.swift
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

import AIChat
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class SearchDownloadsBrowserToolTests: XCTestCase {

    private let context = BrowserToolCallContext(ownerTabID: "owner", isBurner: false)

    func testWhenTheQueryMatchesThenCompletedDownloadsAreReturnedNewestFirstWithoutLocalPaths() async {
        let tool = SearchDownloadsBrowserTool(downloads: { [
            self.item("paris-travel-guide.pdf", from: "https://example.com/files/paris-travel-guide.pdf", at: 1_000),
            self.item("notes.txt", from: "https://cdn.example.com/PARIS/notes.txt", at: 2_000),
            self.item("rome.pdf", from: "https://example.com/rome.pdf", at: 3_000)
        ] })

        let result = await tool.execute(arguments: ["query": "paris"], context: context)

        XCTAssertEqual(result, .success(["results": [
            ["fileName": "notes.txt", "url": "https://cdn.example.com/PARIS/notes.txt", "downloadedAt": "1970-01-01T00:33:20.000Z"],
            ["fileName": "paris-travel-guide.pdf", "url": "https://example.com/files/paris-travel-guide.pdf", "downloadedAt": "1970-01-01T00:16:40.000Z"]
        ]]))
    }

    func testWhenASourceURLHasAQueryOrIsNotAWebAddressThenOnlyTheSafePartIsReturnedAndMatched() async {
        let tool = SearchDownloadsBrowserTool(downloads: { [
            self.item("report.pdf", from: "https://bucket.example/report.pdf?X-Amz-Signature=secret#page=2", at: 2),
            self.item("inline.txt", from: "data:text/plain,secret", at: 1)
        ] })

        let byName = await tool.execute(arguments: ["query": "."], context: context)
        let byToken = await tool.execute(arguments: ["query": "secret"], context: context)

        XCTAssertEqual(byName, .success(["results": [
            ["fileName": "report.pdf", "url": "https://bucket.example/report.pdf", "downloadedAt": "1970-01-01T00:00:02.000Z"],
            ["fileName": "inline.txt", "url": "", "downloadedAt": "1970-01-01T00:00:01.000Z"]
        ]]))
        XCTAssertEqual(byToken, .success(["results": []]))
    }

    func testWhenADownloadIsUnfinishedOrFailedThenItIsLeftOut() async {
        var unfinished = item("a.pdf", from: "https://example.com/a.pdf", at: 1)
        unfinished.progress = Progress(totalUnitCount: 10)
        var failed = item("b.pdf", from: "https://example.com/b.pdf", at: 2)
        failed.error = .failedToMoveFileToDownloads
        let tool = SearchDownloadsBrowserTool(downloads: { [unfinished, failed] })

        let result = await tool.execute(arguments: ["query": "pdf"], context: context)

        XCTAssertEqual(result, .success(["results": []]))
    }

    func testWhenNoQueryOrLimitIsGivenThenTheTenNewestDownloadsAreReturned() async {
        let items = (0..<60).map { item("file\($0).pdf", from: "https://example.com/\($0).pdf", at: TimeInterval($0)) }
        let tool = SearchDownloadsBrowserTool(downloads: { items })

        let defaulted = await tool.execute(arguments: [:], context: context)
        let limited = await tool.execute(arguments: ["query": "", "limit": 50], context: context)

        XCTAssertEqual(defaulted.results?.count, 10)
        XCTAssertEqual(defaulted.results?.first?["fileName"], "file59.pdf")
        XCTAssertEqual(limited.results?.count, 50)
    }

    func testWhenArgumentsAreMalformedThenTheyAreInvalid() async {
        let tool = SearchDownloadsBrowserTool(downloads: { [] })
        let tooLong = String(repeating: "a", count: BrowserToolOutputLimits.query + 1)

        for arguments: JSONValue in [["query": 1], ["query": .string(tooLong)],
                                     ["query": "a", "limit": 0], ["query": "a", "limit": 51], ["query": "a", "limit": "5"]] {
            let result = await tool.execute(arguments: arguments, context: context)
            XCTAssertEqual(result, .failure(.invalidArguments), "\(arguments)")
        }
    }

    func testWhenCalledInAFireWindowThenCallIsUnavailable() async {
        let tool = SearchDownloadsBrowserTool(downloads: { [] })

        let result = await tool.execute(arguments: ["query": "a"], context: BrowserToolCallContext(ownerTabID: "owner", isBurner: true))

        XCTAssertEqual(result, .failure(.unavailable))
    }

    func testWhenDescribedThenItAsksForPermission() {
        let tool = SearchDownloadsBrowserTool(downloads: { [] })

        XCTAssertEqual(tool.name, "searchDownloads")
        XCTAssertEqual(tool.permissionMode, .ask)
    }

    private func item(_ fileName: String, from url: String, at seconds: TimeInterval) -> DownloadListItem {
        DownloadListItem(identifier: UUID(),
                         added: Date(timeIntervalSince1970: seconds),
                         modified: Date(timeIntervalSince1970: seconds),
                         downloadURL: URL(string: url)!,
                         websiteURL: nil,
                         fileName: fileName,
                         progress: nil,
                         fireWindowSession: nil,
                         destinationURL: URL(fileURLWithPath: "/Users/someone/Downloads/\(fileName)"),
                         destinationFileBookmarkData: nil,
                         tempURL: nil,
                         tempFileBookmarkData: nil,
                         error: nil)
    }
}

private extension BrowserToolResult {
    var results: [JSONValue]? {
        guard case .success(let value) = self else { return nil }
        return value["results"]?.arrayValue
    }
}
