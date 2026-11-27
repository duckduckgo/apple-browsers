//
//  AuditLogPoller.swift
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
import FoundationExtensions
import Persistence

/// Tracks forward progress independently of the Device Activity screen's history cursor and review date.
final class AuditLogPoller {
    private enum Constants {
        static let pageSize = 100
        static let pageDelayNanoseconds: UInt64 = 2_000_000_000
    }

    private let accountManager: AccountManaging
    private let keyValueStore: ThrowingKeyValueStoring
    private let canPoll: (SyncAccount) throws -> Bool
    private let initializeReviewState: (AuditLogPage, SyncAccount) throws -> Void
    private let onError: (Error) -> Void
    private let sleep: (UInt64) async throws -> Void
    private let lock = NSLock()
    // Keep checkpoint writes ordered with logout cleanup; callbacks may re-enter cancellation or cleanup.
    private let checkpointLock = NSRecursiveLock()
    private var task: (id: UUID, handle: Task<Void, Error>)?

    init(accountManager: AccountManaging,
         keyValueStore: ThrowingKeyValueStoring,
         canPoll: @escaping (SyncAccount) throws -> Bool,
         initializeReviewState: @escaping (AuditLogPage, SyncAccount) throws -> Void,
         onError: @escaping (Error) -> Void,
         sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.accountManager = accountManager
        self.keyValueStore = keyValueStore
        self.canPoll = canPoll
        self.initializeReviewState = initializeReviewState
        self.onError = onError
        self.sleep = sleep
    }

    static func cursorKey(for accountID: String) -> String {
        "com.duckduckgo.sync.audit-log.cursor.\(accountID)"
    }

    /// Returns false when polling is disabled or another caller already owns a poll.
    func pollIfNeeded(for account: SyncAccount) async throws -> Bool {
        guard let handle = try beginPolling(for: account) else { return false }
        try await waitForPoll(handle)
        return true
    }

    /// Starts foreground polling and reports failures through onError.
    @discardableResult
    func startPolling(for account: SyncAccount) -> Task<Void, Error>? {
        do {
            return try beginPolling(for: account, onError: onError)
        } catch is CancellationError {
            return nil
        } catch {
            onError(error)
            return nil
        }
    }

    private func beginPolling(for account: SyncAccount, onError: ((Error) -> Void)? = nil) throws -> Task<Void, Error>? {
        try Task.checkCancellation()
        guard try canPoll(account) else { return nil }
        try Task.checkCancellation()
        return lock.withLock {
            guard task == nil else { return nil }
            let id = UUID()
            let handle = Task {
                defer {
                    self.lock.withLock {
                        if self.task?.id == id { self.task = nil }
                    }
                }
                do {
                    try await self.poll(for: account)
                } catch {
                    if !Task.isCancelled, !(error is CancellationError) { onError?(error) }
                    throw error
                }
            }
            task = (id, handle)
            return handle
        }
    }

    private func waitForPoll(_ handle: Task<Void, Error>) async throws {
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            try await handle.value
        }, onCancel: {
            handle.cancel()
        })
    }

    func cancel() {
        // Keep the slot occupied until a cancelled request has actually unwound.
        lock.withLock { task?.handle.cancel() }
    }

    func clearState(for accountID: String) throws {
        cancel()
        try checkpointLock.withLock {
            try keyValueStore.removeObject(forKey: Self.cursorKey(for: accountID))
        }
    }

    private func poll(for account: SyncAccount) async throws {
        try checkCanPoll(account)
        guard var cursor = try keyValueStore.object(forKey: Self.cursorKey(for: account.userId)) as? String else {
            try await initialize(for: account)
            return
        }

        do {
            while true {
                try checkCanPoll(account)
                let page = try await accountManager.fetchAuditLog(for: account, cursor: .after(cursor), limit: Constants.pageSize)
                if page.entries.isEmpty {
                    // Commit only when the whole poll succeeds. A failure repeats all pages on the next sync.
                    try save(page, for: account, isInitialPage: false)
                    return
                }
                let nextCursor = try afterCursor(in: page)
                guard nextCursor != cursor else { throw AuditLogError.nonAdvancingAfterCursor }
                cursor = nextCursor
                try await sleep(Constants.pageDelayNanoseconds)
            }
        } catch AuditLogError.invalidCursor {
            try checkCanPoll(account)
            // Reinitialize once; the returned history is not new activity.
            try await initialize(for: account)
        }
    }

    private func initialize(for account: SyncAccount) async throws {
        try checkCanPoll(account)
        let page = try await accountManager.fetchAuditLog(for: account, cursor: nil, limit: Constants.pageSize)
        try save(page, for: account, isInitialPage: true)
    }

    private func save(_ page: AuditLogPage, for account: SyncAccount, isInitialPage: Bool) throws {
        let cursor = try afterCursor(in: page)
        try checkCanPoll(account)
        try checkpointLock.withLock {
            try Task.checkCancellation()
            if isInitialPage { try initializeReviewState(page, account) }
            // Initialization may synchronously cancel polling or remove the account.
            try Task.checkCancellation()
            try keyValueStore.set(cursor, forKey: Self.cursorKey(for: account.userId))
        }
    }

    private func afterCursor(in page: AuditLogPage) throws -> String {
        guard let cursor = page.after else { throw AuditLogError.missingRequiredAfterCursor }
        return cursor
    }

    private func checkCanPoll(_ account: SyncAccount) throws {
        try Task.checkCancellation()
        guard try canPoll(account) else { throw CancellationError() }
    }
}
