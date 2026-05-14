//
//  HistoryStoringMock.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
@testable import DuckDuckGo_Privacy_Browser
import Combine
import History

final class HistoryStoringMock: HistoryStoring {

    enum HistoryStoringMockError: Error {
        case defaultError
    }

    var cleanOldCalled = false
    var cleanOldResult: Result<BrowsingHistory, Error>?
    func cleanOld(until date: Date) async throws -> BrowsingHistory {
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

    func load() {
        // no-op
    }

    var removeEntriesCalled = false
    var removeEntriesArray = [HistoryEntry]()
    var removeEntriesResult: Result<Void, Error>?
    func removeEntries(_ entries: some Sequence<History.HistoryEntry>) async throws {
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

    var removeVisitsCalled = false
    var removeVisitsArray = [Visit]()
    var removeVisitsResult: Result<Void, Error>?
    func removeVisits(_ visits: some Sequence<History.Visit>) async throws {
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

    var saveCalled = false
    var savedHistoryEntries = [HistoryEntry]()
    func save(entry: HistoryEntry) async throws -> [(id: Visit.ID, date: Date)] {
        saveCalled = true
        savedHistoryEntries.append(entry)
        for visit in entry.visits {
            // swiftlint:disable:next legacy_random
            visit.identifier = URL(string: "x-coredata://FBEAB2C4-8C32-4F3F-B34F-B79F293CDADD/VisitManagedObject/\(arc4random())")
        }

        return entry.visits.map { ($0.identifier!, $0.date) }
    }

    var pageVisitIDsCalled = false
    var pageVisitIDsResult: [Visit.ID] = []
    func pageVisitIDs(in tabID: String) async throws -> [Visit.ID] {
        pageVisitIDsCalled = true
        return pageVisitIDsResult
    }

}
