//
//  ChromiumHistoryImporterTests.swift
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

final class ChromiumHistoryImporterTests: XCTestCase {

    private enum Transition {
        static let link: Int64 = 0
        static let typed: Int64 = 1
        static let autoSubframe: Int64 = 3
        static let manualSubframe: Int64 = 4
        static let chainStart: Int64 = 0x10000000
        static let chainEnd: Int64 = 0x20000000
        static let serverRedirect: Int64 = 0x80000000
    }

    private let visitTime = ChromiumHistoryImporter.chromiumTime(for: Date(timeIntervalSince1970: 1_790_000_000))

    func testWhenConvertingChromiumTime_ThenUnixEpochMatches() {
        XCTAssertEqual(ChromiumHistoryImporter.chromiumTime(for: Date(timeIntervalSince1970: 0)), 11_644_473_600_000_000)
        XCTAssertEqual(ChromiumHistoryImporter.date(fromChromiumTime: 11_644_473_600_000_000), Date(timeIntervalSince1970: 0))
    }

    func testWhenVisitIsCompleteNavigation_ThenItIsImportedWithTitleAndDate() {
        let result = ChromiumHistoryImporter.parse([
            row("https://example.com/", title: "Example", transition: Transition.typed | Transition.chainStart | Transition.chainEnd)
        ])

        XCTAssertEqual(result.visits.count, 1)
        XCTAssertEqual(result.visits.first?.url, URL(string: "https://example.com/"))
        XCTAssertEqual(result.visits.first?.title, "Example")
        XCTAssertEqual(result.visits.first!.date.timeIntervalSince1970, 1_790_000_000, accuracy: 0.001)
        XCTAssertEqual(result.skipped, 0)
    }

    func testWhenVisitIsRedirectChain_ThenOnlyTheFinalHopIsImported() {
        let result = ChromiumHistoryImporter.parse([
            row("http://example.com/", transition: Transition.link | Transition.chainStart),
            row("https://example.com/", transition: Transition.link | Transition.serverRedirect | Transition.chainEnd)
        ])

        XCTAssertEqual(result.visits.map(\.url), [URL(string: "https://example.com/")!])
        XCTAssertEqual(result.skipped, 1)
    }

    func testWhenVisitIsSubframeOrNonWeb_ThenItIsSkipped() {
        let complete = Transition.chainStart | Transition.chainEnd
        let result = ChromiumHistoryImporter.parse([
            row("https://ads.example/frame", transition: Transition.autoSubframe | complete),
            row("https://example.com/embed", transition: Transition.manualSubframe | complete),
            row("chrome://settings/", transition: Transition.typed | complete),
            row("file:///Users/someone/page.html", transition: Transition.typed | complete)
        ])

        XCTAssertTrue(result.visits.isEmpty)
        XCTAssertEqual(result.skipped, 4)
    }

    private func row(_ url: String, title: String? = nil, transition: Int64) -> ChromiumHistoryImporter.Row {
        .init(url: url, title: title, visitTime: visitTime, transition: transition)
    }
}
