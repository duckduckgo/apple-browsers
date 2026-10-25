//
//  HistoryCoordinatingMock.swift
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

import Combine
import Common
import Foundation
import History

final class HistoryCoordinatingMock: HistoryCoordinating {
    var isHistoryLoaded = false
    var history: BrowsingHistory?
    var allHistoryVisits: [Visit]?
    @Published var historyDictionary: [URL: HistoryEntry]?
    var historyDictionaryPublisher: Published<[URL: HistoryEntry]?>.Publisher { $historyDictionary }

    var addImportedVisitsError: Error?
    var addImportedVisitsCalls: [[HistoryImport.Visit]] = []
    func addImportedVisits(_ visits: [HistoryImport.Visit]) async throws {
        addImportedVisitsCalls.append(visits)
        if let addImportedVisitsError {
            throw addImportedVisitsError
        }
    }

    func loadHistory(onCleanFinished: @escaping () -> Void) {}
    func addVisit(of url: URL, at date: Date, tabID: String?) -> Visit? { nil }
    func addBlockedTracker(entityName: String, on url: URL) {}
    func trackerFound(on: URL) {}
    func cookiePopupBlocked(on: URL) {}
    func updateTitleIfNeeded(title: String, url: URL) {}
    func markFailedToLoadUrl(_ url: URL) {}
    func commitChanges(url: URL) {}
    func title(for url: URL) -> String? { nil }
    func burnAll(completion: @escaping @MainActor (Result<Void, Error>) -> Void) {}
    func burnDomains(_ baseDomains: Set<String>, tld: TLD, completion: @escaping @MainActor (Result<Set<URL>, Error>) -> Void) {}
    func burnVisits(_ visits: [Visit], completion: @escaping @MainActor (Result<Void, Error>) -> Void) {}
    func burnVisits(for tabID: String) async throws {}
    func resetCookiePopupBlocked(for domains: Set<String>, tld: TLD, completion: @escaping @MainActor (Result<Void, Error>) -> Void) {}
    func removeUrlEntry(_ url: URL, completion: (@MainActor (Error?) -> Void)?) {}
}
