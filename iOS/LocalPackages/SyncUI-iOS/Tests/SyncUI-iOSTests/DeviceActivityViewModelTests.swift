//
//  DeviceActivityViewModelTests.swift
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

import Foundation
import Testing
@testable import SyncUI_iOS

@MainActor
struct DeviceActivityViewModelTests {

    @available(iOS 16, macOS 13, *)
    @Test("Initial fetch seeds all existing activity at the newest timestamp", .timeLimit(.minutes(1)))
    func initialFetchSeedsBaseline() async {
        let store = MemoryReviewStateStore()
        let newestDate = Date(timeIntervalSince1970: 30)
        let olderDate = Date(timeIntervalSince1970: 20)
        let model = makeModel(store: store) { _ in
            TestPage(entries: [entry("new", date: newestDate), entry("old", date: olderDate)], before: nil)
        }

        await model.loadIfNeeded()

        #expect(model.reviewState == DeviceActivityReviewState(reviewedThrough: newestDate, isInitialized: true))
        #expect(isSeen("new", in: model))
        #expect(isSeen("old", in: model))
        #expect(store.values["account-a"] == model.reviewState)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An initialized empty history leaves future events unread", .timeLimit(.minutes(1)))
    func emptyBaselineLeavesFutureEventsUnread() async {
        let store = MemoryReviewStateStore()
        var events = [DeviceActivityEntry]()
        let model = makeModel(store: store) { _ in TestPage(entries: events, before: nil) }

        await model.loadIfNeeded()
        #expect(model.reviewState == DeviceActivityReviewState(reviewedThrough: nil, isInitialized: true))

        events = [entry("future", date: Date(timeIntervalSince1970: 100))]
        model.cancelAndClear()
        await model.loadIfNeeded()

        #expect(!isSeen("future", in: model))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Same-timestamp events are grouped and screen review advances monotonically", .timeLimit(.minutes(1)))
    func timestampGroupsAndReviewStateIsMonotonic() async throws {
        let store = MemoryReviewStateStore()
        let sleeper = ControlledSleeper()
        let baseline = Date(timeIntervalSince1970: 30)
        let newer = Date(timeIntervalSince1970: 40)
        var events = [entry("baseline-a", date: baseline), entry("baseline-b", date: baseline)]
        let model = makeModel(store: store, sleep: sleeper.sleep) { _ in TestPage(entries: events, before: nil) }

        await model.loadIfNeeded()
        #expect(isSeen("baseline-a", in: model))
        #expect(isSeen("baseline-b", in: model))

        events = [entry("newer", date: newer), entry("old", date: Date(timeIntervalSince1970: 10))]
        model.cancelAndClear()
        await model.loadIfNeeded()
        #expect(!isSeen("newer", in: model))
        #expect(isSeen("old", in: model))

        let reviewTask = Task { await model.markAsReviewedAfterDelay() }
        await sleeper.waitForRequests(1)
        #expect(sleeper.requestedDurations == [3_000_000_000])
        #expect(!isSeen("newer", in: model))
        sleeper.resumeNext()
        await reviewTask.value
        #expect(isSeen("newer", in: model))
        #expect(model.reviewState.reviewedThrough == newer)

        events = [entry("old", date: Date(timeIntervalSince1970: 10))]
        model.cancelAndClear()
        await model.loadIfNeeded()
        await model.markAsReviewedAfterDelay()
        #expect(model.reviewState.reviewedThrough == newer)
        #expect(store.values["account-a"]?.reviewedThrough == newer)
        #expect(sleeper.requestedDurations.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Leaving early cancels review and reopening requires a new three-second visit", .timeLimit(.minutes(1)))
    func leavingScreenCancelsReview() async throws {
        let store = MemoryReviewStateStore()
        let sleeper = ControlledSleeper()
        let baseline = Date(timeIntervalSince1970: 100)
        store.values["account-a"] = DeviceActivityReviewState(reviewedThrough: baseline, isInitialized: true)
        let model = makeModel(store: store, sleep: sleeper.sleep) { _ in
            TestPage(entries: [entry("event", date: Date(timeIntervalSince1970: 101))], before: nil)
        }

        await model.loadIfNeeded()
        let reviewTask = Task { await model.markAsReviewedAfterDelay() }
        await sleeper.waitForRequests(1)
        reviewTask.cancel()
        model.cancelAndClear()
        sleeper.resumeNext()
        await reviewTask.value
        #expect(store.values["account-a"]?.reviewedThrough == baseline)

        await model.loadIfNeeded()
        #expect(!isSeen("event", in: model))
        let reopenedReviewTask = Task { await model.markAsReviewedAfterDelay() }
        await sleeper.waitForRequests(2)
        #expect(sleeper.requestedDurations == [3_000_000_000, 3_000_000_000])
        #expect(!isSeen("event", in: model))
        sleeper.resumeNext()
        await reopenedReviewTask.value
        #expect(isSeen("event", in: model))
    }

    @available(iOS 16, macOS 13, *)
    @Test("One screen visit reviews all history, including pages loaded later", .timeLimit(.minutes(1)))
    func screenReviewIncludesAllHistory() async {
        let store = MemoryReviewStateStore()
        let sleeper = ControlledSleeper()
        store.values["account-a"] = DeviceActivityReviewState(reviewedThrough: Date(timeIntervalSince1970: 100), isInitialized: true)
        let model = makeModel(store: store, sleep: sleeper.sleep) { cursor in
            switch cursor {
            case nil:
                return TestPage(entries: [entry("newest", date: Date(timeIntervalSince1970: 300)),
                                                    entry("middle", date: Date(timeIntervalSince1970: 250))], before: "older")
            case "older":
                return TestPage(entries: [entry("old", date: Date(timeIntervalSince1970: 200))], before: "oldest")
            default:
                return TestPage(entries: [entry("oldest", date: Date(timeIntervalSince1970: 150))], before: nil)
            }
        }

        await model.loadIfNeeded()
        let reviewTask = Task { await model.markAsReviewedAfterDelay() }
        await sleeper.waitForRequests(1)
        await model.loadOlderIfNeeded(after: "middle")
        #expect(model.entries.allSatisfy { !model.isSeen($0) })
        sleeper.resumeNext()
        await reviewTask.value
        #expect(model.entries.allSatisfy { model.isSeen($0) })
        #expect(store.values["account-a"]?.reviewedThrough == Date(timeIntervalSince1970: 300))

        await model.loadOlderIfNeeded(after: "old")
        #expect(isSeen("oldest", in: model))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Review waits for history to load before starting its three seconds", .timeLimit(.minutes(1)))
    func loadingDoesNotCountAsReviewTime() async throws {
        let store = MemoryReviewStateStore()
        let sleeper = ControlledSleeper()
        let loading = ControlledSleeper()
        let baseline = Date(timeIntervalSince1970: 100)
        store.values["account-a"] = DeviceActivityReviewState(reviewedThrough: baseline, isInitialized: true)
        let model = makeModel(store: store, sleep: sleeper.sleep) { _ in
            try await loading.sleep(0)
            return TestPage(entries: [entry("event", date: Date(timeIntervalSince1970: 101))], before: nil)
        }

        let loadTask = Task { await model.loadIfNeeded() }
        await loading.waitForRequests(1)
        await model.markAsReviewedAfterDelay()
        #expect(store.values["account-a"]?.reviewedThrough == baseline)
        #expect(sleeper.requestedDurations.isEmpty)
        loading.resumeNext()
        await loadTask.value
        #expect(!isSeen("event", in: model))

        let reviewTask = Task { await model.markAsReviewedAfterDelay() }
        await sleeper.waitForRequests(1)
        #expect(sleeper.requestedDurations == [3_000_000_000])
        #expect(!isSeen("event", in: model))
        sleeper.resumeNext()
        await reviewTask.value
        #expect(isSeen("event", in: model))
    }

    @available(iOS 16, macOS 13, *)
    @Test("An account switch prevents a pending screen review from being saved", .timeLimit(.minutes(1)))
    func accountSwitchDiscardsPendingReview() async {
        var accountID = "account-a"
        let store = MemoryReviewStateStore()
        let sleeper = ControlledSleeper()
        let baseline = DeviceActivityReviewState(reviewedThrough: Date(timeIntervalSince1970: 100), isInitialized: true)
        store.values["account-a"] = baseline
        store.values["account-b"] = baseline
        let model = DeviceActivityViewModel(accountIdentifier: { accountID }, fetchPage: { _ in
            TestPage(entries: [entry("event", date: Date(timeIntervalSince1970: 101))], before: nil)
        }, loadReviewState: store.load, saveReviewState: store.save, sleep: sleeper.sleep)

        await model.loadIfNeeded()
        let reviewTask = Task { await model.markAsReviewedAfterDelay() }
        await sleeper.waitForRequests(1)
        accountID = "account-b"
        sleeper.resumeNext()
        await reviewTask.value
        #expect(store.values["account-a"] == baseline)
        #expect(store.values["account-b"] == baseline)
        #expect(model.entries.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Review state is isolated by account and survives reopening", .timeLimit(.minutes(1)))
    func reviewStateIsAccountScopedAndRetained() async {
        let store = MemoryReviewStateStore()
        let date = Date(timeIntervalSince1970: 30)
        store.values["account-a"] = DeviceActivityReviewState(reviewedThrough: date, isInitialized: true)
        let model = DeviceActivityViewModel(accountIdentifier: { "account-a" }, fetchPage: { _ in
            TestPage(entries: [entry("event", date: date)], before: nil)
        }, loadReviewState: store.load, saveReviewState: store.save)

        await model.loadIfNeeded()
        model.cancelAndClear()
        await model.loadIfNeeded()

        #expect(store.values["account-b"] == nil)
        #expect(isSeen("event", in: model))
        #expect(store.values["account-a"]?.reviewedThrough == date)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Requests older pages across an empty page", .timeLimit(.minutes(1)))
    func paginationRequestsOlderPagesAcrossEmptyPage() async {
        var cursors = [String?]()
        let newest = entry("new", date: Date(timeIntervalSince1970: 30))
        let older = entry("old", date: Date(timeIntervalSince1970: 10))
        let model = DeviceActivityViewModel(accountIdentifier: { "account-a" }, fetchPage: { cursor in
            cursors.append(cursor)
            switch cursor {
            case nil: return TestPage(entries: [newest], before: "older-1")
            case "older-1": return TestPage(entries: [], before: "older-2")
            default: return TestPage(entries: [older], before: nil)
            }
        }, sleep: { _ in })

        await model.loadIfNeeded()
        await model.loadOlderIfNeeded(after: "new")

        #expect(cursors == [nil, "older-1", "older-2"])
        #expect(model.entries.map(\.id) == ["new", "old"])
        #expect(model.hasLoaded)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Fetch errors can be retried", .timeLimit(.minutes(1)))
    func failedInitialFetchCanBeRetried() async {
        let store = MemoryReviewStateStore()
        var cursors = [String?]()
        var shouldFail = true
        let model = makeModel(store: store) { cursor in
            cursors.append(cursor)
            if shouldFail {
                shouldFail = false
                throw TestFailure.fetch
            }
            return TestPage(entries: [], before: nil)
        }

        await model.loadIfNeeded()
        #expect(model.error != nil)
        #expect(!model.reviewState.isInitialized)
        #expect(store.values.isEmpty)
        #expect(cursors == [nil])
        model.dismissError()
        #expect(model.error == nil)
        #expect(!model.hasLoaded)
        await model.retry()
        #expect(model.error == nil)
        #expect(model.hasLoaded)
        #expect(model.reviewState == DeviceActivityReviewState(reviewedThrough: nil, isInitialized: true))
        #expect(cursors == [nil, nil])
        #expect(store.values["account-a"] == model.reviewState)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Dismissing a pagination error retains activity and its retry cursor", .timeLimit(.minutes(1)))
    func paginationFailureCanBeDismissedAndRetried() async {
        var cursors = [String?]()
        var shouldFail = true
        let newest = entry("new", date: Date(timeIntervalSince1970: 30))
        let older = entry("old", date: Date(timeIntervalSince1970: 10))
        let model = DeviceActivityViewModel(accountIdentifier: { "account-a" }, fetchPage: { cursor in
            cursors.append(cursor)
            guard cursor != nil else { return TestPage(entries: [newest], before: "older") }
            if shouldFail {
                shouldFail = false
                throw TestFailure.fetch
            }
            return TestPage(entries: [older], before: nil)
        })

        await model.loadIfNeeded()
        await model.loadOlderIfNeeded(after: "new")
        #expect(model.error != nil)
        model.dismissError()
        #expect(model.error == nil)
        #expect(model.entries.map(\.id) == ["new"])
        #expect(model.hasLoaded)

        await model.retry()
        #expect(cursors == [nil, "older", "older"])
        #expect(model.entries.map(\.id) == ["new", "old"])
        #expect(model.error == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A response from the previous account is discarded", .timeLimit(.minutes(1)))
    func accountSwitchDiscardsInFlightPage() async {
        var accountID = "account-a"
        let store = MemoryReviewStateStore()
        let model = DeviceActivityViewModel(accountIdentifier: { accountID }, fetchPage: { _ in
            accountID = "account-b"
            return TestPage(entries: [entry("old-account", date: Date())], before: nil)
        }, loadReviewState: store.load, saveReviewState: store.save)

        await model.loadIfNeeded()

        #expect(model.entries.isEmpty)
        #expect(model.hasLoaded == false)
        #expect(store.values.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Empty pages continue beyond three requests with a two-second delay before each follow-up", .timeLimit(.minutes(1)))
    func emptyPagesContinueAutomaticallyAndSeedBaseline() async {
        var cursors = [String?]()
        var delays = [UInt64]()
        let store = MemoryReviewStateStore()
        let existing = entry("existing", date: Date(timeIntervalSince1970: 30))
        let model = DeviceActivityViewModel(accountIdentifier: { "account-a" }, fetchPage: { cursor in
            cursors.append(cursor)
            #expect(store.values.isEmpty)
            if cursors.count <= 6 {
                return TestPage(entries: [], before: "cursor-\(cursors.count)")
            }
            return TestPage(entries: [existing], before: nil)
        }, loadReviewState: store.load, saveReviewState: store.save, sleep: { delays.append($0) })

        await model.loadIfNeeded()

        #expect(cursors == [nil, "cursor-1", "cursor-2", "cursor-3", "cursor-4", "cursor-5", "cursor-6"])
        #expect(delays == Array(repeating: 2_000_000_000, count: 6))
        #expect(model.entries == [existing])
        #expect(model.isSeen(existing))
        #expect(store.values["account-a"]?.reviewedThrough == existing.date)
        #expect(model.hasLoaded)
        #expect(!model.isLoading)
        #expect(model.error == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A gap of empty pages continues automatically and normal pages do not wait", .timeLimit(.minutes(1)))
    func paginationAcrossUnreadableGapContinuesAutomatically() async {
        var cursors = [String?]()
        var delays = [UInt64]()
        let newest = entry("newest", date: Date(timeIntervalSince1970: 30))
        let older = entry("older", date: Date(timeIntervalSince1970: 20))
        let oldest = entry("oldest", date: Date(timeIntervalSince1970: 10))
        let model = DeviceActivityViewModel(accountIdentifier: { "account-a" }, fetchPage: { cursor in
            cursors.append(cursor)
            switch cursor {
            case nil: return TestPage(entries: [newest], before: "gap-1")
            case "gap-1": return TestPage(entries: [], before: "gap-2")
            case "gap-2": return TestPage(entries: [], before: "gap-3")
            case "gap-3": return TestPage(entries: [], before: "older")
            case "older": return TestPage(entries: [older], before: "oldest")
            default: return TestPage(entries: [oldest], before: nil)
            }
        }, sleep: { delays.append($0) })

        await model.loadIfNeeded()
        #expect(cursors == [nil])
        #expect(delays.isEmpty)
        await model.loadOlderIfNeeded(after: newest.id)
        #expect(cursors == [nil, "gap-1", "gap-2", "gap-3", "older"])
        #expect(model.entries == [newest, older])
        #expect(delays == Array(repeating: 2_000_000_000, count: 3))

        await model.loadOlderIfNeeded(after: older.id)
        #expect(model.entries == [newest, older, oldest])
        #expect(cursors.last == "oldest")
        #expect(delays.count == 3)
        await model.loadOlderIfNeeded(after: oldest.id)
        #expect(cursors.count == 6)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An empty history is initialized only when its before cursor is absent", .timeLimit(.minutes(1)))
    func emptyHistoryContinuesUntilCursorIsAbsent() async {
        var requests = 0
        var delays = [UInt64]()
        let store = MemoryReviewStateStore()
        let model = DeviceActivityViewModel(accountIdentifier: { "account-a" }, fetchPage: { _ in
            requests += 1
            #expect(store.values.isEmpty)
            return TestPage(entries: [], before: requests < 5 ? "cursor-\(requests)" : nil)
        }, loadReviewState: store.load, saveReviewState: store.save, sleep: { delays.append($0) })

        await model.loadIfNeeded()
        #expect(requests == 5)
        #expect(delays.count == 4)
        #expect(model.reviewState == DeviceActivityReviewState(reviewedThrough: nil, isInitialized: true))
        #expect(store.values["account-a"] == model.reviewState)
        #expect(model.entries.isEmpty)
        #expect(model.hasLoaded)
        #expect(!model.isLoading)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An initial scan stops on rate limiting and retries only the failed cursor", .timeLimit(.minutes(1)))
    func failedEmptyPageContinuationRetriesSavedCursor() async {
        var cursors = [String?]()
        var delays = [UInt64]()
        let older = entry("older", date: Date(timeIntervalSince1970: 20))
        let model = DeviceActivityViewModel(accountIdentifier: { "account-a" }, fetchPage: { cursor in
            cursors.append(cursor)
            if cursors.count <= 3 {
                return TestPage(entries: [], before: "cursor-\(cursors.count)")
            }
            if cursors.count == 4 { throw NSError(domain: "AuditLog", code: 418) }
            return TestPage(entries: [older], before: nil)
        }, sleep: { delays.append($0) })

        await model.loadIfNeeded()
        #expect((model.error as NSError?)?.code == 418)
        #expect(!model.isLoading)
        #expect(!model.hasLoaded)
        #expect(!model.reviewState.isInitialized)
        #expect(cursors == [nil, "cursor-1", "cursor-2", "cursor-3"])
        #expect(delays.count == 3)
        model.dismissError()
        await model.retry()
        #expect(cursors == [nil, "cursor-1", "cursor-2", "cursor-3", "cursor-3"])
        #expect(model.entries == [older])
        #expect(model.error == nil)
        #expect(delays.count == 3)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancelling a row task during its wait clears loading without an alert and preserves progress", .timeLimit(.minutes(1)))
    func cancellingPaginationWaitResumesAtSavedCursor() async {
        var cursors = [String?]()
        var isWaiting = false
        let newest = entry("newest", date: Date(timeIntervalSince1970: 30))
        let older = entry("older", date: Date(timeIntervalSince1970: 20))
        let model = DeviceActivityViewModel(accountIdentifier: { "account-a" }, fetchPage: { cursor in
            cursors.append(cursor)
            switch cursor {
            case nil: return TestPage(entries: [newest], before: "gap")
            case "gap": return TestPage(entries: [], before: "older")
            default: return TestPage(entries: [older], before: nil)
            }
        }, sleep: { _ in
            isWaiting = true
            try await Task.sleep(nanoseconds: 60_000_000_000)
        })
        await model.loadIfNeeded()
        let rowTask = Task { await model.loadOlderIfNeeded(after: newest.id) }
        while !isWaiting { await Task.yield() }
        #expect(model.isLoading)
        rowTask.cancel()
        await rowTask.value

        #expect(!model.isLoading)
        #expect(model.error == nil)
        #expect(model.entries == [newest])
        #expect(cursors == [nil, "gap"])
        await model.loadOlderIfNeeded(after: newest.id)
        #expect(cursors == [nil, "gap", "older"])
        #expect(model.entries == [newest, older])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Closing during a wait discards the cursor and reopening starts without one", .timeLimit(.minutes(1)))
    func closingDuringWaitDiscardsCursor() async {
        var cursors = [String?]()
        var isWaiting = false
        let store = MemoryReviewStateStore()
        let existing = entry("existing", date: Date(timeIntervalSince1970: 30))
        let model = DeviceActivityViewModel(accountIdentifier: { "account-a" }, fetchPage: { cursor in
            cursors.append(cursor)
            if cursors.count == 1 { return TestPage(entries: [], before: "older") }
            return TestPage(entries: [existing], before: nil)
        }, loadReviewState: store.load, saveReviewState: store.save, sleep: { _ in
            isWaiting = true
            try await Task.sleep(nanoseconds: 60_000_000_000)
        })
        let screenTask = Task { await model.loadIfNeeded() }
        while !isWaiting { await Task.yield() }
        screenTask.cancel()
        model.cancelAndClear()
        await screenTask.value

        #expect(model.error == nil)
        #expect(!model.isLoading)
        #expect(!model.hasLoaded)
        #expect(store.values.isEmpty)
        await model.loadIfNeeded()
        #expect(cursors == [nil, nil])
        #expect(model.entries == [existing])
        #expect(model.isSeen(existing))
    }

    @available(iOS 16, macOS 13, *)
    @Test("An account switch during an empty-page wait prevents the next request", .timeLimit(.minutes(1)))
    func accountSwitchDuringWaitDiscardsCursor() async {
        var accountID = "account-a"
        var requests = 0
        let store = MemoryReviewStateStore()
        let model = DeviceActivityViewModel(accountIdentifier: { accountID }, fetchPage: { _ in
            requests += 1
            return TestPage(entries: [], before: "older")
        }, loadReviewState: store.load, saveReviewState: store.save, sleep: { _ in
            accountID = "account-b"
        })

        await model.loadIfNeeded()
        #expect(requests == 1)
        #expect(model.entries.isEmpty)
        #expect(!model.hasLoaded)
        #expect(!model.isLoading)
        #expect(model.error == nil)
        #expect(store.values.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A completed page is consumed when its row task is cancelled", .timeLimit(.minutes(1)))
    func completedPageSurvivesRowCancellation() async {
        let model = DeviceActivityViewModel(accountIdentifier: { "account-a" }, makePageFetcher: {
            return {
                withUnsafeCurrentTask { $0?.cancel() }
                return DeviceActivityPage(entries: [self.entry("completed", date: Date())], hasMore: false)
            }
        })
        let request = Task { await model.loadIfNeeded() }
        await request.value

        #expect(model.entries.map(\.id) == ["completed"])
        #expect(model.hasLoaded)
        #expect(model.error == nil)
    }

    private func isSeen(_ entryID: String, in model: DeviceActivityViewModel) -> Bool {
        guard let entry = model.entries.first(where: { $0.id == entryID }) else {
            Issue.record("Expected entry \(entryID) to be loaded")
            return false
        }
        return model.isSeen(entry)
    }

    private func makeModel(store: MemoryReviewStateStore,
                           sleep: @escaping (UInt64) async throws -> Void = { _ in },
                           fetchPage: @escaping (String?) async throws -> TestPage) -> DeviceActivityViewModel {
        DeviceActivityViewModel(accountIdentifier: { "account-a" },
                                fetchPage: fetchPage,
                                loadReviewState: store.load,
                                saveReviewState: store.save,
                                sleep: sleep)
    }

    private func entry(_ id: String, date: Date) -> DeviceActivityEntry {
        DeviceActivityEntry(id: id, action: .synced, date: date, deviceName: id, deviceType: "phone")
    }
}

private enum TestFailure: Error {
    case fetch
}

private final class MemoryReviewStateStore {
    var values = [String: DeviceActivityReviewState]()

    func load(accountID: String) -> DeviceActivityReviewState? {
        values[accountID]
    }

    func save(accountID: String, reviewState: DeviceActivityReviewState) {
        values[accountID] = reviewState
    }
}

@MainActor
private final class ControlledSleeper {
    private(set) var requestedDurations: [UInt64] = []
    private var continuations: [CheckedContinuation<Void, Error>] = []

    func sleep(_ nanoseconds: UInt64) async throws {
        requestedDurations.append(nanoseconds)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            continuations.append(continuation)
        }
        try Task.checkCancellation()
    }

    func waitForRequests(_ count: Int) async {
        while requestedDurations.count < count {
            await Task.yield()
        }
    }

    func resumeNext() {
        continuations.removeFirst().resume(returning: ())
    }
}

private struct TestPage {
    let entries: [DeviceActivityEntry]
    let before: String?
}

@MainActor
private final class TestPageReader {
    private let fetchPage: (String?) async throws -> TestPage
    private var before: String?

    init(fetchPage: @escaping (String?) async throws -> TestPage) { self.fetchPage = fetchPage }

    func nextPage() async throws -> DeviceActivityPage {
        let page = try await fetchPage(before)
        before = page.before
        return DeviceActivityPage(entries: page.entries, hasMore: before != nil)
    }
}

private extension DeviceActivityViewModel {
    convenience init(accountIdentifier: @escaping () -> String?,
                     fetchPage: @escaping (String?) async throws -> TestPage,
                     loadReviewState: @escaping (String) -> DeviceActivityReviewState? = { _ in nil },
                     saveReviewState: @escaping (String, DeviceActivityReviewState) -> Void = { _, _ in },
                     sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.init(accountIdentifier: accountIdentifier, makePageFetcher: {
            let reader = TestPageReader(fetchPage: fetchPage)
            return { try await reader.nextPage() }
        }, loadReviewState: loadReviewState, saveReviewState: saveReviewState, sleep: sleep)
    }
}
