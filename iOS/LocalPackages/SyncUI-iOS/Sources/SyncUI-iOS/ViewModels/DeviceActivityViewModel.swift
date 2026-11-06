//
//  DeviceActivityViewModel.swift
//  DuckDuckGo
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
import Foundation

public struct DeviceActivityEntry: Identifiable, Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        case synced
        case removed
    }

    public let id: String
    public let action: Action
    public let date: Date
    public let deviceName: String
    public let deviceType: String
    public let credentialId: String?

    public init(id: String, action: Action, date: Date, deviceName: String, deviceType: String, credentialId: String? = nil) {
        self.id = id
        self.action = action
        self.date = date
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.credentialId = credentialId
    }
}

public struct DeviceActivityPage: Sendable {
    public let entries: [DeviceActivityEntry]
    public let hasMore: Bool

    public init(entries: [DeviceActivityEntry], hasMore: Bool) {
        self.entries = entries
        self.hasMore = hasMore
    }
}

/// Tracks the account's reviewed-through date.
/// An initialized state with no date represents an empty history, so future events remain unread.
public struct DeviceActivityReviewState: Sendable, Equatable {
    public let reviewedThrough: Date?
    public let isInitialized: Bool

    public init(reviewedThrough: Date?, isInitialized: Bool) {
        self.reviewedThrough = reviewedThrough
        self.isInitialized = isInitialized
    }
}

@MainActor
public final class DeviceActivityViewModel: ObservableObject {
    public typealias PageFetcher = @MainActor () async throws -> DeviceActivityPage

    private static let emptyPageDelayNanoseconds: UInt64 = 2_000_000_000
    private static let reviewDelayNanoseconds: UInt64 = 3_000_000_000

    @Published public private(set) var entries: [DeviceActivityEntry] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?
    @Published public private(set) var hasLoaded = false
    @Published public private(set) var reviewState = DeviceActivityReviewState(reviewedThrough: nil, isInitialized: false)

    private let accountIdentifier: () -> String?
    private let makePageFetcher: () throws -> PageFetcher
    private var fetchPage: PageFetcher?
    private let loadReviewState: (String) -> DeviceActivityReviewState?
    private let saveReviewState: (String, DeviceActivityReviewState) -> Void
    private let sleep: (UInt64) async throws -> Void
    private var accountID: String?
    private var hasMore = true
    // A new visit or account change invalidates work that is suspended at an await.
    private var generation = 0

    public init(accountIdentifier: @escaping () -> String?,
                makePageFetcher: @escaping () throws -> PageFetcher,
                loadReviewState: @escaping (String) -> DeviceActivityReviewState? = { _ in nil },
                saveReviewState: @escaping (String, DeviceActivityReviewState) -> Void = { _, _ in },
                sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.accountIdentifier = accountIdentifier
        self.makePageFetcher = makePageFetcher
        self.loadReviewState = loadReviewState
        self.saveReviewState = saveReviewState
        self.sleep = sleep
    }

    public func loadIfNeeded() async {
        updateAccountIfNeeded()
        guard !hasLoaded, !isLoading else { return }
        await loadPage()
    }

    public func loadOlderIfNeeded(after entryID: String) async {
        updateAccountIfNeeded()
        guard entries.last?.id == entryID, hasMore, !isLoading else { return }
        await loadPage()
    }

    public func retry() async {
        updateAccountIfNeeded()
        guard !isLoading else { return }
        await loadPage()
    }

    public func dismissError() {
        error = nil
    }

    public func isSeen(_ entry: DeviceActivityEntry) -> Bool {
        guard reviewState.isInitialized else { return false }
        guard let reviewedThrough = reviewState.reviewedThrough else { return false }
        return entry.date <= reviewedThrough
    }

    /// Reviews all activity through the newest timestamp after the screen stays open for the delay.
    /// This includes older rows that have not been loaded or scrolled into view.
    public func markAsReviewedAfterDelay() async {
        guard hasLoaded, let newestEntry = entries.first, !isSeen(newestEntry), let accountID else { return }
        let requestGeneration = generation
        do {
            try await sleep(Self.reviewDelayNanoseconds)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        updateAccountIfNeeded()
        guard requestGeneration == generation, accountIdentifier() == accountID else { return }
        if let reviewedThrough = reviewState.reviewedThrough, newestEntry.date <= reviewedThrough { return }
        reviewState = DeviceActivityReviewState(reviewedThrough: newestEntry.date, isInitialized: true)
        saveReviewState(accountID, reviewState)
    }

    /// Discards this visit's entries and reader while retaining the persisted review state.
    public func cancelAndClear() {
        generation += 1
        entries = []
        fetchPage = nil
        hasMore = true
        hasLoaded = false
        isLoading = false
        error = nil
        accountID = nil
        reviewState = DeviceActivityReviewState(reviewedThrough: nil, isInitialized: false)
    }

    private func updateAccountIfNeeded() {
        let currentID = accountIdentifier()
        guard currentID != accountID else { return }
        generation += 1
        accountID = currentID
        isLoading = false
        entries = []
        fetchPage = nil
        hasMore = true
        hasLoaded = false
        error = nil
        reviewState = currentID.flatMap(loadReviewState) ?? DeviceActivityReviewState(reviewedThrough: nil, isInitialized: false)
    }

    private func loadPage() async {
        guard accountID != nil else { return }
        isLoading = true
        error = nil
        let requestGeneration = generation
        defer {
            if requestGeneration == generation { isLoading = false }
        }
        var receivedEntries = [DeviceActivityEntry]()

        do {
            let pageFetcher: PageFetcher
            if let fetchPage {
                pageFetcher = fetchPage
            } else {
                pageFetcher = try makePageFetcher()
                fetchPage = pageFetcher
            }
            repeat {
                try Task.checkCancellation()
                try checkRequestIsCurrent(requestGeneration)
                let page = try await pageFetcher()
                // Consume a completed page even if its row task was cancelled, keeping the reader and visible rows in step.
                try checkRequestIsCurrent(requestGeneration)
                receivedEntries.append(contentsOf: page.entries)
                hasMore = page.hasMore
                // Empty pages can lead to older activity; pace these follow-up requests.
                if receivedEntries.isEmpty && hasMore {
                    try await sleep(Self.emptyPageDelayNanoseconds)
                }
            } while receivedEntries.isEmpty && hasMore

            seedReviewStateIfNeeded(from: receivedEntries)
            entries = (entries + receivedEntries).sorted { $0.date > $1.date }
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            updateAccountIfNeeded()
            guard requestGeneration == generation else { return }
            self.error = error
        }
    }

    private func checkRequestIsCurrent(_ requestGeneration: Int) throws {
        updateAccountIfNeeded()
        guard requestGeneration == generation else { throw CancellationError() }
    }

    // Establish the initial baseline only after finding entries or reaching the start of history.
    private func seedReviewStateIfNeeded(from receivedEntries: [DeviceActivityEntry]) {
        guard !reviewState.isInitialized else { return }
        reviewState = DeviceActivityReviewState(reviewedThrough: receivedEntries.map(\.date).max(), isInitialized: true)
        guard let accountID, accountIdentifier() == accountID else { return }
        saveReviewState(accountID, reviewState)
    }
}
