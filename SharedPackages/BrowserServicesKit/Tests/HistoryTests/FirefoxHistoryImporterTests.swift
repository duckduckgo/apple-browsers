//
//  FirefoxHistoryImporterTests.swift
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

import XCTest
@testable import History

final class FirefoxHistoryImporterTests: XCTestCase {

    private enum VisitType {
        static let link: Int64 = 1
        static let typed: Int64 = 2
        static let embed: Int64 = 4
        static let redirectPermanent: Int64 = 5
        static let download: Int64 = 7
        static let framedLink: Int64 = 8
    }

    private let visitDate = FirefoxHistoryImporter.firefoxTime(for: Date(timeIntervalSince1970: 1_790_000_000))

    func testWhenConvertingFirefoxTime_ThenItIsMicrosecondsSinceUnixEpoch() {
        XCTAssertEqual(FirefoxHistoryImporter.firefoxTime(for: Date(timeIntervalSince1970: 1)), 1_000_000)
    }

    func testWhenVisitIsVisiblePage_ThenItIsImportedWithTitleAndDate() {
        let result = FirefoxHistoryImporter.parse([
            row("https://example.com/", title: "Example", visitType: VisitType.link)
        ])

        XCTAssertEqual(result.visits.count, 1)
        XCTAssertEqual(result.visits.first?.url, URL(string: "https://example.com/"))
        XCTAssertEqual(result.visits.first?.title, "Example")
        XCTAssertEqual(result.visits.first!.date.timeIntervalSince1970, 1_790_000_000, accuracy: 0.001)
        XCTAssertEqual(result.skipped, 0)
    }

    func testWhenVisitIsRedirectChain_ThenOnlyTheVisibleDestinationIsImported() {
        let result = FirefoxHistoryImporter.parse([
            row("http://example.com/", visitType: VisitType.typed, hidden: true),
            row("https://example.com/", visitType: VisitType.redirectPermanent, hidden: true),
            row("https://www.example.com/", visitType: VisitType.redirectPermanent)
        ])

        XCTAssertEqual(result.visits.map(\.url), [URL(string: "https://www.example.com/")!])
        XCTAssertEqual(result.skipped, 2)
    }

    func testWhenVisitIsEmbedDownloadFramedOrNonWeb_ThenItIsSkipped() {
        let result = FirefoxHistoryImporter.parse([
            row("https://ads.example/frame", visitType: VisitType.embed),
            row("https://example.com/file.zip", visitType: VisitType.download),
            row("https://example.com/inner", visitType: VisitType.framedLink),
            row("about:preferences", visitType: VisitType.typed),
            row("file:///Users/someone/page.html", visitType: VisitType.typed)
        ])

        XCTAssertTrue(result.visits.isEmpty)
        XCTAssertEqual(result.skipped, 5)
    }

    private func row(_ url: String, title: String? = nil, visitType: Int64, hidden: Bool = false) -> FirefoxHistoryImporter.Row {
        .init(url: url, title: title, visitDate: visitDate, visitType: visitType, hidden: hidden)
    }
}
