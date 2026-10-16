//
//  TokenBackupStore.swift
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
import os.log
import FoundationExtensions

/// Keeps the backup token container, an independent token pair forked from the current one, and decides when it must be renewed.
struct TokenBackupStore {

    private let storage: any AuthTokenStoring
    private let maxAge: TimeInterval
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - storage: Where the backup token container is read from and saved to.
    ///   - maxAge: How long after its refresh token was issued a backup is renewed.
    ///   - now: The current date, used to measure the backup's age.
    init(storage: any AuthTokenStoring,
         maxAge: TimeInterval = .days(14),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.storage = storage
        self.maxAge = maxAge
        self.now = now
    }

    /// Whether a refresh of `primary` should also mint a new backup.
    /// - Parameter primary: The token container about to be refreshed.
    /// - Returns: `true` when there is no backup, or the stored one is expired, belongs to another account than `primary`,
    ///   or was issued more than `maxAge` ago. `false` when the backup is still usable or reading it fails.
    func needsRenewal(for primary: TokenContainer) -> Bool {
        let backup: TokenContainer?
        do {
            backup = try storage.getTokenContainer()
        } catch {
            Logger.OAuthClient.error("Failed to read the backup token, skipping renewal: \(String(describing: error), privacy: .public)")
            return false
        }
        guard let backup else { return true }
        if backup.decodedRefreshToken.isExpired() { return true }
        if backup.decodedAccessToken.externalID != primary.decodedAccessToken.externalID { return true }
        return now().timeIntervalSince(backup.decodedRefreshToken.issuedAtDate) > maxAge
    }

    /// Stores `backup`, replacing any previous one. A failure is logged and otherwise ignored.
    /// - Parameter backup: The new backup token container.
    func save(_ backup: TokenContainer) {
        do {
            try storage.saveTokenContainer(backup)
        } catch {
            Logger.OAuthClient.error("Failed to save the backup token: \(String(describing: error), privacy: .public)")
        }
    }

    /// Deletes the backup token container. A failure is logged and otherwise ignored.
    func remove() {
        do {
            try storage.saveTokenContainer(nil)
        } catch {
            Logger.OAuthClient.error("Failed to delete the backup token: \(String(describing: error), privacy: .public)")
        }
    }
}
