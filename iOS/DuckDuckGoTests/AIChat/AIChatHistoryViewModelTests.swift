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

    func testNewChatTapped_notifiesDelegate() {
        let sut = makeSUT(chats: [])
        let delegate = MockDelegate()
        sut.delegate = delegate

        sut.newChatTapped()

        XCTAssertTrue(delegate.didRequestOpenNewChat)
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
    }

    func testDeleteChat_noFireExecutor_isNoOp() {
        let sut = makeSUT(chats: [chat(id: "p1", pinned: true)], fireExecutor: nil)
        // No fire executor (e.g. dependency wasn't plumbed) — must not crash; nothing to assert
        // beyond that.
        sut.deleteChat(chatId: "p1")
        processMainQueue()
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

    func testDownloadChat_onFailure_doesNotNotifyDelegate() {
        let downloader = StubDownloader()
        downloader.stubbedResult = .failure(ChatHistoryDownloader.DownloadError.chatNotFound)
        let queue = DispatchQueue(label: "test.download")
        let sut = makeSUT(chats: [chat(id: "r1", pinned: false)], downloader: downloader, mutationQueue: queue)
        let delegate = MockDelegate()
        sut.delegate = delegate

        sut.downloadChat(chatId: "r1")
        queue.sync { }
        processMainQueue()

        XCTAssertEqual(delegate.exportedFilenames, [])
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

    // MARK: - Helpers

    private func makeSUT(
        chats: [DuckAiChat],
        fireExecutor: FireExecuting? = MockChatHistoryFireExecutor(),
        downloader: ChatHistoryDownloading? = nil,
        pinner: ChatPinning? = nil,
        mutationQueue: DispatchQueue = .main
    ) -> AIChatHistoryViewModel {
        let sut = AIChatHistoryViewModel(
            reader: MockChatHistoryReader(chats: chats),
            fireExecutor: fireExecutor,
            downloader: downloader,
            pinner: pinner,
            mutationQueue: mutationQueue
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

        func viewModelDidRequestOpenNewChat() { didRequestOpenNewChat = true }
        func viewModelDidRequestOpenChat(chatId: String) { requestedChatId = chatId }
        func viewModelDidExportChat(filename: String) { exportedFilenames.append(filename) }
    }

    private final class MockChatHistoryFireExecutor: FireExecuting {
        var burnInProgress: Bool = false
        weak var delegate: FireExecutorDelegate?
        private(set) var burnedChatIds: [String] = []
        private(set) var burnedIsFireMode: [Bool] = []

        func prepare(for request: FireRequest) { }
        func burn(request: FireRequest, applicationState: DataStoreWarmup.ApplicationState) async { }
        @discardableResult
        func burnChat(chatID: String, isFireMode: Bool) async -> Result<Void, Error> {
            burnedChatIds.append(chatID)
            burnedIsFireMode.append(isFireMode)
            return .success(())
        }
    }

    private final class StubDownloader: ChatHistoryDownloading {
        var stubbedResult: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/stub.txt"))
        private(set) var requestedChatIds: [String] = []

        func downloadChat(chatId: String) throws -> URL {
            requestedChatIds.append(chatId)
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
}
