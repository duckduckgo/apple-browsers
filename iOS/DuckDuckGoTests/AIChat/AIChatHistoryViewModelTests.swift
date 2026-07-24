//
//  AIChatHistoryViewModelTests.swift
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
import XCTest
import AIChat
@testable import DuckDuckGo
@testable import Core

@MainActor
final class AIChatHistoryViewModelTests: XCTestCase {

    private typealias Section = AIChatHistoryViewModel.Section

    func testInit_splitsChatsIntoPinnedAndRecent() {
        let sut = makeSUT(chats: [
            chat(id: "p1", pinned: true),
            chat(id: "r1", pinned: false),
            chat(id: "p2", pinned: true)
        ])

        XCTAssertEqual(sut.pinned.map(\.chatId), ["p1", "p2"])
        XCTAssertEqual(sut.recent.map(\.chatId), ["r1"])
        XCTAssertTrue(sut.hasLoaded)
        XCTAssertFalse(sut.isEmpty)
        XCTAssertFalse(sut.loadFailed)
    }

    func testIsEmpty_whenReaderHasNoChats() {
        let sut = makeSUT(chats: [])
        XCTAssertTrue(sut.isEmpty)
        XCTAssertTrue(sut.hasLoaded)
    }

    func testNumberOfSections_isTwo() {
        XCTAssertEqual(makeSUT(chats: []).numberOfSections, 2)
    }

    func testNumberOfRows_perSection() {
        let sut = makeSUT(chats: [
            chat(id: "p1", pinned: true),
            chat(id: "r1", pinned: false),
            chat(id: "r2", pinned: false)
        ])
        XCTAssertEqual(sut.numberOfRows(in: Section.pinned.rawValue), 1)
        XCTAssertEqual(sut.numberOfRows(in: Section.recent.rawValue), 2)
        XCTAssertEqual(sut.numberOfRows(in: 99), 0)
    }

    func testSectionTitles_returnHeadersWhenSectionHasContent() {
        let sut = makeSUT(chats: [
            chat(id: "p1", pinned: true),
            chat(id: "r1", pinned: false)
        ])
        XCTAssertEqual(sut.title(forSection: Section.pinned.rawValue), UserText.aiChatHistoryPinnedSectionTitle)
        XCTAssertEqual(sut.title(forSection: Section.recent.rawValue), UserText.aiChatHistoryRecentSectionTitle)
    }

    func testSectionTitle_isNilForEmptySectionOrInvalidIndex() {
        let sut = makeSUT(chats: [chat(id: "r1", pinned: false)])
        XCTAssertNil(sut.title(forSection: Section.pinned.rawValue), "Empty pinned section should have no header")
        XCTAssertEqual(sut.title(forSection: Section.recent.rawValue), UserText.aiChatHistoryRecentSectionTitle)
        XCTAssertNil(sut.title(forSection: 99), "Out-of-range section should return nil")
    }

    func testTitleForRowAt_returnsChatTitleOrNilWhenOutOfBounds() {
        let sut = makeSUT(chats: [chat(id: "p1", title: "Hello world", pinned: true)])
        XCTAssertEqual(sut.title(forRowAt: IndexPath(row: 0, section: Section.pinned.rawValue)), "Hello world")
        XCTAssertNil(sut.title(forRowAt: IndexPath(row: 5, section: Section.pinned.rawValue)))
    }

    func testReaderFailure_clearsChatsAndMarksLoadedAndFailed() {
        let reader = MockChatHistoryReader(chats: [chat(id: "p1", pinned: true)])
        let sut = AIChatHistoryViewModel(reader: reader)
        processMainQueue()
        XCTAssertFalse(sut.isEmpty)
        XCTAssertFalse(sut.loadFailed)

        reader.subject.send(completion: .failure(NSError(domain: "test", code: 1)))
        processMainQueue()

        XCTAssertTrue(sut.pinned.isEmpty)
        XCTAssertTrue(sut.recent.isEmpty)
        XCTAssertTrue(sut.hasLoaded)
        XCTAssertTrue(sut.loadFailed, "Storage failure should set loadFailed so the UI can show an error, not the empty state")
    }

