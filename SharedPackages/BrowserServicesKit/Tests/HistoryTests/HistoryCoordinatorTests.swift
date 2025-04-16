//
//  HistoryCoordinatorTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import CoreData
import Combine
import Persistence
import Common
@testable import History

class HistoryCoordinatorTests: XCTestCase {

    var location: URL!

    override func setUp() {
        super.setUp()
        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(at: location)
    }

    func testWhenHistoryCoordinatorIsInitialized_ThenHistoryIsCleanedAndLoadedFromTheStore() {
        let (historyStoringMock, _) = HistoryCoordinator.aHistoryCoordinator

        XCTAssert(historyStoringMock.cleanOldCalled)
    }

    func testWhenAddVisitIsCalledBeforeHistoryIsLoadedFromStorage_ThenVisitIsIgnored() {
        let historyStoringMock = HistoryStoringMock()
        historyStoringMock.cleanOldResult = nil
        let historyCoordinator = HistoryCoordinator(historyStoring: historyStoringMock)

        let url = URL.duckDuckGo
        historyCoordinator.addVisit(of: url)

        XCTAssertFalse(historyStoringMock.saveCalled)
    }

    func testWhenAddVisitIsCalledAndUrlIsNotPartOfHistoryYet_ThenNewHistoryEntryIsAdded() {
        let (historyStoringMock, historyCoordinator) = HistoryCoordinator.aHistoryCoordinator

        let url = URL.duckDuckGo
        historyCoordinator.addVisit(of: url)

        XCTAssert(historyCoordinator.history!.contains(where: { entry in
            entry.url == url
        }))

        historyCoordinator.commitChanges(url: url)
        XCTAssert(historyStoringMock.saveCalled)
    }

    func testWhenAddVisitIsCalledAndUrlIsAlreadyPartOfHistory_ThenNoEntryIsAdded() {
        let (historyStoringMock, historyCoordinator) = HistoryCoordinator.aHistoryCoordinator

        let url = URL.duckDuckGo
        historyCoordinator.addVisit(of: url)
        historyCoordinator.addVisit(of: url)

        XCTAssert(historyCoordinator.history!.count == 1)
        XCTAssert(historyCoordinator.history!.first!.numberOfTotalVisits == 2)
        XCTAssert(historyCoordinator.history!.contains(where: { entry in
            entry.url == url
        }))

        historyCoordinator.commitChanges(url: url)
        XCTAssert(historyStoringMock.saveCalled)
    }

    func testWhenVisitIsAdded_ThenTitleIsNil() {
        let (_, historyCoordinator) = HistoryCoordinator.aHistoryCoordinator

        let url = URL.duckDuckGo
        historyCoordinator.addVisit(of: url)

        XCTAssertNil(historyCoordinator.history!.first?.title)
    }

    func testUpdateTitleIfNeeded() {
        let (historyStoringMock, historyCoordinator) = HistoryCoordinator.aHistoryCoordinator

        let url = URL.duckDuckGo
        historyCoordinator.addVisit(of: url)

        let title1 = "Title 1"
        historyCoordinator.updateTitleIfNeeded(title: title1, url: url)
        XCTAssertEqual(historyCoordinator.history!.first?.title, title1)

        let title2 = "Title 2"
        historyCoordinator.updateTitleIfNeeded(title: title2, url: url)
        XCTAssertEqual(historyCoordinator.history!.first?.title, title2)

        historyCoordinator.updateTitleIfNeeded(title: title2, url: url)

        historyCoordinator.commitChanges(url: url)
        XCTAssert(historyStoringMock.saveCalled)
    }

