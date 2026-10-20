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
    func testWhenVisitsAreImported_ThenOnlyNewVisitsWithinCutoffAreAddedAndEveryVisitIsCounted() async throws {
        let coordinator = makeCoordinator(historyWithVisitOf: knownURL, hoursAgo: 1)
        let importer = HistoryImporter(historyCoordinator: coordinator, cutoff: { self.date(hoursAgo: 24) })
        let parseResult = HistoryImport.ParseResult(visits: [visit(newURL, title: "New", hoursAgo: 2),
                                                             visit(newURL, title: "New", hoursAgo: 2),
                                                             visit(knownURL, hoursAgo: 1),
                                                             visit(knownURL, hoursAgo: 3),
                                                             visit(oldURL, hoursAgo: 48)],
                                                    skipped: 3)

        let summary = try await importer.importVisits(parseResult)

        XCTAssertEqual(summary, HistoryImport.Summary(imported: 2, alreadyInHistory: 2, tooOld: 1, skipped: 3))
        XCTAssertEqual(coordinator.addImportedVisitsCalls, [[visit(newURL, title: "New", hoursAgo: 2), visit(knownURL, hoursAgo: 3)]])
    }

    @MainActor
    func testWhenCutoffMovesAfterImporterIsCreated_ThenImportUsesTheCurrentCutoff() async throws {
        var cutoff = date(hoursAgo: 24)
        let importer = HistoryImporter(historyCoordinator: makeCoordinator(historyWithVisitOf: knownURL, hoursAgo: 1), cutoff: { cutoff })
        cutoff = date(hoursAgo: 72)

        let summary = try await importer.importVisits(HistoryImport.ParseResult(visits: [visit(oldURL, hoursAgo: 48)], skipped: 0))

        XCTAssertEqual(summary, HistoryImport.Summary(imported: 1))
    }

    @MainActor
    func testWhenHistoryIsNotLoaded_ThenImportThrows() async {
        await assertImportIsRejected(coordinator: HistoryCoordinatingMock())
    }

    @MainActor
    func testWhenDictionaryExistsButLoadingHasNotFinished_ThenImportThrows() async {
        let coordinator = HistoryCoordinatingMock()
        coordinator.historyDictionary = [:]

        await assertImportIsRejected(coordinator: coordinator)
    }

    @MainActor
    func testWhenSavingIsPending_ThenImportDoesNotReturnASummary() async throws {
        let coordinator = makeCoordinator(historyWithVisitOf: knownURL, hoursAgo: 1)
        let saveStarted = expectation(description: "Save started")
        var saveContinuation: CheckedContinuation<Void, Never>?
        coordinator.addImportedVisitsHandler = {
            await withCheckedContinuation {
                saveContinuation = $0
                saveStarted.fulfill()
            }
        }
        let importer = HistoryImporter(historyCoordinator: coordinator)
        var didReturnSummary = false
        let task = Task {
            let summary = try await importer.importVisits(HistoryImport.ParseResult(visits: [visit(newURL, hoursAgo: 1)], skipped: 0))
            didReturnSummary = true
            return summary
        }

        await fulfillment(of: [saveStarted], timeout: 1)
        XCTAssertFalse(didReturnSummary)
        try XCTUnwrap(saveContinuation).resume()
        let summary = try await task.value
        XCTAssertEqual(summary.imported, 1)
    }

    @MainActor
    func testWhenSavingFails_ThenImportPropagatesTheError() async {
        let coordinator = makeCoordinator(historyWithVisitOf: knownURL, hoursAgo: 1)
        coordinator.addImportedVisitsHandler = { throw HistoryStoringMock.HistoryStoringMockError.defaultError }
        let importer = HistoryImporter(historyCoordinator: coordinator)

        do {
            _ = try await importer.importVisits(HistoryImport.ParseResult(visits: [visit(newURL, hoursAgo: 1)], skipped: 0))
            XCTFail("Import should propagate the save failure")
        } catch HistoryStoringMock.HistoryStoringMockError.defaultError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    private func assertImportIsRejected(coordinator: HistoryCoordinatingMock, file: StaticString = #filePath, line: UInt = #line) async {
        let importer = HistoryImporter(historyCoordinator: coordinator)
        do {
            _ = try await importer.importVisits(HistoryImport.ParseResult(visits: [visit(newURL, hoursAgo: 1)], skipped: 0))
            XCTFail("Import should be rejected before history finishes loading", file: file, line: line)
        } catch HistoryImport.Error.historyNotLoaded {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
        XCTAssertTrue(coordinator.addImportedVisitsCalls.isEmpty, file: file, line: line)
    }

    // MARK: - Helpers

    private func date(hoursAgo: Double) -> Date {
        now.addingTimeInterval(-hoursAgo * 3600)
    }

    private func visit(_ url: URL, title: String? = nil, hoursAgo: Double) -> HistoryImport.Visit {
        HistoryImport.Visit(url: url, title: title, date: date(hoursAgo: hoursAgo))
    }

    @MainActor
    private func makeCoordinator(historyWithVisitOf url: URL, hoursAgo: Double) -> HistoryCoordinatingMock {
        let entry = HistoryEntry(url: url)
        _ = entry.addVisit(at: date(hoursAgo: hoursAgo), tabID: nil)
        let coordinator = HistoryCoordinatingMock()
        coordinator.historyDictionary = [url: entry]
        coordinator.isHistoryLoaded = true
        return coordinator
    }
}