    func testReaderFailure_firesLoadFailedPixelOncePerTransition() {
        let reader = MockChatHistoryReader(chats: [chat(id: "p1", pinned: true)])
        let instrumentation = MockAIChatHistoryInstrumentation()
        let sut = AIChatHistoryViewModel(reader: reader, instrumentation: instrumentation)
        processMainQueue()
        XCTAssertTrue(instrumentation.loadFailedErrors.isEmpty)

        let error = NSError(domain: "test", code: 1)
        reader.subject.send(completion: .failure(error))
        processMainQueue()

        XCTAssertEqual(instrumentation.loadFailedErrors.count, 1, "The load-failure pixel should fire on the failure transition")

        // A later query keystroke recombines the cached failure through CombineLatest, re-running
        // `apply(.failure:)`. Since `loadFailed` is already true, the pixel must not re-fire.
        sut.updateQuery("hello")
        waitForDebounce()

        XCTAssertTrue(sut.loadFailed)
        XCTAssertEqual(instrumentation.loadFailedErrors.count, 1, "Re-emitted cached failures should not re-count")
    }

    func testNewChatTapped_notifiesDelegate() {
        let sut = makeSUT(chats: [])
        let delegate = MockDelegate()
        sut.delegate = delegate

        sut.newChatTapped()

        XCTAssertTrue(delegate.didRequestOpenNewChat)
    }

    func testOpenChatProtection_notifiesDelegate() {
        let sut = makeSUT(chats: [])
        let delegate = MockDelegate()
        sut.delegate = delegate

        sut.openChatProtection()

        XCTAssertTrue(delegate.didRequestChatProtection)
    }

    func testChatId_forValidIndexPath_returnsChatId() {
        let sut = makeSUT(chats: [
            chat(id: "p1", pinned: true),
            chat(id: "r1", pinned: false)
        ])

        XCTAssertEqual(sut.chatId(forRowAt: IndexPath(row: 0, section: Section.pinned.rawValue)), "p1")
        XCTAssertEqual(sut.chatId(forRowAt: IndexPath(row: 0, section: Section.recent.rawValue)), "r1")
    }

    func testChatId_forInvalidIndexPath_returnsNil() {
        let sut = makeSUT(chats: [chat(id: "p1", pinned: true)])

        XCTAssertNil(sut.chatId(forRowAt: IndexPath(row: 99, section: Section.recent.rawValue)))
    }

    func testOpenChat_notifiesDelegateWithChatId() {
        let sut = makeSUT(chats: [chat(id: "r1", pinned: false)])
        let delegate = MockDelegate()
        sut.delegate = delegate

        sut.openChat(chatId: "r1")

        XCTAssertEqual(delegate.requestedChatId, "r1")
    }

    func testDeleteChat_invokesFireExecutorBurnChat() {
        let fireExecutor = MockChatHistoryFireExecutor()
        let sut = makeSUT(chats: [chat(id: "p1", pinned: true)], fireExecutor: fireExecutor)

        sut.deleteChat(chatId: "p1")
        processMainQueue()

        XCTAssertEqual(fireExecutor.burnedChatIds, ["p1"])
        XCTAssertEqual(fireExecutor.burnedIsFireMode, [false],
                       "chat-history sheet only ever deletes persistent chats; never fire-mode")
        XCTAssertEqual(fireExecutor.scheduleSyncCallCount, 1,
                       "a successful delete must flush sync so the deletion isn't re-pulled")
    }

    func testDeleteChat_noFireExecutor_isNoOp() {
        let sut = makeSUT(chats: [chat(id: "p1", pinned: true)], fireExecutor: nil)
        // No fire executor (e.g. dependency wasn't plumbed) — must not crash; nothing to assert
        // beyond that.
        sut.deleteChat(chatId: "p1")
        processMainQueue()
    }

    func testBurnAllChats_invokesFireExecutorAndFlushesSync() {
        let fireExecutor = MockChatHistoryFireExecutor()
        let sut = makeSUT(chats: [chat(id: "p1", pinned: true)], fireExecutor: fireExecutor)

        let done = expectation(description: "burnAllChats")
        Task { await sut.burnAllChats(); done.fulfill() }
        wait(for: [done], timeout: 1)

        XCTAssertEqual(fireExecutor.burnedAllChatsIsFireMode, [false],
                       "chat-history sheet only ever clears persistent chats; never fire-mode")
        XCTAssertEqual(fireExecutor.scheduleSyncCallCount, 1,
                       "a successful clear must flush sync so the deletion isn't re-pulled")
    }

