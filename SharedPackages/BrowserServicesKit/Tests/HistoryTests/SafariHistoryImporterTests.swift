//
//  SafariHistoryImporterTests.swift
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

final class SafariHistoryImporterTests: XCTestCase {

    // MARK: - Parsing

    func testWhenExportIsValid_ThenWebVisitsAreParsedWithLatestVisitDate() throws {
        let data = historyJSON(rows: [
            row(url: "https://example.com/", title: "Example", time: date(hoursAgo: 1))
        ])

        let result = try SafariHistoryImporter.parse(data)

        XCTAssertEqual(result.visits.count, 1)
        XCTAssertEqual(result.visits.first?.url, URL(string: "https://example.com/"))
        XCTAssertEqual(result.visits.first?.title, "Example")
        XCTAssertEqual(result.visits.first!.date.timeIntervalSince1970, date(hoursAgo: 1).timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(result.skipped, 0)
    }

    func testWhenRowsAreRedirectsFailedLoadsOrNonWebURLs_ThenTheyAreSkipped() throws {
        let data = historyJSON(rows: [
            row(url: "https://example.com/", time: date(hoursAgo: 1)),
            row(url: "https://redirect.example/", time: date(hoursAgo: 1), extra: #""destination_url": "https://example.com/""#),
            row(url: "https://failed.example/", time: date(hoursAgo: 1), extra: #""latest_visit_was_load_failure": true"#),
            row(url: "file:///Users/someone/page.html", time: date(hoursAgo: 1)),
            #"{"url": "https://no-time.example/"}"#
        ])

        let result = try SafariHistoryImporter.parse(data)

        XCTAssertEqual(result.visits.map(\.url), [URL(string: "https://example.com/")!])
        XCTAssertEqual(result.skipped, 4)
    }

    func testWhenJSONIsNotSafariHistory_ThenParsingThrows() {
        let paymentCards = Data(#"{"metadata": {"data_type": "payment_cards"}, "history": []}"#.utf8)
        XCTAssertThrowsError(try SafariHistoryImporter.parse(paymentCards))

        let garbage = Data("not json".utf8)
        XCTAssertThrowsError(try SafariHistoryImporter.parse(garbage))
    }

    // MARK: - Importing

    @MainActor
    func testWhenVisitsAreImported_ThenTheyAreAddedWithTitlesAndSaved() async throws {
        let (storingMock, coordinator) = await makeLoadedCoordinator()
        let url = URL(string: "https://example.com/")!
        let visitDate = date(hoursAgo: 2)

        let summary = try await SafariHistoryImporter.importVisits(parse(rows: [row(url: url.absoluteString, title: "Example", time: visitDate)]),
                                                                   into: coordinator)

        XCTAssertEqual(summary.imported, 1)
        let entry = try XCTUnwrap(coordinator.historyDictionary?[url])
        XCTAssertEqual(entry.title, "Example")
        XCTAssertEqual(entry.visits.count, 1)
        XCTAssertEqual(entry.lastVisit.timeIntervalSince1970, visitDate.timeIntervalSince1970, accuracy: 0.001)

        await waitForSaves(storingMock) { $0.contains { $0.url == url && $0.title == "Example" } }
    }

    @MainActor
    func testWhenVisitIsOlderThanCutoff_ThenItIsNotImported() async throws {
        let (_, coordinator) = await makeLoadedCoordinator()

        let summary = try await SafariHistoryImporter.importVisits(parse(rows: [row(url: "https://old.example/", time: date(hoursAgo: 48))]),
                                                                   into: coordinator,
                                                                   cutoff: date(hoursAgo: 24))

        XCTAssertEqual(summary.tooOld, 1)
        XCTAssertEqual(summary.imported, 0)
        XCTAssertNil(coordinator.historyDictionary?[URL(string: "https://old.example/")!])
    }

    @MainActor
    func testWhenSameExportIsImportedTwice_ThenVisitsAreNotDuplicated() async throws {
        let (_, coordinator) = await makeLoadedCoordinator()
        let url = URL(string: "https://example.com/")!
        let parseResult = try parse(rows: [row(url: url.absoluteString, time: date(hoursAgo: 2))])

        _ = try await SafariHistoryImporter.importVisits(parseResult, into: coordinator)
        let second = try await SafariHistoryImporter.importVisits(parseResult, into: coordinator)

        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(second.alreadyInHistory, 1)
        XCTAssertEqual(coordinator.historyDictionary?[url]?.visits.count, 1)
    }

    @MainActor
    func testWhenExportHasDuplicateRows_ThenOnlyOneVisitIsAdded() async throws {
        let (_, coordinator) = await makeLoadedCoordinator()
        let url = URL(string: "https://example.com/")!
        let visitDate = date(hoursAgo: 2)

        let summary = try await SafariHistoryImporter.importVisits(parse(rows: [row(url: url.absoluteString, time: visitDate),
                                                                                row(url: url.absoluteString, time: visitDate)]),
                                                                   into: coordinator)

        XCTAssertEqual(summary.imported, 1)
        XCTAssertEqual(summary.alreadyInHistory, 1)
        XCTAssertEqual(coordinator.historyDictionary?[url]?.visits.count, 1)
    }

    @MainActor
    func testWhenSameURLHasSeveralVisits_ThenLastVisitIsTheNewest() async throws {
        let (_, coordinator) = await makeLoadedCoordinator()
        let url = URL(string: "https://example.com/")!

        _ = try await SafariHistoryImporter.importVisits(parse(rows: [row(url: url.absoluteString, time: date(hoursAgo: 5)),
                                                                      row(url: url.absoluteString, time: date(hoursAgo: 1))]),
                                                         into: coordinator)

        let entry = try XCTUnwrap(coordinator.historyDictionary?[url])
        XCTAssertEqual(entry.visits.count, 2)
        XCTAssertEqual(entry.lastVisit.timeIntervalSince1970, date(hoursAgo: 1).timeIntervalSince1970, accuracy: 0.001)
    }

    @MainActor
    func testWhenHistoryIsNotLoaded_ThenImportThrows() async throws {
        let coordinator = HistoryCoordinator(historyStoring: HistoryStoringMock())
        let parseResult = try parse(rows: [row(url: "https://example.com/", time: date(hoursAgo: 1))])

        do {
            _ = try await SafariHistoryImporter.importVisits(parseResult, into: coordinator)
            XCTFail("Expected import to throw")
        } catch SafariHistoryImporter.ImportError.historyNotLoaded {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private let now = Date()

    private func date(hoursAgo: Double) -> Date {
        now.addingTimeInterval(-hoursAgo * 3600)
    }

    private func row(url: String, title: String? = nil, time: Date, extra: String? = nil) -> String {
        var fields = [#""url": "\#(url)""#, #""time_usec": \#(Int64(time.timeIntervalSince1970 * 1_000_000))"#]
        if let title {
            fields.append(#""title": "\#(title)""#)
        }
        if let extra {
            fields.append(extra)
        }
        return "{\(fields.joined(separator: ", "))}"
    }

    private func historyJSON(rows: [String]) -> Data {
        Data("""
        {"metadata": {"browser_name": "Safari", "data_type": "history", "schema_version": 1},
         "history": [\(rows.joined(separator: ", "))]}
        """.utf8)
    }

    private func parse(rows: [String]) throws -> SafariHistoryImporter.ParseResult {
        try SafariHistoryImporter.parse(historyJSON(rows: rows))
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
