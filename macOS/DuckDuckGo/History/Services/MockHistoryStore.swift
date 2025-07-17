//
//  MockHistoryStore.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

#if DEBUG
import Combine
import Foundation
import History

final class MockHistoryStore: HistoryStoring {
    func cleanOld(until date: Date) -> Future<BrowsingHistory, any Error> {
        Future { promise in
            promise(.success([]))
        }
    }

    func save(entry: HistoryEntry) -> Future<[(id: Visit.ID, date: Date)], any Error> {
        Future { promise in
            promise(.success([]))
        }
    }

    func removeEntries(_ entries: [HistoryEntry]) -> Future<Void, any Error> {
        Future { promise in
            promise(.success(()))
        }
    }

    func removeVisits(_ visits: [Visit]) -> Future<Void, any Error> {
        Future { promise in
            promise(.success(()))
        }
    }
}
#endif