    func testBurnAllChats_noFireExecutor_isNoOp() {
        let sut = makeSUT(chats: [chat(id: "p1", pinned: true)], fireExecutor: nil)
        // No fire executor — must not crash.
        let done = expectation(description: "burnAllChats")
        Task { await sut.burnAllChats(); done.fulfill() }
        wait(for: [done], timeout: 1)
    }

    func testBurnSelectedChats_burnsEachChatAndFlushesSyncOnce() {
        let fireExecutor = MockChatHistoryFireExecutor()
        let sut = makeSUT(chats: [chat(id: "p1", pinned: true), chat(id: "r1", pinned: false), chat(id: "r2", pinned: false)],
                          fireExecutor: fireExecutor)

        let done = expectation(description: "burnSelectedChats")
        Task { await sut.burnSelectedChats(chatIds: ["p1", "r2"]); done.fulfill() }
        wait(for: [done], timeout: 1)

        XCTAssertEqual(fireExecutor.burnedChatsBatches, [["p1", "r2"]],
                       "selected chats must be burned in a single batch call, not one per chat")
        XCTAssertEqual(fireExecutor.burnedIsFireMode, [false],
                       "chat-history sheet only ever deletes persistent chats; never fire-mode")
        XCTAssertEqual(fireExecutor.scheduleSyncCallCount, 1,
                       "sync must be flushed once for the whole batch, not per chat")
    }

    func testBurnSelectedChats_emptyIds_isNoOp() {
        let fireExecutor = MockChatHistoryFireExecutor()
        let sut = makeSUT(chats: [chat(id: "p1", pinned: true)], fireExecutor: fireExecutor)

        let done = expectation(description: "burnSelectedChats")
        Task { await sut.burnSelectedChats(chatIds: []); done.fulfill() }
        wait(for: [done], timeout: 1)

        XCTAssertTrue(fireExecutor.burnedChatsBatches.isEmpty)
        XCTAssertEqual(fireExecutor.scheduleSyncCallCount, 0)
    }

    func testTotalChatCount_reflectsAllChats_notTheSearchFilteredView() {
        let sut = makeSUT(chats: [
            chat(id: "a", title: "alpha", pinned: true),
            chat(id: "b", title: "beta", pinned: false),
            chat(id: "c", title: "gamma", pinned: false)
        ])
        XCTAssertEqual(sut.totalChatCount, 3)

        sut.updateQuery("alpha")
        waitForDebounce()

        // The visible list is filtered to the single match...
        XCTAssertEqual(sut.pinned.count + sut.recent.count, 1)
        // ...but "Delete All" clears every chat, so the count must stay the full total.
        XCTAssertEqual(sut.totalChatCount, 3,
                       "totalChatCount must reflect all chats so the Fire confirmation can't understate the delete scope during a search")
    }

    func testDownloadChat_onSuccess_notifiesDelegateWithWrittenFilename() {
        let downloader = StubDownloader()
        downloader.stubbedResult = .success(URL(fileURLWithPath: "/tmp/duck.ai_2026-01-01_00-00-00.txt"))
        let queue = DispatchQueue(label: "test.download")
        let sut = makeSUT(chats: [chat(id: "r1", pinned: false)], downloader: downloader, mutationQueue: queue)
        let delegate = MockDelegate()
        sut.delegate = delegate

        sut.downloadChat(chatId: "r1")
        queue.sync { }       // drain the off-main work
        processMainQueue()   // drain the hop-back

        XCTAssertEqual(downloader.requestedChatIds, ["r1"])
        XCTAssertEqual(delegate.exportedFilenames, ["duck.ai_2026-01-01_00-00-00.txt"])
    }

    func testDownloadChat_onFailure_notifiesFailureAndNotSuccess() {
        let downloader = StubDownloader()
        downloader.stubbedResult = .failure(ChatHistoryDownloader.DownloadError.chatNotFound)
        let queue = DispatchQueue(label: "test.download")
        let sut = makeSUT(chats: [chat(id: "r1", pinned: false)], downloader: downloader, mutationQueue: queue)
        let delegate = MockDelegate()
        sut.delegate = delegate

        sut.downloadChat(chatId: "r1")
        queue.sync { }
        processMainQueue()

        XCTAssertEqual(delegate.exportedFilenames, [], "a failed download must not fire the success toast")
        XCTAssertTrue(delegate.didFailExport, "a failed single download surfaces the error toast")
    }

