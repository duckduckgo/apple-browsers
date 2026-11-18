//
//  ChromiumProfileDatabaseInspector.swift
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

import Foundation
import GRDB

/// Chromium creates `Login Data` and `History` with every new profile, so their presence doesn't mean there's anything to import.
protocol ChromiumProfileDatabaseInspectorProtocol {
    func hasLogins(inDatabaseAt databaseURL: URL) -> Bool
    func hasVisits(inDatabaseAt databaseURL: URL, since cutoff: Date) -> Bool
}

final class ChromiumProfileDatabaseInspector: ChromiumProfileDatabaseInspectorProtocol {
    private let lock = NSLock()
    private var cachedResults = [String: Bool]()

    func hasLogins(inDatabaseAt databaseURL: URL) -> Bool {
        hasRows(inDatabaseAt: databaseURL, sql: "SELECT 1 FROM logins WHERE blacklisted_by_user != 1 LIMIT 1")
    }

    /// Counts only the visits `ChromiumHistoryReader` imports: web pages the user opened, not subframes, keyword searches or redirect hops.
    func hasVisits(inDatabaseAt databaseURL: URL, since cutoff: Date) -> Bool {
        typealias Transition = ChromiumHistoryReader.Transition
        let chromiumCutoff = Int64((cutoff.timeIntervalSince1970 + ChromiumHistoryReader.Constants.chromiumEpochOffset) * 1_000_000)
        let sql = """
            SELECT 1 FROM visits JOIN urls ON urls.id = visits.url
            WHERE visits.visit_time >= ?
            AND (urls.url LIKE 'http://%' OR urls.url LIKE 'https://%')
            AND visits.transition & \(Transition.chainEnd) != 0
            AND visits.transition & \(Transition.coreMask) NOT IN (\(Transition.autoSubframe), \(Transition.manualSubframe), \(Transition.keywordGenerated))
            LIMIT 1
            """
        return hasRows(inDatabaseAt: databaseURL, sql: sql, arguments: [chromiumCutoff])
    }

    /// Results are cached because the profile picker validates profiles on every redraw.
    /// A database that can't be read counts as having rows, so a read failure never hides a profile.
    private func hasRows(inDatabaseAt databaseURL: URL, sql: String, arguments: StatementArguments = []) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let cacheKey = databaseURL.path + "|" + sql
        if let cachedResult = cachedResults[cacheKey] {
            return cachedResult
        }

        // Chromium keeps its databases locked while it runs, so read a copy.
        let result = (try? databaseURL.withTemporaryFile { temporaryDatabaseURL in
            try DatabaseQueue(path: temporaryDatabaseURL.path).read { database in
                try Row.fetchOne(database, sql: sql, arguments: arguments) != nil
            }
        }) ?? true
        cachedResults[cacheKey] = result
        return result
    }
}
