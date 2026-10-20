//
//  HistoryImporterTests.swift
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

final class HistoryImporterTests: XCTestCase {
    private let now = Date()
    private let newURL = URL(string: "https://new.example/")!
    private let oldURL = URL(string: "https://old.example/")!
    private let knownURL = URL(string: "https://known.example/")!

    @MainActor
    func testWhenVisitsAreImported_ThenOnlyNewVisitsWithinCutoffAreAddedAndEveryVisitIsCounted() throws {
        let coordinator = makeCoordinator(historyWithVisitOf: knownURL, hoursAgo: 1)
        let importer = HistoryImporter(historyCoordinator: coordinator, cutoff: { self.date(hoursAgo: 24) })
        let parseResult = HistoryImport.ParseResult(visits: [visit(newURL, title: "New", hoursAgo: 2),
                                                             visit(newURL, title: "New", hoursAgo: 2),
                                                             visit(knownURL, hoursAgo: 1),
                                                             visit(knownURL, hoursAgo: 3),
                                                             visit(oldURL, hoursAgo: 48)],
                                                    skipped: 3)

        let summary = try importer.importVisits(parseResult)

        XCTAssertEqual(summary, HistoryImport.Summary(imported: 2, alreadyInHistory: 2, tooOld: 1, skipped: 3))
        XCTAssertEqual(coordinator.addImportedVisitsCalls, [[visit(newURL, title: "New", hoursAgo: 2), visit(knownURL, hoursAgo: 3)]])
    }

    @MainActor
    func testWhenCutoffMovesAfterImporterIsCreated_ThenImportUsesTheCurrentCutoff() throws {
        var cutoff = date(hoursAgo: 24)
        let importer = HistoryImporter(historyCoordinator: makeCoordinator(historyWithVisitOf: knownURL, hoursAgo: 1), cutoff: { cutoff })
        cutoff = date(hoursAgo: 72)

        let summary = try importer.importVisits(HistoryImport.ParseResult(visits: [visit(oldURL, hoursAgo: 48)], skipped: 0))

        XCTAssertEqual(summary, HistoryImport.Summary(imported: 1))
    }

    @MainActor
    func testWhenHistoryIsNotLoaded_ThenImportThrows() {
        let coordinator = HistoryImportCoordinatorMock()
        let importer = HistoryImporter(historyCoordinator: coordinator)

        XCTAssertThrowsError(try importer.importVisits(HistoryImport.ParseResult(visits: [visit(newURL, hoursAgo: 1)], skipped: 0))) { error in
            guard case HistoryImport.Error.historyNotLoaded = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertTrue(coordinator.addImportedVisitsCalls.isEmpty)
    }

    // MARK: - Helpers

    private func date(hoursAgo: Double) -> Date {
        now.addingTimeInterval(-hoursAgo * 3600)
    }

    private func visit(_ url: URL, title: String? = nil, hoursAgo: Double) -> HistoryImport.Visit {
        HistoryImport.Visit(url: url, title: title, date: date(hoursAgo: hoursAgo))
    }

    @MainActor
    private func makeCoordinator(historyWithVisitOf url: URL, hoursAgo: Double) -> HistoryImportCoordinatorMock {
        let entry = HistoryEntry(url: url)
        entry.addVisit(at: date(hoursAgo: hoursAgo), tabID: nil)
        let coordinator = HistoryImportCoordinatorMock()
        coordinator.historyDictionary = [url: entry]
        return coordinator
    }
}