    func testDownloadSelectedChats_downloadsEachSeparatelyAndNotifiesDelegateOnceWithCount() {
        let downloader = StubDownloader()
        let queue = DispatchQueue(label: "test.download")
        let sut = makeSUT(chats: [chat(id: "r1", pinned: false), chat(id: "r2", pinned: false), chat(id: "r3", pinned: false)],
                          downloader: downloader, mutationQueue: queue)
        let delegate = MockDelegate()
        sut.delegate = delegate

        sut.downloadSelectedChats(chatIds: ["r1", "r3"])
        queue.sync { }
        processMainQueue()

        XCTAssertEqual(downloader.requestedChatIds, ["r1", "r3"], "each selected chat is downloaded as its own file")
        XCTAssertEqual(delegate.exportedChatCounts, [2], "the delegate is notified once with the number that saved")
        XCTAssertEqual(delegate.exportedFilenames, [], "batch download must not fire the single-file toast")
    }

    func testDownloadSelectedChats_partialFailure_notifiesWithSuccessCountOnly() {
        let downloader = StubDownloader()
        downloader.failingChatIds = ["r2"]
        let queue = DispatchQueue(label: "test.download")
        let sut = makeSUT(chats: [chat(id: "r1", pinned: false), chat(id: "r2", pinned: false), chat(id: "r3", pinned: false)],
                          downloader: downloader, mutationQueue: queue)
        let delegate = MockDelegate()
        sut.delegate = delegate

        sut.downloadSelectedChats(chatIds: ["r1", "r2", "r3"])
        queue.sync { }
        processMainQueue()

        XCTAssertEqual(downloader.requestedChatIds, ["r1", "r2", "r3"], "a failure must not abort the rest of the batch")
        XCTAssertEqual(delegate.exportedChatCounts, [2], "count reflects only the chats that actually saved")
        XCTAssertFalse(delegate.didFailExport, "partial success shows the success toast, not the error")
    }

    func testDownloadSelectedChats_allFailures_notifiesFailure() {
        let downloader = StubDownloader()
        downloader.failingChatIds = ["r1", "r2"]
        let queue = DispatchQueue(label: "test.download")
        let sut = makeSUT(chats: [chat(id: "r1", pinned: false), chat(id: "r2", pinned: false)],
                          downloader: downloader, mutationQueue: queue)
        let delegate = MockDelegate()
        sut.delegate = delegate

        sut.downloadSelectedChats(chatIds: ["r1", "r2"])
        queue.sync { }
        processMainQueue()

        XCTAssertEqual(delegate.exportedChatCounts, [], "no success toast when nothing saved")
        XCTAssertTrue(delegate.didFailExport, "an all-failed batch surfaces the error toast")
    }

    func testDownloadSelectedChats_emptyIds_isNoOp() {
        let downloader = StubDownloader()
        let queue = DispatchQueue(label: "test.download")
        let sut = makeSUT(chats: [chat(id: "r1", pinned: false)], downloader: downloader, mutationQueue: queue)
        let delegate = MockDelegate()
        sut.delegate = delegate

        sut.downloadSelectedChats(chatIds: [])
        queue.sync { }
        processMainQueue()

        XCTAssertEqual(downloader.requestedChatIds, [])
        XCTAssertEqual(delegate.exportedChatCounts, [])
        XCTAssertFalse(delegate.didFailExport, "empty selection is a no-op, not a failure")
    }

    // MARK: - Pin

    func testIsPinned_returnsTrueForChatsInPinnedSection_falseOtherwise() {
        let sut = makeSUT(chats: [
            chat(id: "p1", pinned: true),
            chat(id: "r1", pinned: false)
        ])

        XCTAssertTrue(sut.isPinned(chatId: "p1"))
        XCTAssertFalse(sut.isPinned(chatId: "r1"))
        XCTAssertFalse(sut.isPinned(chatId: "missing"))
    }

    func testTogglePin_noPinner_returnsNilAndIsNoOp() {
        let sut = makeSUT(chats: [chat(id: "r1", pinned: false)], pinner: nil)

        let move = sut.togglePin(chatId: "r1")

        XCTAssertNil(move)
        XCTAssertEqual(sut.recent.map(\.chatId), ["r1"])
        XCTAssertEqual(sut.pinned, [])
    }

