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

    @MainActor
    func testWhenHistoryCoordinatorIsInitialized_ThenHistoryIsCleanedAndLoadedFromTheStore() async {
        let historyStoringMock = HistoryStoringMock()
        historyStoringMock.cleanOldResult = .success(BrowsingHistory())
        let historyCoordinator = HistoryCoordinator(historyStoring: historyStoringMock)

        let expectation = expectation(description: "History loaded")
        historyCoordinator.loadHistory {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(historyStoringMock.cleanOldCalled)
    }

    @MainActor
    func testWhenAddVisitIsCalledBeforeHistoryIsLoadedFromStorage_ThenVisitIsIgnored() {
        let historyStoringMock = HistoryStoringMock()
        historyStoringMock.cleanOldResult = nil
        let historyCoordinator = HistoryCoordinator(historyStoring: historyStoringMock)

        let url = URL.duckDuckGo
        historyCoordinator.addVisit(of: url)

        XCTAssertFalse(historyStoringMock.saveCalled)
    }

    @MainActor
    func testWhenAddVisitIsCalledAndUrlIsNotPartOfHistoryYet_ThenNewHistoryEntryIsAdded() async {
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

        let url = URL.duckDuckGo
        historyCoordinator.addVisit(of: url)

        XCTAssertTrue(historyCoordinator.history!.contains(where: { entry in
            entry.url == url
        }))

        let expectation = expectation(description: "Changes committed")
        historyStoringMock.saveCompletion = {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertTrue(historyStoringMock.saveCalled)
    }

    @MainActor
    func testWhenAddVisitIsCalledAndUrlIsAlreadyPartOfHistory_ThenNoEntryIsAdded() async {
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

        let url = URL.duckDuckGo
        historyCoordinator.addVisit(of: url)
        historyCoordinator.addVisit(of: url)

        XCTAssertEqual(historyCoordinator.history!.count, 1)
        XCTAssertEqual(historyCoordinator.history!.first!.numberOfTotalVisits, 2)
        XCTAssertTrue(historyCoordinator.history!.contains(where: { entry in
            entry.url == url
        }))

        let expectation = expectation(description: "Changes committed")
        expectation.expectedFulfillmentCount = 2
        historyStoringMock.saveCompletion = {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertTrue(historyStoringMock.saveCalled)
    }

    @MainActor
    func testWhenVisitIsAdded_ThenTitleIsNil() async {
        let (_, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

        let url = URL.duckDuckGo
        historyCoordinator.addVisit(of: url)

        XCTAssertNil(historyCoordinator.history!.first?.title)
    }

    @MainActor
    func testUpdateTitleIfNeeded() async {
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

        let url = URL.duckDuckGo
        historyCoordinator.addVisit(of: url)

        let title1 = "Title 1"
        historyCoordinator.updateTitleIfNeeded(title: title1, url: url)
        XCTAssertEqual(historyCoordinator.history!.first?.title, title1)

        let title2 = "Title 2"
        historyCoordinator.updateTitleIfNeeded(title: title2, url: url)
        XCTAssertEqual(historyCoordinator.history!.first?.title, title2)

        historyCoordinator.updateTitleIfNeeded(title: title2, url: url)

        let expectation = expectation(description: "Changes committed")
        historyStoringMock.saveCompletion = {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertTrue(historyStoringMock.saveCalled)
    }

    @MainActor
    func testWhenImportedVisitsAreAdded_ThenEachEntryGetsItsNewestTitleAndIsSavedOnce() async throws {
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()
        let newest = importedVisit(title: "Newest", hoursAgo: 0)
        let older = importedVisit(title: "Older", hoursAgo: 1)
        let other = importedVisit(of: URL(string: "https://example.com/")!, title: "Other", hoursAgo: 2)
        try await historyCoordinator.addImportedVisits([newest, older, other])

        let entry = try XCTUnwrap(historyCoordinator.historyDictionary?[newest.url])
        XCTAssertEqual(entry.visits.count, 2)
        XCTAssertEqual(entry.lastVisit, newest.date)
        XCTAssertEqual(entry.title, "Newest")
        XCTAssertEqual(historyStoringMock.savedHistoryEntries.count, 2)
        XCTAssertTrue(entry.visits.allSatisfy { $0.identifier != nil })
        XCTAssertEqual(Set(historyStoringMock.savedHistoryEntries.map(\.url)), [newest.url, other.url])
    }

    @MainActor
    func testWhenImportedVisitIsOlderThanLocalVisit_ThenLocalTitleIsKept() async throws {
        let (_, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()
        historyCoordinator.addVisit(of: .duckDuckGo)
        historyCoordinator.updateTitleIfNeeded(title: "Local", url: .duckDuckGo)

        try await historyCoordinator.addImportedVisits([importedVisit(title: "Imported", hoursAgo: 1)])

        XCTAssertEqual(historyCoordinator.historyDictionary?[.duckDuckGo]?.visits.count, 2)
        XCTAssertEqual(historyCoordinator.historyDictionary?[.duckDuckGo]?.title, "Local")
    }

    @MainActor
    func testWhenHistoryIsLoading_ThenImportIsRejectedUntilLoadingCompletes() async throws {
        let store = HistoryStoringMock()
        let coordinator = HistoryCoordinator(historyStoring: store)
        let loadStarted = expectation(description: "Load started")
        let loadFinished = expectation(description: "Load finished")
        var loadContinuation: CheckedContinuation<BrowsingHistory, Error>?
        store.cleanOldHandler = {
            try await withCheckedThrowingContinuation {
                loadContinuation = $0
                loadStarted.fulfill()
            }
        }
        let imported = importedVisit(title: "Known", hoursAgo: 1)
        let existing = HistoryEntry(url: imported.url)
        _ = existing.addVisit(at: imported.date, tabID: nil)
        let importer = HistoryImporter(historyCoordinator: coordinator)
        let parseResult = HistoryImport.ParseResult(visits: [imported], skipped: 0)
        coordinator.loadHistory { loadFinished.fulfill() }

        await fulfillment(of: [loadStarted], timeout: 1)
        XCTAssertNotNil(coordinator.historyDictionary)
        XCTAssertFalse(coordinator.isHistoryLoaded)
        do {
            _ = try await importer.importVisits(parseResult)
            XCTFail("Import should be rejected while history is loading")
        } catch HistoryImport.Error.historyNotLoaded {
            // Expected.
        }
        XCTAssertFalse(store.saveCalled)

        try XCTUnwrap(loadContinuation).resume(returning: [existing])
        await fulfillment(of: [loadFinished], timeout: 1)
        XCTAssertTrue(coordinator.isHistoryLoaded)
        let summary = try await importer.importVisits(parseResult)
        XCTAssertEqual(summary, HistoryImport.Summary(alreadyInHistory: 1))
        XCTAssertFalse(store.saveCalled)
    }

    @MainActor
    func testWhenHistoryLoadingFails_ThenImportRemainsUnavailable() async throws {
        let store = HistoryStoringMock(cleanOldResult: .failure(HistoryStoringMock.HistoryStoringMockError.defaultError))
        let coordinator = HistoryCoordinator(historyStoring: store)
        let loadFinished = expectation(description: "Load finished")
        coordinator.loadHistory { loadFinished.fulfill() }
        await fulfillment(of: [loadFinished], timeout: 1)

        XCTAssertFalse(coordinator.isHistoryLoaded)
        do {
            try await coordinator.addImportedVisits([importedVisit(title: "New", hoursAgo: 1)])
            XCTFail("Import should be rejected after loading fails")
        } catch HistoryImport.Error.historyNotLoaded {
            // Expected.
        }
        XCTAssertFalse(store.saveCalled)
    }

    @MainActor
    func testWhenImportSaveIsPending_ThenImportWaitsAndRejectsAnotherImport() async throws {
        let (store, coordinator) = await HistoryCoordinator.aHistoryCoordinator()
        let saveStarted = expectation(description: "Save started")
        var saveContinuation: CheckedContinuation<Void, Error>?
        store.saveHandler = { _ in
            try await withCheckedThrowingContinuation {
                saveContinuation = $0
                saveStarted.fulfill()
            }
        }
        let imported = importedVisit(title: "New", hoursAgo: 1)
        var didFinishImport = false
        let task = Task {
            try await coordinator.addImportedVisits([imported])
            didFinishImport = true
        }

        await fulfillment(of: [saveStarted], timeout: 1)
        XCTAssertFalse(didFinishImport)
        do {
            try await coordinator.addImportedVisits([])
            XCTFail("Overlapping imports must not report unsaved visits as already imported")
        } catch HistoryImport.Error.importInProgress {
            // Expected.
        }
        try XCTUnwrap(saveContinuation).resume()
        try await task.value
        let entry = try XCTUnwrap(coordinator.historyDictionary?[imported.url])
        XCTAssertTrue(entry.visits.allSatisfy { $0.identifier != nil })
    }

    @MainActor
    func testWhenImportPartiallyFails_ThenRetryImportsOnlyTheUnsavedVisits() async throws {
        let (store, coordinator) = await HistoryCoordinator.aHistoryCoordinator()
        var saveCount = 0
        store.saveHandler = { _ in
            saveCount += 1
            if saveCount == 2 {
                throw HistoryStoringMock.HistoryStoringMockError.defaultError
            }
        }
        let visits = [importedVisit(title: "First", hoursAgo: 1),
                      importedVisit(of: URL(string: "https://example.com/")!, title: "Second", hoursAgo: 2),
                      importedVisit(of: URL(string: "https://other.example/")!, title: "Third", hoursAgo: 3)]
        let importer = HistoryImporter(historyCoordinator: coordinator)
        let parseResult = HistoryImport.ParseResult(visits: visits, skipped: 0)

        do {
            _ = try await importer.importVisits(parseResult)
            XCTFail("Import should propagate the save failure")
        } catch HistoryStoringMock.HistoryStoringMockError.defaultError {
            // Expected.
        }
        let savedURL = try XCTUnwrap(store.savedHistoryEntries.first?.url)
        XCTAssertEqual(Set(try XCTUnwrap(coordinator.historyDictionary).keys), [savedURL])
        XCTAssertEqual(saveCount, 2)

        let summary = try await importer.importVisits(parseResult)
        XCTAssertEqual(summary, HistoryImport.Summary(imported: 2, alreadyInHistory: 1))
        XCTAssertEqual(coordinator.historyDictionary?.count, 3)
        XCTAssertEqual(saveCount, 4)
    }

    @MainActor
    func testWhenImportSaveFails_ThenExistingTitleAndVisitCountsAreRestored() async throws {
        let existing = HistoryEntry(url: .duckDuckGo)
        let originalDate = Date().addingTimeInterval(-3 * 3600)
        existing.addVisit(at: originalDate, tabID: nil).savingState = .saved
        existing.title = "Original"
        let (store, coordinator) = await HistoryCoordinator.aHistoryCoordinator(history: [existing])
        store.saveHandler = { _ in throw HistoryStoringMock.HistoryStoringMockError.defaultError }

        do {
            try await coordinator.addImportedVisits([importedVisit(title: "Imported", hoursAgo: 1)])
            XCTFail("Import should propagate the save failure")
        } catch HistoryStoringMock.HistoryStoringMockError.defaultError {
            // Expected.
        }
        XCTAssertTrue(coordinator.historyDictionary?[existing.url] === existing)
        XCTAssertEqual(existing.title, "Original")
        XCTAssertEqual(existing.lastVisit, originalDate)
        XCTAssertEqual(existing.numberOfTotalVisits, 1)
        XCTAssertEqual(existing.visits.map(\.date), [originalDate])
    }

    @MainActor
    func testWhenBrowsingDuringAFailedImport_ThenTheNewVisitAndTitleArePreservedAndSaved() async throws {
        let (store, coordinator) = await HistoryCoordinator.aHistoryCoordinator()
        let saveStarted = expectation(description: "Import save started")
        let browsingSaved = expectation(description: "Browsing saved")
        var saveContinuation: CheckedContinuation<Void, Error>?
        store.saveHandler = { _ in
            store.saveHandler = nil
            try await withCheckedThrowingContinuation {
                saveContinuation = $0
                saveStarted.fulfill()
            }
        }
        let imported = importedVisit(title: "Imported", hoursAgo: 1)
        let task = Task { try await coordinator.addImportedVisits([imported]) }
        await fulfillment(of: [saveStarted], timeout: 1)

        let browsingDate = Date()
        let browsingVisit = try XCTUnwrap(coordinator.addVisit(of: imported.url, at: browsingDate, tabID: "live-tab"))
        coordinator.updateTitleIfNeeded(title: "Live", url: imported.url)
        coordinator.commitChanges(url: imported.url)
        XCTAssertEqual(store.savedHistoryEntries.count, 1)
        store.saveCompletion = { browsingSaved.fulfill() }
        try XCTUnwrap(saveContinuation).resume(throwing: HistoryStoringMock.HistoryStoringMockError.defaultError)
        do {
            try await task.value
            XCTFail("Import should propagate the save failure")
        } catch HistoryStoringMock.HistoryStoringMockError.defaultError {
            // Expected.
        }

        let entry = try XCTUnwrap(coordinator.historyDictionary?[imported.url])
        XCTAssertEqual(entry.visits, [browsingVisit])
        XCTAssertEqual(entry.numberOfTotalVisits, 1)
        XCTAssertEqual(entry.lastVisit, browsingDate)
        XCTAssertEqual(entry.title, "Live")
        await fulfillment(of: [browsingSaved], timeout: 1)
        let saved = try XCTUnwrap(store.savedHistoryEntries.last)
        XCTAssertEqual(saved.visits.map(\.date), [browsingDate])
        XCTAssertEqual(saved.title, "Live")
        XCTAssertEqual(saved.numberOfTotalVisits, 1)
    }

    @MainActor
    func testWhenHistoryIsBurning_ThenHistoryIsCleanedIncludingFireproofDomains() async {
        let burnAllFinished = expectation(description: "Burn All Finished")
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

        let url1 = URL(string: "https://duckduckgo.com")!
        historyCoordinator.addVisit(of: url1)

        let url2 = URL(string: "https://test.duckduckgo.com")!
        historyCoordinator.addVisit(of: url2)

        let fireproofDomain = "wikipedia.org"
        let url3 = URL(string: "https://\(fireproofDomain)")!
        historyCoordinator.addVisit(of: url3)

        let url4 = URL(string: "https://subdomain.\(fireproofDomain)")!
        historyCoordinator.addVisit(of: url4)

        XCTAssertEqual(historyCoordinator.history!.count, 4)

        historyCoordinator.burnAll { _ in
            // We now clean the database directly so we don't burn by entry
            XCTAssertEqual(historyStoringMock.removeEntriesArray.count, 0)

            // And we reset the entries dictionary
            XCTAssertEqual(historyCoordinator.history!.count, 0)

            burnAllFinished.fulfill()
        }

        await fulfillment(of: [burnAllFinished], timeout: 2.0)
    }

    @MainActor
    func testWhenBurningVisits_removesHistoryWhenVisitsCountHitsZero() async {
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()
        historyStoringMock.removeEntriesResult = .success(())
        historyStoringMock.removeVisitsResult = .success(())

        let url1 = URL(string: "https://duckduckgo.com")!
        historyCoordinator.addVisit(of: url1)
        historyCoordinator.addVisit(of: url1)
        historyCoordinator.addVisit(of: url1)

        let visitsToBurn = Array(historyCoordinator.history!.first!.visits)

        let waiter = expectation(description: "Wait")
        historyCoordinator.burnVisits(visitsToBurn) { _ in
            waiter.fulfill()
            XCTAssertEqual(historyStoringMock.removeEntriesArray.count, 1)
            XCTAssertEqual(historyStoringMock.removeEntriesArray.first!.url, url1)
        }
        await fulfillment(of: [waiter], timeout: 1.0)
    }

    @MainActor
    func testWhenBurningVisits_removesVisitsFromTheStore() async {
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()
        historyStoringMock.removeEntriesResult = .success(())
        historyStoringMock.removeVisitsResult = .success(())

        let url1 = URL(string: "https://duckduckgo.com")!
        historyCoordinator.addVisit(of: url1)
        historyCoordinator.addVisit(of: url1)
        historyCoordinator.addVisit(of: url1)

        let visitsToBurn = Array(historyCoordinator.history!.first!.visits)

        let waiter = expectation(description: "Wait")
        historyCoordinator.burnVisits(visitsToBurn) { _ in
            waiter.fulfill()
            XCTAssertEqual(historyStoringMock.removeVisitsArray.count, 3)
        }
        await fulfillment(of: [waiter], timeout: 1.0)
    }

    @MainActor
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
        historyCoordinator.burnVisits(visitsToBurn) { _ in
            waiter.fulfill()
            // Simply don't raise an assertion
        }
        waitForExpectations(timeout: 1.0)
    }

    @MainActor
    func testWhenHistoryIsBurningDomains_ThenHistoryIsCleanedForDomainsAndRemovedUrlsReturnedInCallback() async {
        let burnAllFinished = expectation(description: "Burn All Finished")
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

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

        XCTAssertEqual(historyCoordinator.history!.count, 6)

        historyCoordinator.burnDomains(["duckduckgo.com", fireproofDomain], tld: TLD()) { result in
            let expectedUrls = Set([url1, url2, url3, url4])

            XCTAssertEqual(Set(historyStoringMock.removeEntriesArray.map(\.url)), expectedUrls)

            if case .success(let urls) = result {
                XCTAssertEqual(urls, expectedUrls)
            } else {
                XCTFail("Expected success result")
            }

            burnAllFinished.fulfill()
        }

        await fulfillment(of: [burnAllFinished], timeout: 2.0)
    }

    @MainActor
    func testWhenUrlIsMarkedAsFailedToLoad_ThenFailedToLoadFlagIsStored() async {
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

        let url = URL(string: "https://duckduckgo.com")!
        let firstSaveExpectation = expectation(description: "Visit added")
        historyStoringMock.saveCompletion = {
            firstSaveExpectation.fulfill()
        }
        historyCoordinator.addVisit(of: url)
        await fulfillment(of: [firstSaveExpectation], timeout: 1.0)

        historyCoordinator.markFailedToLoadUrl(url)

        let secondSaveExpectation = expectation(description: "Changes committed")
        historyStoringMock.saveCompletion = {
            secondSaveExpectation.fulfill()
        }
        historyCoordinator.commitChanges(url: url)

        await fulfillment(of: [secondSaveExpectation], timeout: 1.0)

        XCTAssertEqual(historyStoringMock.savedHistoryEntries.last?.url, url)
        XCTAssertEqual(historyStoringMock.savedHistoryEntries.last?.failedToLoad, true)
    }

    @MainActor
    func testWhenUrlIsMarkedAsFailedToLoadAndItIsVisitedAgain_ThenFailedToLoadFlagIsSetToFalse() async {
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

        let url = URL(string: "https://duckduckgo.com")!
        historyCoordinator.addVisit(of: url)

        historyCoordinator.markFailedToLoadUrl(url)

        historyCoordinator.addVisit(of: url)

        let expectation = expectation(description: "Changes committed")
        expectation.expectedFulfillmentCount = 2
        historyStoringMock.saveCompletion = {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertEqual(historyStoringMock.savedHistoryEntries.last?.url, url)
        XCTAssertEqual(historyStoringMock.savedHistoryEntries.last?.failedToLoad, false)
    }

    @MainActor
    func testWhenUrlHasNoTitle_ThenFetchingTitleReturnsNil() async {
        let (_, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

        let url = URL.duckDuckGo
        historyCoordinator.addVisit(of: url)

        let title = historyCoordinator.title(for: url)

        XCTAssertNil(title)
    }

    @MainActor
    func testWhenUrlHasTitle_ThenTitleIsReturned() async {
        let (_, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

        let url = URL.duckDuckGo
        let title = "DuckDuckGo"

        historyCoordinator.addVisit(of: url)
        historyCoordinator.updateTitleIfNeeded(title: title, url: url)
        let fetchedTitle = historyCoordinator.title(for: url)

        XCTAssertEqual(title, fetchedTitle)
    }

    @MainActor
    func loadDatabase(name: String) -> CoreDataDatabase? {
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "BrowsingHistory") else {
            return nil
        }
        let bookmarksDatabase = CoreDataDatabase(name: name, containerLocation: location, model: model)
        bookmarksDatabase.loadStore()
        return bookmarksDatabase
    }

    @MainActor
    func testWhenRemoveUrlEntryCalledWithExistingUrl_ThenEntryIsRemovedAndNoError() async {
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

        let url = URL(string: "https://duckduckgo.com")!
        historyCoordinator.addVisit(of: url)

        XCTAssertTrue(historyCoordinator.history!.contains(where: { $0.url == url }))

        let removalExpectation = expectation(description: "Entry removed without error")
        historyCoordinator.removeUrlEntry(url) { error in
            XCTAssertNil(error, "Expected no error when removing an existing URL entry")
            removalExpectation.fulfill()
        }

        await fulfillment(of: [removalExpectation], timeout: 1.0)

        XCTAssertFalse(historyCoordinator.history!.contains(where: { $0.url == url }))
        XCTAssertTrue(historyStoringMock.removeEntriesCalled, "Expected removeEntries to be called")
        XCTAssertEqual(historyStoringMock.removeEntriesArray.count, 1)
        XCTAssertEqual(historyStoringMock.removeEntriesArray.first?.url, url)
    }

    @MainActor
    func testWhenRemoveUrlEntryCalledWithNonExistingUrl_ThenEntryRemovalFailsWithNotAvailableError() async {
        let (_, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

        let nonExistentUrl = URL(string: "https://nonexistent.com")!

        let removalExpectation = expectation(description: "Entry removal fails with notAvailable error")
        historyCoordinator.removeUrlEntry(nonExistentUrl) { error in
            XCTAssertNotNil(error, "Expected an error when removing a non-existent URL entry")
            XCTAssertEqual(error as? HistoryCoordinator.EntryRemovalError, .notAvailable, "Expected notAvailable error")
            removalExpectation.fulfill()
        }

        await fulfillment(of: [removalExpectation], timeout: 1.0)
    }

    // MARK: - Cookie Popup Blocked Tests

    @MainActor
    func testWhenCookiePopupBlockedIsCalled_ThenFlagIsSetAndAutoCommitted() async {
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

        // Add an initial visit, and wait for it to complete:
        let url = URL(string: "https://example.com")!
        historyCoordinator.addVisit(of: url)

        let expectation1 = expectation(description: "Changes auto-committed")
        historyStoringMock.saveCompletion = { expectation1.fulfill() }
        await fulfillment(of: [expectation1], timeout: 5.0)

        // Reset save state after initial visit
        historyStoringMock.saveCalled = false
        historyStoringMock.savedHistoryEntries.removeAll()

        // Perform the cookie-popup block visit:
        let expectation2 = expectation(description: "Changes auto-committed")
        historyStoringMock.saveCompletion = { expectation2.fulfill() }
        historyCoordinator.cookiePopupBlocked(on: url)

        await fulfillment(of: [expectation2], timeout: 5.0)

        // Verify flag is set in memory
        XCTAssertTrue(historyCoordinator.history!.first?.cookiePopupBlocked ?? false)

        // Verify save was called
        XCTAssertTrue(historyStoringMock.saveCalled)
        XCTAssertEqual(historyStoringMock.savedHistoryEntries.count, 1)
        XCTAssertEqual(historyStoringMock.savedHistoryEntries.last?.cookiePopupBlocked, true)
    }

    @MainActor
    func testWhenCookiePopupBlockedIsCalledWithNonExistentURL_ThenNothingHappens() async {
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

        let url = URL(string: "https://nonexistent.com")!

        let noSaveExpectation = expectation(description: "Save should not be called")
        noSaveExpectation.isInverted = true
        historyStoringMock.saveCompletion = {
            noSaveExpectation.fulfill()
        }

        historyCoordinator.cookiePopupBlocked(on: url)

        await fulfillment(of: [noSaveExpectation], timeout: 0.1)

        XCTAssertFalse(historyStoringMock.saveCalled)
    }

    @MainActor
    func testWhenCookiePopupBlockedIsCalledBeforeHistoryLoaded_ThenItIsIgnored() {
        let historyStoringMock = HistoryStoringMock()
        historyStoringMock.cleanOldResult = nil
        let historyCoordinator = HistoryCoordinator(historyStoring: historyStoringMock)

        let url = URL(string: "https://example.com")!
        historyCoordinator.cookiePopupBlocked(on: url)

        XCTAssertFalse(historyStoringMock.saveCalled)
    }

    // MARK: - Reset Cookie Popup Blocked Tests

    @MainActor
    func testWhenResetCookiePopupBlockedIsCalled_ThenFlagsAreResetForMatchingDomains() async {
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

        // Setup: Add visits and mark cookie popups as blocked
        let url1 = URL(string: "https://example.com")!
        let url2 = URL(string: "https://test.example.com")!
        let url3 = URL(string: "https://other.com")!

        // Set up expectation for all saves (3 visits + 3 cookiePopupBlocked = 6)
        let saveExpectation = expectation(description: "All saves completed")
        saveExpectation.expectedFulfillmentCount = 6
        historyStoringMock.saveCompletion = {
            saveExpectation.fulfill()
        }

        historyCoordinator.addVisit(of: url1)
        historyCoordinator.addVisit(of: url2)
        historyCoordinator.addVisit(of: url3)

        historyCoordinator.cookiePopupBlocked(on: url1)
        historyCoordinator.cookiePopupBlocked(on: url2)
        historyCoordinator.cookiePopupBlocked(on: url3)

        await fulfillment(of: [saveExpectation], timeout: 1.0)

        // Verify all are blocked
        XCTAssertTrue(historyCoordinator.history!.first(where: { $0.url == url1 })?.cookiePopupBlocked ?? false)
        XCTAssertTrue(historyCoordinator.history!.first(where: { $0.url == url2 })?.cookiePopupBlocked ?? false)
        XCTAssertTrue(historyCoordinator.history!.first(where: { $0.url == url3 })?.cookiePopupBlocked ?? false)

        // Reset: Clear flags for example.com domain
        let resetExpectation = expectation(description: "Flags reset")
        let saveExpectation2 = expectation(description: "Reset saves completed")
        saveExpectation2.expectedFulfillmentCount = 2 // example.com, test.example.com
        historyStoringMock.saveCompletion = {
            saveExpectation2.fulfill()
        }

        historyCoordinator.resetCookiePopupBlocked(for: ["example.com"], tld: TLD()) { _ in
            resetExpectation.fulfill()
        }

        await fulfillment(of: [resetExpectation, saveExpectation2], timeout: 1.0)

        // Verify: example.com and test.example.com should be reset, other.com should remain
        let entry1 = historyCoordinator.history!.first(where: { $0.url == url1 })
        let entry2 = historyCoordinator.history!.first(where: { $0.url == url2 })
        let entry3 = historyCoordinator.history!.first(where: { $0.url == url3 })

        XCTAssertFalse(entry1?.cookiePopupBlocked ?? true, "example.com should be reset")
        XCTAssertFalse(entry2?.cookiePopupBlocked ?? true, "test.example.com should be reset")
        XCTAssertTrue(entry3?.cookiePopupBlocked ?? false, "other.com should remain blocked")
    }

    @MainActor
    func testWhenResetCookiePopupBlockedIsCalledWithEmptyDomains_ThenNoChanges() async {
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

        let url = URL(string: "https://example.com")!

        // Set up expectation for initial saves (1 visit + 1 cookiePopupBlocked = 2)
        let initialSaveExpectation = expectation(description: "Initial saves completed")
        initialSaveExpectation.expectedFulfillmentCount = 2
        historyStoringMock.saveCompletion = {
            initialSaveExpectation.fulfill()
        }

        historyCoordinator.addVisit(of: url)
        historyCoordinator.cookiePopupBlocked(on: url)

        await fulfillment(of: [initialSaveExpectation], timeout: 5.0)

        let initialSaveCount = historyStoringMock.savedHistoryEntries.count

        let resetExpectation = expectation(description: "Reset called")
        historyCoordinator.resetCookiePopupBlocked(for: [], tld: TLD()) { _ in
            resetExpectation.fulfill()
        }

        await fulfillment(of: [resetExpectation], timeout: 1.0)

        // No additional saves should have occurred
        XCTAssertEqual(historyStoringMock.savedHistoryEntries.count, initialSaveCount)

        // Flag should still be set
        XCTAssertTrue(historyCoordinator.history!.first?.cookiePopupBlocked ?? false)
    }

    @MainActor
    func testWhenResetCookiePopupBlockedIsCalledBeforeHistoryLoaded_ThenItReturnsImmediately() {
        let historyStoringMock = HistoryStoringMock()
        historyStoringMock.cleanOldResult = nil
        let historyCoordinator = HistoryCoordinator(historyStoring: historyStoringMock)

        let completionExpectation = expectation(description: "Completion called")
        historyCoordinator.resetCookiePopupBlocked(for: ["example.com"], tld: TLD()) { _ in
            completionExpectation.fulfill()
        }

        wait(for: [completionExpectation], timeout: 0.1)
        XCTAssertFalse(historyStoringMock.saveCalled)
    }

    @MainActor
    func testWhenResetCookiePopupBlockedIsCalled_ThenOnlyMatchingDomainsAreAffected() async {
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

        // Create various URLs to test eTLD+1 matching
        let urls = [
            URL(string: "https://example.com")!,
            URL(string: "https://www.example.com")!,
            URL(string: "https://subdomain.example.com")!,
            URL(string: "https://another.com")!,
            URL(string: "https://test.org")!
        ]

        // Set up expectation for all saves (5 URLs × 2 saves each = 10)
        let saveExpectation = expectation(description: "All saves completed")
        saveExpectation.expectedFulfillmentCount = 10
        historyStoringMock.saveCompletion = {
            saveExpectation.fulfill()
        }

        // Add visits and block all
        for url in urls {
            historyCoordinator.addVisit(of: url)
            historyCoordinator.cookiePopupBlocked(on: url)
        }

        await fulfillment(of: [saveExpectation], timeout: 5.0)

        // Reset only example.com and test.org
        let resetExpectation = expectation(description: "Reset completed")
        let saveExpectation2 = expectation(description: "Reset saves completed")
        saveExpectation2.expectedFulfillmentCount = 4 // example.com, www.example.com, subdomain.example.com, test.org
        historyStoringMock.saveCompletion = {
            saveExpectation2.fulfill()
        }

        historyCoordinator.resetCookiePopupBlocked(for: ["example.com", "test.org"], tld: TLD()) { _ in
            resetExpectation.fulfill()
        }

        await fulfillment(of: [resetExpectation, saveExpectation2], timeout: 1.0)

        // Verify results
        let results = urls.map { url in
            historyCoordinator.history!.first(where: { $0.url == url })?.cookiePopupBlocked ?? false
        }

        XCTAssertFalse(results[0], "example.com should be reset")
        XCTAssertFalse(results[1], "www.example.com should be reset (same eTLD+1)")
        XCTAssertFalse(results[2], "subdomain.example.com should be reset (same eTLD+1)")
        XCTAssertTrue(results[3], "another.com should remain blocked")
        XCTAssertFalse(results[4], "test.org should be reset")
    }

    // MARK: - Tab ID Tests

    @MainActor
    func testWhenAddVisitIsCalledWithTabID_ThenTabIDIsStoredInVisit() async {
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

        let url = URL(string: "https://duckduckgo.com")!
        let tabID = "test-tab-789"

        historyCoordinator.addVisit(of: url, tabID: tabID)

        let expectation = expectation(description: "Changes committed")
        historyStoringMock.saveCompletion = {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)

        let savedTabID = historyStoringMock.savedVisitsWithTabIDs.last?.tabID
        XCTAssertEqual(savedTabID, tabID)
    }

    @MainActor
    func testWhenAddVisitIsCalledWithNilTabID_ThenVisitHasNoTabID() async {
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()

        let url = URL(string: "https://duckduckgo.com")!

        historyCoordinator.addVisit(of: url, tabID: nil)

        let expectation = expectation(description: "Changes committed")
        historyStoringMock.saveCompletion = {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)

        let savedTabID = historyStoringMock.savedVisitsWithTabIDs.last?.tabID
        XCTAssertNil(savedTabID)
    }

    // MARK: - Burn Visits For Tab ID Tests

    @MainActor
    func testWhenBurnVisitsForTabID_ThenOnlyThatTabsVisitsAreRemoved() async {
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()
        historyStoringMock.removeEntriesResult = .success(())
        historyStoringMock.removeVisitsResult = .success(())

        let url1 = URL(string: "https://site1.com")!
        let url2 = URL(string: "https://site2.com")!

        let saveExpectation = expectation(description: "Saves completed")
        saveExpectation.expectedFulfillmentCount = 2
        historyStoringMock.saveCompletion = {
            saveExpectation.fulfill()
        }

        let visit1 = historyCoordinator.addVisit(of: url1, tabID: "tab-1")
        _ = historyCoordinator.addVisit(of: url2, tabID: "tab-2")

        await fulfillment(of: [saveExpectation], timeout: 1.0)

        // Wait for identifier to be set on the original visit (happens asynchronously after save returns)
        guard let visit1 else {
            XCTFail("visit1 should not be nil")
            return
        }

        let identifierPredicate = NSPredicate { _, _ in visit1.identifier != nil }
        let identifierExpectation = XCTNSPredicateExpectation(predicate: identifierPredicate, object: nil)

        await fulfillment(of: [identifierExpectation], timeout: 10.0)

        guard let visit1ID = visit1.identifier else {
            XCTFail("visit1 identifier should not be nil after save")
            return
        }

        historyStoringMock.pageVisitIDsResult = [visit1ID]

        // When
        let burnExpectation = expectation(description: "Burn completed")
        do {
            try await historyCoordinator.burnVisits(for: "tab-1")
            burnExpectation.fulfill()
        } catch {
            XCTFail("burnVisits should not throw: \(error)")
        }
        await fulfillment(of: [burnExpectation], timeout: 1.0)

        // Then - Only tab-1's visit should be removed
        XCTAssertEqual(historyStoringMock.removeVisitsArray.count, 1)
        XCTAssertEqual(historyStoringMock.removeVisitsArray.first?.identifier, visit1.identifier)
        XCTAssertTrue(historyCoordinator.history!.contains { $0.url == url2 })
    }

    @MainActor
    func testWhenBurnVisitsForTabIDWithNoHistory_ThenNoVisitsAreBurned() async {
        let (historyStoringMock, historyCoordinator) = await HistoryCoordinator.aHistoryCoordinator()
        historyStoringMock.removeVisitsResult = .success(())

        // Configure mock to return empty visit IDs (no history for this tab)
        historyStoringMock.pageVisitIDsResult = []

        // When
        let burnExpectation = expectation(description: "Burn completed")
        do {
            try await historyCoordinator.burnVisits(for: "non-existent-tab")
            burnExpectation.fulfill()
        } catch {
            XCTFail("burnVisits should not throw: \(error)")
        }
        await fulfillment(of: [burnExpectation], timeout: 1.0)

        // Then - No visits should be removed
        XCTAssertTrue(historyStoringMock.removeVisitsArray.isEmpty)
    }

    // MARK: - Imported Visits Helpers

    private func importedVisit(of url: URL = .duckDuckGo, title: String, hoursAgo: Double) -> HistoryImport.Visit {
        HistoryImport.Visit(url: url, title: title, date: Date().addingTimeInterval(-hoursAgo * 3600))
    }

}

fileprivate extension HistoryCoordinator {

    @MainActor
    static func aHistoryCoordinator(history: BrowsingHistory = []) async -> (HistoryStoringMock, HistoryCoordinator) {
        let historyStoringMock = HistoryStoringMock(cleanOldResult: .success(history), removeEntriesResult: .success(()))
        let historyCoordinator = HistoryCoordinator(historyStoring: historyStoringMock)

        // Use a continuation to wait for async loading
        return await withCheckedContinuation { continuation in
            historyCoordinator.loadHistory {
                continuation.resume(returning: (historyStoringMock, historyCoordinator))
            }
        }
    }

}

actor HistoryStoringMock: HistoryStoring {

    enum HistoryStoringMockError: Error {
        case defaultError
    }

    @MainActor
    init(cleanOldResult: Result<BrowsingHistory, Error>? = nil, removeEntriesResult: Result<Void, Error>? = nil) {
        self.cleanOldResult = cleanOldResult
        self.removeEntriesResult = removeEntriesResult
    }

    @MainActor var cleanOldHandler: (@MainActor () async throws -> BrowsingHistory)?
    @MainActor var cleanOldCalled = false
    @MainActor var cleanOldResult: Result<BrowsingHistory, Error>?
    func cleanOld(until date: Date) async throws -> BrowsingHistory {
        if let handler = await cleanOldHandler {
            return try await handler()
        }
        return try await MainActor.run {
            cleanOldCalled = true
            switch cleanOldResult {
            case .success(let history):
                return history
            case .failure(let error):
                throw error
            case .none:
                throw HistoryStoringMockError.defaultError
            }
        }
    }

    func load() {
        // no-op
    }

    @MainActor var removeEntriesCalled = false
    @MainActor var removeEntriesArray = [HistoryEntry]()
    @MainActor var removeEntriesResult: Result<Void, Error>?
    func removeEntries(_ entries: some Sequence<History.HistoryEntry>) async throws {
        try await MainActor.run {
            removeEntriesCalled = true
            removeEntriesArray = Array(entries)

            switch removeEntriesResult {
            case .success:
                return
            case .failure(let error):
                throw error
            case .none:
                throw HistoryStoringMockError.defaultError
            }
        }
    }

    @MainActor var removeVisitsCalled = false
    @MainActor var removeVisitsArray = [Visit]()
    @MainActor var removeVisitsResult: Result<Void, Error>?
    func removeVisits(_ visits: some Sequence<History.Visit>) async throws {
        try await MainActor.run {
            removeVisitsCalled = true
            removeVisitsArray = Array(visits)
            switch removeVisitsResult {
            case .success:
                return
            case .failure(let error):
                throw error
            case .none:
                throw HistoryStoringMockError.defaultError
            }
        }
    }

    @MainActor var saveHandler: (@MainActor (HistoryEntry) async throws -> Void)?
    @MainActor var saveCalled = false
    @MainActor var savedHistoryEntries = [HistoryEntry]()
    @MainActor var savedVisitsWithTabIDs: [(visit: Visit, tabID: String?)] = []
    @MainActor var saveCompletion: (() -> Void)?

    func save(entry: HistoryEntry) async throws -> [(id: Visit.ID, date: Date)] {
        for visit in entry.visits {
            // swiftlint:disable:next legacy_random
            visit.identifier = URL(string: "x-coredata://FBEAB2C4-8C32-4F3F-B34F-B79F293CDADD/VisitManagedObject/\(arc4random())")
        }

        await MainActor.run {
            saveCalled = true
            savedHistoryEntries.append(entry)
            for visit in entry.visits {
                savedVisitsWithTabIDs.append((visit, visit.tabID))
            }
            saveCompletion?()
        }

        if let handler = await saveHandler {
            try await handler(entry)
        }
        return entry.visits.map { ($0.identifier!, $0.date) }
    }

    @MainActor var pageVisitIDsCalled = false
    @MainActor var pageVisitIDsResult: [Visit.ID] = []

    func pageVisitIDs(in tabID: String) async throws -> [History.Visit.ID] {
        await MainActor.run {
            pageVisitIDsCalled = true
            return pageVisitIDsResult
        }
    }

}

class MockHistoryStoreEventMapper: EventMapping<HistoryDatabaseError> {
    public init() {
        super.init { _, _, _, _ in
            // no-op
        }
    }

    override init(mapping: @escaping EventMapping<HistoryDatabaseError>.Mapping) {
        fatalError("Use init()")
    }
}