    func testWhenHistoryIsBurning_ThenHistoryIsCleanedIncludingFireproofDomains() {
        let burnAllFinished = expectation(description: "Burn All Finished")
        let (historyStoringMock, historyCoordinator) = HistoryCoordinator.aHistoryCoordinator

        let url1 = URL(string: "https://duckduckgo.com")!
        historyCoordinator.addVisit(of: url1)

        let url2 = URL(string: "https://test.duckduckgo.com")!
        historyCoordinator.addVisit(of: url2)

        let fireproofDomain = "wikipedia.org"
        let url3 = URL(string: "https://\(fireproofDomain)")!
        historyCoordinator.addVisit(of: url3)

        let url4 = URL(string: "https://subdomain.\(fireproofDomain)")!
        historyCoordinator.addVisit(of: url4)

        XCTAssert(historyCoordinator.history!.count == 4)

        historyCoordinator.burnAll {
            // We now clean the database directly so we don't burn by entry
            XCTAssert(historyStoringMock.removeEntriesArray.count == 0)

            // And we reset the entries dictionary
            XCTAssert(historyCoordinator.history!.count == 0)

            burnAllFinished.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }

    func testWhenBurningVisits_removesHistoryWhenVisitsCountHitsZero() {
        let (historyStoringMock, historyCoordinator) = HistoryCoordinator.aHistoryCoordinator
        historyStoringMock.removeEntriesResult = .success(())
        historyStoringMock.removeVisitsResult = .success(())

        let url1 = URL(string: "https://duckduckgo.com")!
        historyCoordinator.addVisit(of: url1)
        historyCoordinator.addVisit(of: url1)
        historyCoordinator.addVisit(of: url1)

        let visitsToBurn = Array(historyCoordinator.history!.first!.visits)

        let waiter = expectation(description: "Wait")
        historyCoordinator.burnVisits(visitsToBurn) {
            waiter.fulfill()
            XCTAssertEqual(historyStoringMock.removeEntriesArray.count, 1)
            XCTAssertEqual(historyStoringMock.removeEntriesArray.first!.url, url1)
        }
        waitForExpectations(timeout: 1.0)
    }

    func testWhenBurningVisits_removesVisitsFromTheStore() {
        let (historyStoringMock, historyCoordinator) = HistoryCoordinator.aHistoryCoordinator
        historyStoringMock.removeEntriesResult = .success(())
        historyStoringMock.removeVisitsResult = .success(())

        let url1 = URL(string: "https://duckduckgo.com")!
        historyCoordinator.addVisit(of: url1)
        historyCoordinator.addVisit(of: url1)
        historyCoordinator.addVisit(of: url1)

        let visitsToBurn = Array(historyCoordinator.history!.first!.visits)

        let waiter = expectation(description: "Wait")
        historyCoordinator.burnVisits(visitsToBurn) {
            waiter.fulfill()
            XCTAssertEqual(historyStoringMock.removeVisitsArray.count, 3)
        }
        waitForExpectations(timeout: 1.0)
    }

    func testWhenBurningVisits_DoesntDeleteHistoryBeforeVisits() {
        // Needs real store to catch assertion which can be raised by improper call ordering in the coordinator
        guard let context = loadDatabase(name: "Any")?.makeContext(concurrencyType: .privateQueueConcurrencyType) else {
            XCTFail("Failed to create context")
            return
        }

        let historyStore = HistoryStore(context: context, eventMapper: MockHistoryStoreEventMapper())
        let historyCoordinator = HistoryCoordinator(historyStoring: historyStore)
        historyCoordinator.loadHistory { }

        let url1 = URL(string: "https://duckduckgo.com")!
        historyCoordinator.addVisit(of: url1)
        historyCoordinator.addVisit(of: url1)
        historyCoordinator.addVisit(of: url1)

        let url2 = URL(string: "https://test.duckduckgo.com")!
        historyCoordinator.addVisit(of: url2)
        historyCoordinator.addVisit(of: url2)
        historyCoordinator.addVisit(of: url2)

        let visitsToBurn = Array(historyCoordinator.history!.first!.visits)

        let waiter = expectation(description: "Wait")
        historyCoordinator.burnVisits(visitsToBurn) {
            waiter.fulfill()
            // Simply don't raise an assertion
        }
        waitForExpectations(timeout: 1.0)
    }

    func testWhenHistoryIsBurningDomains_ThenHistoryIsCleanedForDomainsAndRemovedUrlsReturnedInCallback() {
        let burnAllFinished = expectation(description: "Burn All Finished")
        let (historyStoringMock, historyCoordinator) = HistoryCoordinator.aHistoryCoordinator

        let url0 = URL(string: "https://tobekept.com")!
        historyCoordinator.addVisit(of: url0)

        let url1 = URL(string: "https://duckduckgo.com")!
        historyCoordinator.addVisit(of: url1)

        let url2 = URL(string: "https://test.duckduckgo.com")!
        historyCoordinator.addVisit(of: url2)

        let fireproofDomain = "wikipedia.org"
        let url3 = URL(string: "https://\(fireproofDomain)")!
        historyCoordinator.addVisit(of: url3)

        let url4 = URL(string: "https://subdomain.\(fireproofDomain)")!
        historyCoordinator.addVisit(of: url4)

        let url5 = URL(string: "https://test.com")!
        historyCoordinator.addVisit(of: url5)

        XCTAssert(historyCoordinator.history!.count == 6)

        historyCoordinator.burnDomains(["duckduckgo.com", fireproofDomain], tld: TLD()) { urls in
            let expectedUrls = Set([url1, url2, url3, url4])

            XCTAssertEqual(Set(historyStoringMock.removeEntriesArray.map(\.url)), expectedUrls)
            XCTAssertEqual(urls, expectedUrls)

            burnAllFinished.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }

    func testWhenUrlIsMarkedAsFailedToLoad_ThenFailedToLoadFlagIsStored() {
        let (historyStoringMock, historyCoordinator) = HistoryCoordinator.aHistoryCoordinator

        let url = URL(string: "https://duckduckgo.com")!
        historyCoordinator.addVisit(of: url)

        historyCoordinator.markFailedToLoadUrl(url)
        historyCoordinator.commitChanges(url: url)

        XCTAssertEqual(url, historyStoringMock.savedHistoryEntries.last?.url)
        XCTAssert(historyStoringMock.savedHistoryEntries.last?.failedToLoad ?? false)
    }

    func testWhenUrlIsMarkedAsFailedToLoadAndItIsVisitedAgain_ThenFailedToLoadFlagIsSetToFalse() {
        let (historyStoringMock, historyCoordinator) = HistoryCoordinator.aHistoryCoordinator

        let url = URL(string: "https://duckduckgo.com")!
        historyCoordinator.addVisit(of: url)

        historyCoordinator.markFailedToLoadUrl(url)

        historyCoordinator.addVisit(of: url)

        historyCoordinator.commitChanges(url: url)
        XCTAssertEqual(url, historyStoringMock.savedHistoryEntries.last?.url)
        XCTAssertFalse(historyStoringMock.savedHistoryEntries.last?.failedToLoad ?? true)
    }

    func testWhenUrlHasNoTitle_ThenFetchingTitleReturnsNil() {
        let (_, historyCoordinator) = HistoryCoordinator.aHistoryCoordinator

        let url = URL.duckDuckGo
        historyCoordinator.addVisit(of: url)

        let title = historyCoordinator.title(for: url)

        XCTAssertNil(title)
    }

    func testWhenUrlHasTitle_ThenTitleIsReturned() {
        let (_, historyCoordinator) = HistoryCoordinator.aHistoryCoordinator

        let url = URL.duckDuckGo
        let title = "DuckDuckGo"

        historyCoordinator.addVisit(of: url)
        historyCoordinator.updateTitleIfNeeded(title: title, url: url)
        let fetchedTitle = historyCoordinator.title(for: url)

        XCTAssertEqual(title, fetchedTitle)
    }

    func loadDatabase(name: String) -> CoreDataDatabase? {
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "BrowsingHistory") else {
            return nil
        }
        let bookmarksDatabase = CoreDataDatabase(name: name, containerLocation: location, model: model)
        bookmarksDatabase.loadStore()
        return bookmarksDatabase
    }

    func testWhenRemoveUrlEntryCalledWithExistingUrl_ThenEntryIsRemovedAndNoError() {
        let (historyStoringMock, historyCoordinator) = HistoryCoordinator.aHistoryCoordinator

        let url = URL(string: "https://duckduckgo.com")!
        historyCoordinator.addVisit(of: url)

        XCTAssertTrue(historyCoordinator.history!.contains(where: { $0.url == url }))

        let removalExpectation = expectation(description: "Entry removed without error")
        historyCoordinator.removeUrlEntry(url) { error in
            XCTAssertNil(error, "Expected no error when removing an existing URL entry")
            removalExpectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        XCTAssertFalse(historyCoordinator.history!.contains(where: { $0.url == url }))
        XCTAssertTrue(historyStoringMock.removeEntriesCalled, "Expected removeEntries to be called")
        XCTAssertEqual(historyStoringMock.removeEntriesArray.count, 1)
        XCTAssertEqual(historyStoringMock.removeEntriesArray.first?.url, url)
    }

    func testWhenRemoveUrlEntryCalledWithNonExistingUrl_ThenEntryRemovalFailsWithNotAvailableError() {
        let (_, historyCoordinator) = HistoryCoordinator.aHistoryCoordinator

        let nonExistentUrl = URL(string: "https://nonexistent.com")!

        let removalExpectation = expectation(description: "Entry removal fails with notAvailable error")
        historyCoordinator.removeUrlEntry(nonExistentUrl) { error in
            XCTAssertNotNil(error, "Expected an error when removing a non-existent URL entry")
            XCTAssertEqual(error as? HistoryCoordinator.EntryRemovalError, .notAvailable, "Expected notAvailable error")
            removalExpectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

}

fileprivate extension HistoryCoordinator {

    static var aHistoryCoordinator: (HistoryStoringMock, HistoryCoordinator) {
        let historyStoringMock = HistoryStoringMock()
        historyStoringMock.cleanOldResult = .success(BrowsingHistory())
        historyStoringMock.removeEntriesResult = .success(())
        let historyCoordinator = HistoryCoordinator(historyStoring: historyStoringMock)
        historyCoordinator.loadHistory { }

        return (historyStoringMock, historyCoordinator)
    }

}

final class HistoryStoringMock: HistoryStoring {

    enum HistoryStoringMockError: Error {
        case defaultError
    }

    var cleanOldCalled = false
    var cleanOldResult: Result<BrowsingHistory, Error>?
    func cleanOld(until date: Date) -> Future<BrowsingHistory, Error> {
        cleanOldCalled = true
        return Future { [weak self] promise in
            guard let cleanOldResult = self?.cleanOldResult else {
                promise(.failure(HistoryStoringMockError.defaultError))
                return
            }

            promise(cleanOldResult)
        }
    }

    func load() {
        // no-op
    }

    var removeEntriesCalled = false
    var removeEntriesArray = [HistoryEntry]()
    var removeEntriesResult: Result<Void, Error>?
    func removeEntries(_ entries: [HistoryEntry]) -> Future<Void, Error> {
        removeEntriesCalled = true
        removeEntriesArray = entries
        return Future { [weak self] promise in
            guard let removeEntriesResult = self?.removeEntriesResult else {
                promise(.failure(HistoryStoringMockError.defaultError))
                return
            }
            promise(removeEntriesResult)
        }
    }

    var removeVisitsCalled = false
    var removeVisitsArray = [Visit]()
    var removeVisitsResult: Result<Void, Error>?
    func removeVisits(_ visits: [Visit]) -> Future<Void, Error> {
        removeVisitsCalled = true
        removeVisitsArray = visits
        return Future { [weak self] promise in
            guard let removeVisitsResult = self?.removeVisitsResult else {
                promise(.failure(HistoryStoringMockError.defaultError))
                return
            }
            promise(removeVisitsResult)
        }
    }

    var saveCalled = false
    var savedHistoryEntries = [HistoryEntry]()
    func save(entry: HistoryEntry) -> Future<[(id: Visit.ID, date: Date)], Error> {
        saveCalled = true
        savedHistoryEntries.append(entry)
        for visit in entry.visits {
            // swiftlint:disable:next legacy_random
            visit.identifier = URL(string: "x-coredata://FBEAB2C4-8C32-4F3F-B34F-B79F293CDADD/VisitManagedObject/\(arc4random())")
        }

        return Future { promise in
            let result = entry.visits.map { ($0.identifier!, $0.date) }
            promise(.success(result))
        }
    }

}

class MockHistoryStoreEventMapper: EventMapping<HistoryStore.HistoryStoreEvents> {
    public init() {
        super.init { _, _, _, _ in
            // no-op
        }
    }

    override init(mapping: @escaping EventMapping<HistoryStore.HistoryStoreEvents>.Mapping) {
        fatalError("Use init()")
    }
}