    func testTogglePin_pinningRecentChat_movesItToPinnedSectionAndReturnsIndexPaths() {
        let pinner = StubPinner()
        let sut = makeSUT(
            chats: [chat(id: "r1", pinned: false), chat(id: "r2", pinned: false)],
            pinner: pinner
        )

        let move = sut.togglePin(chatId: "r1")

        XCTAssertEqual(move?.source, IndexPath(row: 0, section: AIChatHistoryViewModel.Section.recent.rawValue))
        XCTAssertEqual(move?.destination, IndexPath(row: 0, section: AIChatHistoryViewModel.Section.pinned.rawValue))
        XCTAssertEqual(sut.pinned.map(\.chatId), ["r1"])
        XCTAssertEqual(sut.recent.map(\.chatId), ["r2"])
        processMainQueue()
        XCTAssertEqual(pinner.calls.map(\.chatId), ["r1"])
        XCTAssertEqual(pinner.calls.map(\.pinned), [true])
    }

    func testTogglePin_unpinningPinnedChat_movesItToRecentSection() {
        let pinner = StubPinner()
        let sut = makeSUT(
            chats: [chat(id: "p1", pinned: true), chat(id: "r1", pinned: false)],
            pinner: pinner
        )

        let move = sut.togglePin(chatId: "p1")

        XCTAssertEqual(move?.source, IndexPath(row: 0, section: AIChatHistoryViewModel.Section.pinned.rawValue))
        XCTAssertEqual(move?.destination.section, AIChatHistoryViewModel.Section.recent.rawValue)
        XCTAssertEqual(sut.pinned, [])
        XCTAssertEqual(sut.recent.map(\.chatId).sorted(), ["p1", "r1"])
        processMainQueue()
        XCTAssertEqual(pinner.calls.map(\.pinned), [false])
    }

    func testTogglePin_insertsAtCorrectPositionByLastEditDescending() {
        let pinner = StubPinner()
        let sut = makeSUT(chats: [
            chat(id: "p_old", lastEdit: "2026-01-01T00:00:00.000Z", pinned: true),
            chat(id: "p_new", lastEdit: "2026-05-01T00:00:00.000Z", pinned: true),
            chat(id: "r_mid", lastEdit: "2026-03-01T00:00:00.000Z", pinned: false)
        ], pinner: pinner)

        let move = sut.togglePin(chatId: "r_mid")

        XCTAssertEqual(move?.destination, IndexPath(row: 1, section: AIChatHistoryViewModel.Section.pinned.rawValue))
        XCTAssertEqual(sut.pinned.map(\.chatId), ["p_new", "r_mid", "p_old"])
    }

    func testTogglePin_chatNotFound_returnsNilAndDoesNotCallPinner() {
        let pinner = StubPinner()
        let sut = makeSUT(chats: [chat(id: "r1", pinned: false)], pinner: pinner)

        let move = sut.togglePin(chatId: "missing")

        XCTAssertNil(move)
        processMainQueue()
        XCTAssertEqual(pinner.requestedChatIds, [])
    }

    func testTogglePin_pinnerThrows_doesNotRevertOptimisticState() {
        let pinner = StubPinner()
        pinner.throwsError = .someError
        let queue = DispatchQueue(label: "test.pin")
        let sut = makeSUT(chats: [chat(id: "r1", pinned: false)], pinner: pinner, mutationQueue: queue)

        let move = sut.togglePin(chatId: "r1")
        queue.sync { }
        processMainQueue()

        XCTAssertNotNil(move)
        XCTAssertEqual(sut.pinned.map(\.chatId), ["r1"])
        XCTAssertEqual(pinner.requestedChatIds, ["r1"])
    }

    // MARK: - Search

    func testUpdateQuery_filtersChatsByTitleCaseInsensitive() {
        let sut = makeSUT(chats: [
            chat(id: "1", title: "Dog walking tips", pinned: false),
            chat(id: "2", title: "Cat food", pinned: false),
            chat(id: "3", title: "Doggy daycare", pinned: true)
        ])

        sut.updateQuery("dog")
        waitForDebounce()

        XCTAssertEqual(sut.pinned.map(\.chatId), ["3"])
        XCTAssertEqual(sut.recent.map(\.chatId), ["1"])
    }

