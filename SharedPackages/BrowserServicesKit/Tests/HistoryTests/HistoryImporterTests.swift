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

    private let url = URL(string: "https://example.com/")!

    @MainActor
    func testWhenVisitsAreImported_ThenTheyAreAddedWithTitlesAndSaved() async throws {
        let (storingMock, coordinator) = await makeLoadedCoordinator()
        let parseResult = HistoryImporter.ParseResult(visits: [visit(url, title: "Example", hoursAgo: 2)], skipped: 3)

        let summary = try HistoryImporter.importVisits(parseResult, into: coordinator)

        XCTAssertEqual(summary, HistoryImporter.Summary(imported: 1, skipped: 3))
        let entry = try XCTUnwrap(coordinator.historyDictionary?[url])
        XCTAssertEqual(entry.title, "Example")
        XCTAssertEqual(entry.visits.count, 1)
        XCTAssertEqual(entry.lastVisit.timeIntervalSince1970, date(hoursAgo: 2).timeIntervalSince1970, accuracy: 0.001)
        await waitForSaves(storingMock) { $0.contains { $0.url == self.url && $0.title == "Example" } }
    }

    @MainActor
    func testWhenVisitIsOlderThanCutoff_ThenItIsNotImported() async throws {
        let (_, coordinator) = await makeLoadedCoordinator()

        let summary = try HistoryImporter.importVisits(parseResult([visit(url, hoursAgo: 48)]),
                                                             into: coordinator,
                                                             cutoff: date(hoursAgo: 24))

        XCTAssertEqual(summary, HistoryImporter.Summary(tooOld: 1))
        XCTAssertNil(coordinator.historyDictionary?[url])
    }

    @MainActor
    func testWhenSameVisitsAreImportedTwice_ThenVisitsAreNotDuplicated() async throws {
        let (_, coordinator) = await makeLoadedCoordinator()
        let parseResult = parseResult([visit(url, hoursAgo: 2)])
        _ = try HistoryImporter.importVisits(parseResult, into: coordinator)

        let summary = try HistoryImporter.importVisits(parseResult, into: coordinator)

        XCTAssertEqual(summary, HistoryImporter.Summary(alreadyInHistory: 1))
        XCTAssertEqual(coordinator.historyDictionary?[url]?.visits.count, 1)
    }

    @MainActor
    func testWhenBatchHasDuplicateVisits_ThenOnlyOneVisitIsAdded() async throws {
        let (_, coordinator) = await makeLoadedCoordinator()

        let summary = try HistoryImporter.importVisits(parseResult([visit(url, hoursAgo: 2), visit(url, hoursAgo: 2)]),
                                                             into: coordinator)

        XCTAssertEqual(summary, HistoryImporter.Summary(imported: 1, alreadyInHistory: 1))
        XCTAssertEqual(coordinator.historyDictionary?[url]?.visits.count, 1)
    }

    @MainActor
    func testWhenSameURLHasSeveralVisits_ThenLastVisitIsTheNewest() async throws {
        let (_, coordinator) = await makeLoadedCoordinator()

        _ = try HistoryImporter.importVisits(parseResult([visit(url, hoursAgo: 5), visit(url, hoursAgo: 1)]),
                                                   into: coordinator)

        let entry = try XCTUnwrap(coordinator.historyDictionary?[url])
        XCTAssertEqual(entry.visits.count, 2)
        XCTAssertEqual(entry.lastVisit.timeIntervalSince1970, date(hoursAgo: 1).timeIntervalSince1970, accuracy: 0.001)
    }

    @MainActor
    func testWhenHistoryIsNotLoaded_ThenImportThrows() {
        let coordinator = HistoryCoordinator(historyStoring: HistoryStoringMock())

        do {
            _ = try HistoryImporter.importVisits(parseResult([visit(url, hoursAgo: 1)]), into: coordinator)
            XCTFail("Expected import to throw")
        } catch HistoryImporter.ImportError.historyNotLoaded {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private let now = Date()

    private func date(hoursAgo: Double) -> Date {
        now.addingTimeInterval(-hoursAgo * 3600)
    }

    private func visit(_ url: URL, title: String? = nil, hoursAgo: Double) -> HistoryImporter.ImportedVisit {
        HistoryImporter.ImportedVisit(url: url, title: title, date: date(hoursAgo: hoursAgo))
    }

    private func parseResult(_ visits: [HistoryImporter.ImportedVisit]) -> HistoryImporter.ParseResult {
        HistoryImporter.ParseResult(visits: visits, skipped: 0)
    }

    @MainActor
    private func makeLoadedCoordinator() async -> (HistoryStoringMock, HistoryCoordinator) {
        let storingMock = HistoryStoringMock(cleanOldResult: .success(BrowsingHistory()), removeEntriesResult: .success(()))
        let coordinator = HistoryCoordinator(historyStoring: storingMock)
        await withCheckedContinuation { continuation in
            coordinator.loadHistory {
                continuation.resume()
            }
        }
        return (storingMock, coordinator)
    }

    @MainActor
    private func waitForSaves(_ storingMock: HistoryStoringMock, until condition: @escaping ([HistoryEntry]) -> Bool) async {
        let expectation = expectation(description: "Entry saved")
        storingMock.saveCompletion = {
            if condition(storingMock.savedHistoryEntries) {
                storingMock.saveCompletion = nil
                expectation.fulfill()
            }
        }
        if condition(storingMock.savedHistoryEntries) {
            storingMock.saveCompletion = nil
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2.0)
    }
}
