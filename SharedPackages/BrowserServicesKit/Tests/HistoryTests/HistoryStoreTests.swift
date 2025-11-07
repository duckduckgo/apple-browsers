//
//  HistoryStoreTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import XCTest
import Combine
import class Persistence.CoreDataDatabase
@testable import History
import Common
import CoreData

final class HistoryStoreTests: XCTestCase {

    private var context: NSManagedObjectContext!
    private var historyStore: HistoryStore!
    private var location: URL!

    override func setUp() {
        super.setUp()
        let model = CoreDataDatabase.loadModel(from: bundle, named: "BrowsingHistory")!
        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = CoreDataDatabase(name: className, containerLocation: location, model: model)
        database.loadStore { _, error in
            if let e = error {
                XCTFail("Could not load store: \(e.localizedDescription)")
            }
        }
        context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        historyStore = HistoryStore(context: context, eventMapper: MockHistoryStoreEventMapper())
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: location)
        context = nil
        historyStore = nil
        try super.tearDownWithError()
    }

    func testWhenHistoryEntryIsSavedMultipleTimes_ThenTheNewestValueMustBeLoadedFromStore() async throws {
        let historyEntry = HistoryEntry(identifier: UUID(),
                                        url: URL.duckDuckGo,
                                        title: "Test",
                                        numberOfVisits: 1,
                                        lastVisit: Date(),
                                        visits: [])
        let firstSavingExpectation = self.expectation(description: "Saving")
        try await save(entry: historyEntry, expectation: firstSavingExpectation)

        let newTitle = "New Title"
        historyEntry.title = newTitle
        let secondSavingExpectation = self.expectation(description: "Saving")
        try await save(entry: historyEntry, expectation: secondSavingExpectation)
        await fulfillment(of: [firstSavingExpectation, secondSavingExpectation], timeout: 2)

        try await cleanOldAndWait(cleanUntil: Date(timeIntervalSince1970: 0)) { history in
            XCTAssertEqual(history.count, 1)
            XCTAssertEqual(history.first!.title, newTitle)
        }
    }

    func testWhenCleanOldIsCalled_ThenOlderEntriesThanDateAreCleaned() async throws {
        let toBeKeptIdentifier = UUID()
        let newHistoryEntry = HistoryEntry(identifier: toBeKeptIdentifier,
                                           url: URL(string: "wikipedia.org")!,
                                           title: nil,
                                           numberOfVisits: 1,
                                           lastVisit: Date(),
                                           visits: [])
        let savingExpectation = self.expectation(description: "Saving")
        try await save(entry: newHistoryEntry, expectation: savingExpectation)

        var toBeDeleted: [HistoryEntry] = []
        for i in 0..<150 {
            let identifier = UUID()
            let visitDate = Date(timeIntervalSince1970: 1000.0 * Double(i))
            let visit = Visit(date: visitDate)
            let toRemoveHistoryEntry = HistoryEntry(identifier: identifier,
                                                    url: URL(string: "wikipedia.org/\(identifier)")!,
                                                    title: nil,
                                                    numberOfVisits: 1,
                                                    lastVisit: visitDate,
                                                    visits: [visit])
            visit.historyEntry = toRemoveHistoryEntry
            try await save(entry: toRemoveHistoryEntry)
            toBeDeleted.append(toRemoveHistoryEntry)
        }

        await fulfillment(of: [savingExpectation], timeout: 2)
        try await cleanOldAndWait(cleanUntil: .weekAgo) { history in
            XCTAssertEqual(history.count, 1)
            XCTAssertEqual(history.first!.identifier, toBeKeptIdentifier)
        }
    }

    func testWhenRemoveEntriesIsCalled_ThenEntriesMustBeCleaned() async throws {
        let visitDate = Date(timeIntervalSince1970: 1234)
        let visit = Visit(date: visitDate)
        let firstSavingExpectation = self.expectation(description: "Saving")
        let toBeKept = try await saveNewHistoryEntry(including: [visit], lastVisit: visitDate, expectation: firstSavingExpectation)

        var toBeDeleted: [HistoryEntry] = []
        for _ in 0..<150 {
            let identifier = UUID()
            let visitDate = Date()
            let visit = Visit(date: visitDate)
            let toRemoveHistoryEntry = HistoryEntry(identifier: identifier,
                                                    url: URL(string: "wikipedia.org/\(identifier)")!,
                                                    title: nil,
                                                    numberOfVisits: 1,
                                                    lastVisit: visitDate,
                                                    visits: [visit])
            visit.historyEntry = toRemoveHistoryEntry
            try await save(entry: toRemoveHistoryEntry)
            toBeDeleted.append(toRemoveHistoryEntry)
        }

        try await removeEntriesAndWait(toBeDeleted)
        await fulfillment(of: [firstSavingExpectation], timeout: 2)

        context.performAndWait {
            let request = BrowsingHistoryEntryManagedObject.fetchRequest()
            do {
                let results = try context.fetch(request)
                XCTAssertEqual(results.first?.identifier, toBeKept.identifier)
                XCTAssertEqual(results.count, 1)
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }

    func removeEntriesAndWait(_ entries: [HistoryEntry], file: StaticString = #file, line: UInt = #line) async throws {
        do {
            try await historyStore.removeEntries(entries)
        } catch {
            XCTFail("Loading of history failed - \(error.localizedDescription)", file: file, line: line)
            throw error
        }
    }

    func testWhenRemoveEntriesIsCalled_visitsCascadeDelete() async throws {
        var toBeDeleted = [Visit]()
        for j in 0..<10 {
            let visitDate = Date(timeIntervalSince1970: Double(j))
            let visit = Visit(date: visitDate)
            toBeDeleted.append(visit)
        }
        let history = try await saveNewHistoryEntry(including: toBeDeleted, lastVisit: toBeDeleted.last!.date)

        try await removeEntriesAndWait([history])

        context.performAndWait {
            let request = PageVisitManagedObject.fetchRequest()
            do {
                let results = try context.fetch(request)
                XCTAssertEqual(results.count, 0)
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }

    func testWhenRemoveVisitsIsCalled_ThenVisitsMustBeCleaned() async throws {
        let visitDate = Date(timeIntervalSince1970: 1234)
        let toBeKept = Visit(date: visitDate)
        let firstSavingExpectation = self.expectation(description: "Saving")
        let toBeKeptsHistory = try await saveNewHistoryEntry(including: [toBeKept], lastVisit: visitDate, expectation: firstSavingExpectation)

        var toBeDeleted: [Visit] = []
        var historiesToPreventFromDeallocation = [HistoryEntry]()
        func addVisitsToEntry(_ visits: [Visit]) async throws {
            let history = try await saveNewHistoryEntry(including: visits, lastVisit: visits.last!.date)
            historiesToPreventFromDeallocation.append(history)
        }

        for _ in 0..<3 {
            var visits = [Visit]()
            for j in 0..<50 {
                let visitDate = Date(timeIntervalSince1970: Double(j))
                let visit = Visit(date: visitDate)
                visits.append(visit)
                toBeDeleted.append(visit)
            }
            try await addVisitsToEntry(visits)
        }

        do {
            try await historyStore.removeVisits(toBeDeleted)
        } catch {
            XCTFail("Loading of history failed - \(error.localizedDescription)")
        }
        withExtendedLifetime(historiesToPreventFromDeallocation) { _ in }
        await fulfillment(of: [firstSavingExpectation], timeout: 2)

        context.performAndWait {
            let request = PageVisitManagedObject.fetchRequest()
            do {
                let results = try context.fetch(request)
                XCTAssertEqual(results.first?.historyEntry?.identifier, toBeKeptsHistory.identifier)
                XCTAssertEqual(results.first?.date, toBeKept.date)
                XCTAssertEqual(results.count, 1)
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }

    func testWhenCleanOldIsCalled_ThenFollowingSaveShouldSucceed() async throws {
        let oldVisitDate = Date(timeIntervalSince1970: 0)
        let newVisitDate = Date(timeIntervalSince1970: 12345)

        let oldVisit = Visit(date: oldVisitDate)
        let newVisit = Visit(date: newVisitDate)

        let firstSavingExpectation = self.expectation(description: "Saving")
        _ = try await saveNewHistoryEntry(including: [oldVisit, newVisit],
                                         lastVisit: newVisitDate,
                                         expectation: firstSavingExpectation)

        try await cleanOldAndWait(cleanUntil: Date(timeIntervalSince1970: 1)) { history in
            XCTAssertEqual(history.count, 1)
            for entry in history {
                XCTAssertEqual(entry.visits.count, 1)
            }
        }

        // This should not fail, but apparently internal version of objects is broken after BatchDelete request causing merge failure.
        let secondSavingExpectation = self.expectation(description: "Saving")
        _ = try await saveNewHistoryEntry(including: [oldVisit, newVisit],
                                         lastVisit: newVisitDate,
                                         expectation: secondSavingExpectation)

        await fulfillment(of: [firstSavingExpectation, secondSavingExpectation], timeout: 2)
    }

    func testWhenRemoveVisitsIsCalled_ThenFollowingSaveShouldSucceed() async throws {
        let oldVisitDate = Date(timeIntervalSince1970: 0)
        let newVisitDate = Date(timeIntervalSince1970: 12345)

        let oldVisit = Visit(date: oldVisitDate)
        let newVisit = Visit(date: newVisitDate)

        let firstSavingExpectation = self.expectation(description: "Saving")
        let history = try await saveNewHistoryEntry(including: [oldVisit, newVisit],
                                                    lastVisit: newVisitDate,
                                                    expectation: firstSavingExpectation)

        do {
            try await historyStore.removeVisits([oldVisit])
        } catch {
            XCTFail("Loading of history failed - \(error.localizedDescription)")
        }
        withExtendedLifetime(history) { _ in }

        let secondSavingExpectation = self.expectation(description: "Saving")
        try await saveNewHistoryEntry(including: [oldVisit, newVisit],
                                      lastVisit: newVisitDate,
                                      expectation: secondSavingExpectation)

        await fulfillment(of: [firstSavingExpectation, secondSavingExpectation], timeout: 2)
    }

    func testWhenRemoveEntriesIsCalled_ThenFollowingSaveShouldSucceed() async throws {
        let oldVisitDate = Date(timeIntervalSince1970: 0)
        let newVisitDate = Date(timeIntervalSince1970: 12345)

        let oldVisit = Visit(date: oldVisitDate)
        let newVisit = Visit(date: newVisitDate)

        let firstSavingExpectation = self.expectation(description: "Saving")
        let historyEntry = try await saveNewHistoryEntry(including: [oldVisit, newVisit],
                                                         lastVisit: newVisitDate,
                                                         expectation: firstSavingExpectation)

        try await removeEntriesAndWait([historyEntry])

        let secondSavingExpectation = self.expectation(description: "Saving")
        try await saveNewHistoryEntry(including: [oldVisit, newVisit],
                                      lastVisit: newVisitDate,
                                      expectation: secondSavingExpectation)

        await fulfillment(of: [firstSavingExpectation, secondSavingExpectation], timeout: 2)
    }

    private func cleanOldAndWait(cleanUntil date: Date, assertion: @escaping (BrowsingHistory) -> Void, file: StaticString = #file, line: UInt = #line) async throws {
        do {
            let history = try await historyStore.cleanOld(until: date)
            assertion(history)
        } catch {
            XCTFail("Loading of history failed - \(error.localizedDescription)", file: file, line: line)
            throw error
        }
    }

    @discardableResult
    private func saveNewHistoryEntry(including visits: [Visit], lastVisit: Date, expectation: XCTestExpectation? = nil, file: StaticString = #file, line: UInt = #line) async throws -> HistoryEntry {
        let historyEntry = HistoryEntry(identifier: UUID(),
                                        url: URL.duckDuckGo,
                                        title: nil,
                                        numberOfVisits: visits.count,
                                        lastVisit: lastVisit,
                                        visits: visits)
        for visit in visits {
            visit.historyEntry = historyEntry
        }
        try await save(entry: historyEntry, expectation: expectation, file: file, line: line)
        return historyEntry
    }

    private func save(entry: HistoryEntry, expectation: XCTestExpectation? = nil, file: StaticString = #file, line: UInt = #line) async throws {
        do {
            _ = try await historyStore.save(entry: entry)
            expectation?.fulfill()
        } catch {
            XCTFail("Saving of history entry failed - \(error.localizedDescription)", file: file, line: line)
            throw error
        }
    }
}

fileprivate extension HistoryEntry {

    convenience init(identifier: UUID, url: URL, title: String?, numberOfVisits: Int, lastVisit: Date, visits: [Visit]) {
        self.init(identifier: identifier,
                  url: url,
                  title: title,
                  failedToLoad: false,
                  numberOfTotalVisits: numberOfVisits,
                  lastVisit: lastVisit,
                  visits: Set(visits),
                  numberOfTrackersBlocked: 0,
                  blockedTrackingEntities: .init(),
                  trackersFound: false)
    }

}