    func testUpdateQuery_whenEmpty_returnsAllChats() {
        let sut = makeSUT(chats: [
            chat(id: "1", title: "Foo", pinned: false),
            chat(id: "2", title: "Bar", pinned: true)
        ])

        sut.updateQuery("dog")
        waitForDebounce()
        sut.updateQuery("")
        waitForDebounce()

        XCTAssertEqual(sut.pinned.count, 1)
        XCTAssertEqual(sut.recent.count, 1)
    }

    func testUpdateQuery_whenWhitespaceOnly_returnsAllChats() {
        let sut = makeSUT(chats: [chat(id: "1", title: "Foo", pinned: false)])

        sut.updateQuery("   ")
        waitForDebounce()

        XCTAssertEqual(sut.recent.count, 1)
    }

    func testUpdateQuery_whitespaceOnly_leavesEffectiveQueryEmpty() {
        // The filter trims whitespace; `effectiveQuery` must reflect that, otherwise the
        // VC's no-results-cell check reads a whitespace-only query as a real search and
        // shows "No matches found" when the user actually just has no chats.
        let sut = makeSUT(chats: [])
        sut.updateQuery("   ")
        waitForDebounce()

        XCTAssertEqual(sut.effectiveQuery, "")
    }

    func testUpdateQuery_whenNoMatches_isEmpty() {
        let sut = makeSUT(chats: [chat(id: "1", title: "Foo", pinned: false)])

        sut.updateQuery("nonexistent")
        waitForDebounce()

        XCTAssertTrue(sut.isEmpty)
    }

    func testEffectiveQuery_lagsLiveQueryUntilDebounceFires() {
        let sut = makeSUT(chats: [chat(id: "1", title: "Foo", pinned: false)])

        sut.updateQuery("foo")
        // Before the debounce fires `query` reflects the user's input but `effectiveQuery`
        // — the query that produced the current `pinned`/`recent` — must still be the
        // previous value, otherwise the empty-state decision races with the filter.
        XCTAssertEqual(sut.query, "foo")
        XCTAssertEqual(sut.effectiveQuery, "")

        waitForDebounce()
        XCTAssertEqual(sut.effectiveQuery, "foo")
    }

    // MARK: - Instrumentation

    func testScreenDidLoad_firesScreenShownWithConfiguredSource() {
        let instrumentation = MockAIChatHistoryInstrumentation()
        let sut = makeSUT(chats: [], source: .contextualChat, instrumentation: instrumentation)

        sut.screenDidLoad()

        XCTAssertEqual(instrumentation.screenShownSources, [.contextualChat])
    }

    func testOpenChat_firesChatOpened() {
        let instrumentation = MockAIChatHistoryInstrumentation()
        let sut = makeSUT(chats: [chat(id: "r1", pinned: false)], instrumentation: instrumentation)

        sut.openChat(chatId: "r1")

        XCTAssertEqual(instrumentation.chatOpenedCount, 1)
    }

    func testDeleteChat_firesChatDeleted() {
        let instrumentation = MockAIChatHistoryInstrumentation()
        let sut = makeSUT(chats: [chat(id: "p1", pinned: true)], instrumentation: instrumentation)

        sut.deleteChat(chatId: "p1")
        processMainQueue()

        XCTAssertEqual(instrumentation.chatDeletedCount, 1)
    }

    func testNewChatTapped_firesNewChatTapped() {
        let instrumentation = MockAIChatHistoryInstrumentation()
        let sut = makeSUT(chats: [], instrumentation: instrumentation)

        sut.newChatTapped()

        XCTAssertEqual(instrumentation.newChatTappedCount, 1)
    }

    func testEmptyStateCTATapped_firesEmptyCTATappedAndOpensNewChat() {
        let instrumentation = MockAIChatHistoryInstrumentation()
        let sut = makeSUT(chats: [], instrumentation: instrumentation)
        let delegate = MockDelegate()
        sut.delegate = delegate

        sut.emptyStateCTATapped()

        XCTAssertEqual(instrumentation.emptyCTATappedCount, 1)
        XCTAssertTrue(delegate.didRequestOpenNewChat)
    }

