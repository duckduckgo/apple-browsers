//
//  HistoryCoordinatingMock.swift
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

#if DEBUG

import Combine
import Common
import Foundation
import History
import Suggestions

public final class HistoryCoordinatingMock: HistoryCoordinating, HistoryDataSource, SuggestionContainer.HistoryProvider {

    public init() {}

    public func loadHistory(onCleanFinished: @escaping () -> Void) {
        onCleanFinished()
    }

    public var history: BrowsingHistory?
    public var allHistoryVisits: [Visit]?
    @Published public private(set) var historyDictionary: [URL: HistoryEntry]?
    public var historyDictionaryPublisher: Published<[URL: HistoryEntry]?>.Publisher { $historyDictionary }

    public var addVisitCalled = false
    public var visit: Visit?
    public func addVisit(of url: URL, at date: Date, tabID: String?) -> Visit? {
        addVisitCalled = true
        return visit
    }

    public var updateTitleIfNeededCalled = false
    public func updateTitleIfNeeded(title: String, url: URL) {
        updateTitleIfNeededCalled = true
    }

    public var addBlockedTrackerCalled = false
    public func addBlockedTracker(entityName: String, on url: URL) {
        addBlockedTrackerCalled = true
    }

    public var commitChangesCalled = false
    public func commitChanges(url: URL) {
        commitChangesCalled = true
    }

    public var burnAllCalled = false
    public var onBurnAll: (() -> Void)?
    public func burnAll(completion: @escaping @MainActor () -> Void) {
        burnAllCalled = true
        onBurnAll?()
        MainActor.assumeMainThread {
            completion()
        }
    }

    public var burnDomainsCalled = false
    public var onBurnDomains: (() -> Void)?
    public func burnDomains(_ baseDomains: Set<String>, tld: Common.TLD, completion: @escaping @MainActor (Set<URL>) -> Void) {
        burnDomainsCalled = true
        onBurnDomains?()
        MainActor.assumeMainThread {
            completion([])
        }
    }

    public var burnVisitsCalled = false
    public var onBurnVisits: (() -> Void)?
    public func burnVisits(_ visits: [Visit], completion: @escaping @MainActor () -> Void) {
        burnVisitsCalled = true
        onBurnVisits?()
        MainActor.assumeMainThread {
            completion()
        }
    }

    public var markFailedToLoadUrlCalled = false
    public func markFailedToLoadUrl(_ url: URL) {
        markFailedToLoadUrlCalled = true
    }

    public var titleForUrlCalled = false
    public func title(for url: URL) -> String? {
        titleForUrlCalled = true
        return nil
    }

    public var trackerFoundCalled = false
    public func trackerFound(on: URL) {
        trackerFoundCalled = true
    }

    public var cookiePopupBlockedCalled = false
    public func cookiePopupBlocked(on: URL) {
        cookiePopupBlockedCalled = true
    }

    public var resetCookiePopupBlockedCalled = false
    public var resetCookiePopupBlockedDomains: Set<String>?
    public var resetCookiePopupBlockedTLD: Common.TLD?
    public func resetCookiePopupBlocked(for domains: Set<String>, tld: Common.TLD, completion: @escaping @MainActor () -> Void) {
        resetCookiePopupBlockedCalled = true
        resetCookiePopupBlockedDomains = domains
        resetCookiePopupBlockedTLD = tld
        MainActor.assumeMainThread {
            completion()
        }
    }

    public var removeUrlEntryCalled = false
    public func removeUrlEntry(_ url: URL, completion: (@MainActor ((any Error)?) -> Void)?) {
        removeUrlEntryCalled = true
        MainActor.assumeMainThread {
            completion?(nil)
        }
    }

    public var historySuggestionsStub: [HistorySuggestion] = []
    public func history(for suggestionLoading: SuggestionLoading) -> [HistorySuggestion] {
        return historySuggestionsStub
    }

    @MainActor
    public func delete(_ visits: [History.Visit]) async {
        await withCheckedContinuation { continuation in
            burnVisits(visits) {
                continuation.resume()
            }
        }
    }
}
#endif
