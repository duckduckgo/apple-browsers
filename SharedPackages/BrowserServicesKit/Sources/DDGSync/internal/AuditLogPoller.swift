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
    private let canPoll: (SyncAccount) -> Bool
    private let initializeReviewState: (AuditLogPage, SyncAccount) throws -> Void
    private let onError: (Error) -> Void
    private let sleep: (UInt64) async throws -> Void
    private let lock = NSLock()
    // Keep checkpoint writes ordered with logout cleanup; callbacks may re-enter cancellation or cleanup.
    private let checkpointLock = NSRecursiveLock()
    private var task: (id: UUID, handle: Task<Void, Never>)?
    private var isSuspended = false

    init(accountManager: AccountManaging,
         keyValueStore: ThrowingKeyValueStoring,
         canPoll: @escaping (SyncAccount) -> Bool,
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

    @discardableResult
    func startPolling(for account: SyncAccount) -> Task<Void, Never>? {
        guard canPoll(account) else { return nil }
        return lock.withLock {
            guard task == nil, !isSuspended else { return nil }
            let id = UUID()
            let handle = Task { [weak self] in
                guard let self else { return }
                defer {
                    self.lock.withLock {
                        if self.task?.id == id { self.task = nil }
                    }
                }
                do {
                    try await self.poll(for: account)
                } catch is CancellationError {
                    // Suspension and account changes resume from the last completed poll on a later sync.
                } catch {
                    if self.canPoll(account), !Task.isCancelled { self.onError(error) }
                }
            }
            task = (id, handle)
            return handle
        }
    }

    func cancel() {
        let handle = lock.withLock {
            let handle = task?.handle
            task = nil
            return handle
        }
        handle?.cancel()
    }

    func setSuspended(_ suspended: Bool) {
        let handle: Task<Void, Never>? = lock.withLock {
            isSuspended = suspended
            guard suspended else { return nil }
            let handle = task?.handle
            task = nil
            return handle
        }
        handle?.cancel()
    }

    func clearState(for accountID: String) throws {
        setSuspended(true)
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
                cursor = try afterCursor(in: page)
                try await sleep(Constants.pageDelayNanoseconds)
            }
        } catch AuditLogError.invalidCursor {
            try checkCanPoll(account)
            try checkpointLock.withLock {
                try Task.checkCancellation()
                try keyValueStore.removeObject(forKey: Self.cursorKey(for: account.userId))
            }
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
        guard canPoll(account) else { throw CancellationError() }
    }
}