    func testBurnAllChats_firesFireAllConfirmed() {
        let instrumentation = MockAIChatHistoryInstrumentation()
        let sut = makeSUT(chats: [chat(id: "p1", pinned: true)], instrumentation: instrumentation)

        let done = expectation(description: "burnAllChats")
        Task { await sut.burnAllChats(); done.fulfill() }
        wait(for: [done], timeout: 1)

        XCTAssertEqual(instrumentation.fireAllConfirmedCount, 1)
    }

    func testTogglePin_pinningFiresPinAdded_unpinningFiresPinRemoved() {
        let instrumentation = MockAIChatHistoryInstrumentation()
        let sut = makeSUT(
            chats: [chat(id: "r1", pinned: false), chat(id: "p1", pinned: true)],
            pinner: StubPinner(),
            instrumentation: instrumentation
        )

        sut.togglePin(chatId: "r1")
        XCTAssertEqual(instrumentation.pinAddedCount, 1)
        XCTAssertEqual(instrumentation.pinRemovedCount, 0)

        sut.togglePin(chatId: "p1")
        XCTAssertEqual(instrumentation.pinRemovedCount, 1)
        XCTAssertEqual(instrumentation.pinAddedCount, 1)
    }

    func testDownloadChat_firesDownloadStarted() {
        let instrumentation = MockAIChatHistoryInstrumentation()
        let queue = DispatchQueue(label: "test.download")
        let sut = makeSUT(chats: [chat(id: "r1", pinned: false)],
                          downloader: StubDownloader(),
                          mutationQueue: queue,
                          instrumentation: instrumentation)

        sut.downloadChat(chatId: "r1")

        XCTAssertEqual(instrumentation.downloadStartedCount, 1)
    }

    func testSearchAndEditModeAndFireAll_fireTheirPixels() {
        let instrumentation = MockAIChatHistoryInstrumentation()
        let sut = makeSUT(chats: [], instrumentation: instrumentation)

        sut.searchActivated()
        sut.editModeEntered()
        sut.fireAllTapped()

        XCTAssertEqual(instrumentation.searchActivatedCount, 1)
        XCTAssertEqual(instrumentation.editModeEnteredCount, 1)
        XCTAssertEqual(instrumentation.fireAllTappedCount, 1)
    }

    // MARK: - Helpers

    private func makeSUT(
        chats: [DuckAiChat],
        fireExecutor: FireExecuting? = MockChatHistoryFireExecutor(),
        downloader: ChatHistoryDownloading? = nil,
        pinner: ChatPinning? = nil,
        source: AIChatHistorySource = .browserMenu,
        mutationQueue: DispatchQueue = .main,
        instrumentation: AIChatHistoryInstrumentation = MockAIChatHistoryInstrumentation()
    ) -> AIChatHistoryViewModel {
        let sut = AIChatHistoryViewModel(
            reader: MockChatHistoryReader(chats: chats),
            fireExecutor: fireExecutor,
            downloader: downloader,
            pinner: pinner,
            source: source,
            mutationQueue: mutationQueue,
            instrumentation: instrumentation
        )
        processMainQueue() // reader delivers on the main queue; let it drain before asserting
        return sut
    }

    private func chat(id: String,
                      title: String = "Title",
                      model: String = "gpt-4o-mini",
                      lastEdit: String = "2026-05-01T00:00:00.000Z",
                      pinned: Bool) -> DuckAiChat {
        DuckAiChat(chatId: id, title: title, model: model, lastEdit: lastEdit, pinned: pinned)
    }

    /// Drains pending `DispatchQueue.main.async` work. FIFO ordering guarantees the view model's
    /// (already-enqueued) value delivery runs before this fulfillment block.
    private func processMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    /// Waits past the 150ms debounce window so the view model can emit the latest query value.
    private func waitForDebounce() {
        let drained = expectation(description: "debounce drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    private final class MockDelegate: AIChatHistoryViewModelDelegate {
        private(set) var didRequestOpenNewChat = false
        private(set) var requestedChatId: String?
        private(set) var exportedFilenames: [String] = []
        private(set) var exportedChatCounts: [Int] = []
        private(set) var didFailExport = false
        private(set) var didRequestChatProtection = false

        func viewModelDidRequestOpenNewChat() { didRequestOpenNewChat = true }
        func viewModelDidRequestOpenChat(chatId: String) { requestedChatId = chatId }
        func viewModelDidExportChat(filename: String) { exportedFilenames.append(filename) }
        func viewModelDidExportChats(count: Int) { exportedChatCounts.append(count) }
        func viewModelDidFailExport() { didFailExport = true }
        func viewModelDidRequestChatProtection() { didRequestChatProtection = true }
    }

    private final class MockChatHistoryFireExecutor: FireExecuting {
        var burnInProgress: Bool = false
        weak var delegate: FireExecutorDelegate?
        private(set) var burnedChatIds: [String] = []
        private(set) var burnedIsFireMode: [Bool] = []
        private(set) var burnedAllChatsIsFireMode: [Bool] = []
        private(set) var scheduleSyncCallCount = 0

        func prepare(for request: FireRequest) { }
        func burn(request: FireRequest, applicationState: DataStoreWarmup.ApplicationState) async { }
        @discardableResult
        func burnChat(chatID: String, isFireMode: Bool) async -> Result<Void, Error> {
            burnedChatIds.append(chatID)
            burnedIsFireMode.append(isFireMode)
            return .success(())
        }
        private(set) var burnedChatsBatches: [[String]] = []
        @discardableResult
        func burnChats(chatIDs: [String], isFireMode: Bool) async -> Result<Void, Error> {
            burnedChatsBatches.append(chatIDs)
            burnedIsFireMode.append(isFireMode)
            return .success(())
        }
        @discardableResult
        func burnAllChats(isFireMode: Bool) async -> Result<Void, Error> {
            burnedAllChatsIsFireMode.append(isFireMode)
            return .success(())
        }
        func scheduleSync() {
            scheduleSyncCallCount += 1
        }
    }

    private final class StubDownloader: ChatHistoryDownloading {
        var stubbedResult: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/stub.txt"))
        /// Chat ids in this set throw `chatNotFound`; all others resolve to `stubbedResult`.
        var failingChatIds: Set<String> = []
        private(set) var requestedChatIds: [String] = []

        func downloadChat(chatId: String) throws -> URL {
            requestedChatIds.append(chatId)
            if failingChatIds.contains(chatId) {
                throw ChatHistoryDownloader.DownloadError.chatNotFound
            }
            return try stubbedResult.get()
        }
    }

    private final class StubPinner: ChatPinning {
        enum StubError: Error { case someError }
        var throwsError: StubError?
        private(set) var calls: [(chatId: String, pinned: Bool)] = []
        var requestedChatIds: [String] { calls.map(\.chatId) }

        func setPinned(chatId: String, pinned: Bool) throws {
            calls.append((chatId, pinned))
            if let throwsError { throw throwsError }
        }
    }

    private final class MockAIChatHistoryInstrumentation: AIChatHistoryInstrumentation {
        private(set) var screenShownSources: [AIChatHistorySource] = []
        private(set) var chatOpenedCount = 0
        private(set) var chatDeletedCount = 0
        private(set) var emptyCTATappedCount = 0
        private(set) var searchActivatedCount = 0
        private(set) var fireAllTappedCount = 0
        private(set) var fireAllConfirmedCount = 0
        private(set) var pinAddedCount = 0
        private(set) var pinRemovedCount = 0
        private(set) var downloadStartedCount = 0
        private(set) var editModeEnteredCount = 0
        private(set) var newChatTappedCount = 0
        private(set) var loadFailedErrors: [Error] = []
        private(set) var pinToggleFailedErrors: [Error] = []
        private(set) var downloadFailedErrors: [Error] = []

        func screenShown(source: AIChatHistorySource) { screenShownSources.append(source) }
        func chatOpened() { chatOpenedCount += 1 }
        func chatDeleted() { chatDeletedCount += 1 }
        func emptyCTATapped() { emptyCTATappedCount += 1 }
        func searchActivated() { searchActivatedCount += 1 }
        func fireAllTapped() { fireAllTappedCount += 1 }
        func fireAllConfirmed() { fireAllConfirmedCount += 1 }
        func pinAdded() { pinAddedCount += 1 }
        func pinRemoved() { pinRemovedCount += 1 }
        func downloadStarted() { downloadStartedCount += 1 }
        func editModeEntered() { editModeEnteredCount += 1 }
        func newChatTapped() { newChatTappedCount += 1 }
        func loadFailed(error: Error) { loadFailedErrors.append(error) }
        func pinToggleFailed(error: Error) { pinToggleFailedErrors.append(error) }
        func downloadFailed(error: Error) { downloadFailedErrors.append(error) }
    }
}
