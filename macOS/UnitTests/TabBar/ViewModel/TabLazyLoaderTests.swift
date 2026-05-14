//
//  TabLazyLoaderTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import XCTest
import Combine
import Navigation
@testable import DuckDuckGo_Privacy_Browser

private final class TabMock: LazyLoadable {

    var isLazyLoadingInProgress: Bool = false

    var isUrl: Bool = true
    var url: URL? = "https://example.com".url
    var webViewSize: CGSize = .zero

    var loadingFinishedSubject = PassthroughSubject<TabMock, Never>()
    lazy var loadingFinishedPublisher: AnyPublisher<TabMock, Never> = loadingFinishedSubject.eraseToAnyPublisher()

    func isNewer(than other: TabMock) -> Bool { isNewerClosure(other) }
    @discardableResult
    func reload() -> ExpectedNavigation? { reloadClosure(self); return nil }

    var isNewerClosure: (TabMock) -> Bool = { _ in true }
    var reloadClosure: (TabMock) -> Void = { _ in }

    var selectedTimestamp: Date

    init(
        isUrl: Bool = true,
        url: URL? = "https://example.com".url,
        webViewSize: CGSize = .zero,
        reloadExpectation: XCTestExpectation? = nil,
        selectedTimestamp: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.isUrl = isUrl
        self.url = url
        self.webViewSize = webViewSize
        self.selectedTimestamp = selectedTimestamp

        isNewerClosure = { [unowned self] other in
            self.selectedTimestamp > other.selectedTimestamp
        }

        reloadClosure = { tab in
            // instantly notify that loading has finished (or failed)
            Task { @MainActor in
                reloadExpectation?.fulfill()
                tab.loadingFinishedSubject.send(tab)
            }
        }
    }

    static let mockUrl = TabMock()
    static let mockNotUrl = TabMock(isUrl: false, url: nil)
}

private final class TabLazyLoaderDataSourceMock: TabLazyLoaderDataSource {

    typealias Tab = TabMock

    var loadedPinnedTabs: [Tab] = []
    var loadedTabs: [Tab] = []
    var selectedTab: Tab?
    var selectedTabIndex: TabIndex?
    var selectedTabPublisher: AnyPublisher<Tab, Never> {
        selectedTabSubject.eraseToAnyPublisher()
    }

    var selectedTabSubject = PassthroughSubject<Tab, Never>()

    var isSelectedTabLoading: Bool = false
    var isSelectedTabLoadingPublisher: AnyPublisher<Bool, Never> {
        isSelectedTabLoadingSubject.eraseToAnyPublisher()
    }

    var isSelectedTabLoadingSubject = PassthroughSubject<Bool, Never>()

    var totalTabCount: Int = 0
    var unloadedTabCount: Int = 0
    var isUnloadedHandler: (Int) -> Bool = { _ in false }
    func isUnloaded(at index: Int) -> Bool { isUnloadedHandler(index) }
    var materializeHandler: (TabIndex) -> TabMock? = { _ in nil }
    func materialize(at index: TabIndex) -> TabMock? { materializeHandler(index) }
}

class TabLazyLoaderTests: XCTestCase {

    private var dataSource: TabLazyLoaderDataSourceMock!
    var cancellables = Set<AnyCancellable>()

    override func setUp() {
        dataSource = TabLazyLoaderDataSourceMock()
        cancellables.removeAll()
    }

    override func tearDown() {
        cancellables = []
        dataSource = nil
    }

    func testWhenThereAreNoTabsThenLazyLoaderIsNotInstantiated() throws {
        dataSource.loadedTabs = []
        XCTAssertNil(TabLazyLoader(dataSource: dataSource))
    }

    func testWhenThereAreNoUrlTabsThenLazyLoaderIsNotInstantiated() throws {
        dataSource.loadedTabs = [.mockNotUrl, .mockNotUrl]
        XCTAssertNil(TabLazyLoader(dataSource: dataSource))
    }

    func testWhenThereIsOneUrlTabAndItIsCurrentlySelectedThenLazyLoaderIsNotInstantiated() throws {
        let urlTab = TabMock.mockUrl
        dataSource.loadedTabs = [.mockNotUrl, .mockNotUrl, urlTab]
        dataSource.selectedTab = urlTab
        XCTAssertNil(TabLazyLoader(dataSource: dataSource))
    }

    func testWhenThereIsOneUrlTabAndItIsNotCurrentlySelectedThenLazyLoaderIsInstantiated() throws {
        let notUrlTab = TabMock.mockUrl
        dataSource.loadedTabs = [.mockNotUrl, notUrlTab, .mockUrl]
        dataSource.selectedTab = notUrlTab
        XCTAssertNotNil(TabLazyLoader(dataSource: dataSource))
    }

    func testWhenThereIsNoSelectedTabThenLazyLoadingIsSkipped() throws {
        dataSource.loadedTabs = [.mockUrl]
        dataSource.selectedTab = nil

        let lazyLoader = TabLazyLoader(dataSource: dataSource)

        var didFinishEvents: [Bool] = []
        lazyLoader?.lazyLoadingDidFinishPublisher
            .sink(receiveValue: { value in
                didFinishEvents.append(value)
            })
            .store(in: &cancellables)

        lazyLoader?.scheduleLazyLoading()

        XCTAssertEqual(didFinishEvents.count, 1)
        XCTAssertEqual(try XCTUnwrap(didFinishEvents.first), false)
    }

    func testWhenSelectedTabIsNotUrlThenLazyLoadingStartsImmediately() async throws {
        let reloadExpectation = expectation(description: "TabMock.reload() called")
        reloadExpectation.expectedFulfillmentCount = 2

        dataSource.loadedTabs = [
            .mockNotUrl,
            TabMock(isUrl: true, reloadExpectation: reloadExpectation),
            TabMock(isUrl: true, reloadExpectation: reloadExpectation)
        ]
        dataSource.selectedTab = dataSource.loadedTabs.first

        let lazyLoader = try XCTUnwrap(TabLazyLoader(dataSource: dataSource))

        await waitForLoadingDidFinishEvent(lazyLoader, and: [reloadExpectation]) {
            lazyLoader.scheduleLazyLoading()
        }
    }

    func testThatLazyLoadingStartsAfterCurrentUrlTabFinishesLoading() async throws {
        let reloadExpectation = expectation(description: "TabMock.reload() called")
        reloadExpectation.expectedFulfillmentCount = 2

        let selectedUrlTab = TabMock.mockUrl

        dataSource.loadedTabs = [
            selectedUrlTab,
            TabMock(isUrl: true, reloadExpectation: reloadExpectation),
            TabMock(isUrl: true, reloadExpectation: reloadExpectation)
        ]
        dataSource.selectedTab = dataSource.loadedTabs.first

        let lazyLoader = try XCTUnwrap(TabLazyLoader(dataSource: dataSource))

        await waitForLoadingDidFinishEvent(lazyLoader, and: [reloadExpectation]) {
            lazyLoader.scheduleLazyLoading()
            selectedUrlTab.reload()
        }
    }

    func testThatLazyLoadingDoesNotStartIfCurrentUrlTabDoesNotFinishLoading() async throws {
        let reloadExpectation = expectation(description: "TabMock.reload() called")
        reloadExpectation.isInverted = true

        dataSource.loadedTabs = [
            .mockUrl,
            TabMock(isUrl: true, reloadExpectation: reloadExpectation),
            TabMock(isUrl: true, reloadExpectation: reloadExpectation)
        ]
        dataSource.selectedTab = dataSource.loadedTabs.first

        let lazyLoader = TabLazyLoader(dataSource: dataSource)

        lazyLoader?.lazyLoadingDidFinishPublisher.sink { _ in
            XCTFail("Unexpected didFinish event")
        }.store(in: &cancellables)

        // When
        lazyLoader?.scheduleLazyLoading()

        // Then
        await fulfillment(of: [reloadExpectation], timeout: 0.1)
    }

    func testThatLazyLoadingStopsAfterLoadingMaximumNumberOfTabs() async throws {
        let maxNumberOfLazyLoadedTabs = TabLazyLoader<TabLazyLoaderDataSourceMock>.Const.maxNumberOfLazyLoadedTabs
        let reloadExpectation = expectation(description: "TabMock.reload() called")
        reloadExpectation.expectedFulfillmentCount = maxNumberOfLazyLoadedTabs

        dataSource.loadedTabs = [.mockNotUrl]
        for _ in 0..<(2 * maxNumberOfLazyLoadedTabs) {
            dataSource.loadedTabs.append(TabMock(isUrl: true, reloadExpectation: reloadExpectation))
        }
        dataSource.selectedTab = dataSource.loadedTabs.first

        let lazyLoader = try XCTUnwrap(TabLazyLoader(dataSource: dataSource))

        await waitForLoadingDidFinishEvent(lazyLoader, and: [reloadExpectation]) {
            lazyLoader.scheduleLazyLoading()
        }
    }

    func testThatLazyLoadingSkipsTabsSelectedInCurrentSession() async throws {
        let reloadExpectation = expectation(description: "TabMock.reload() called")
        reloadExpectation.expectedFulfillmentCount = 2

        let selectedUrlTab = TabMock.mockUrl

        dataSource.loadedTabs = [
            selectedUrlTab,
            TabMock(isUrl: true, reloadExpectation: reloadExpectation),
            TabMock(isUrl: true, reloadExpectation: reloadExpectation), // we expect this to be lazy loaded
            TabMock(isUrl: true, reloadExpectation: reloadExpectation), // we expect this to be lazy loaded
            TabMock(isUrl: true, reloadExpectation: reloadExpectation),
            TabMock(isUrl: true, reloadExpectation: reloadExpectation)
        ]
        dataSource.selectedTab = selectedUrlTab

        let lazyLoader = try XCTUnwrap(TabLazyLoader(dataSource: dataSource))

        await waitForLoadingDidFinishEvent(lazyLoader, and: [reloadExpectation]) {
            lazyLoader.scheduleLazyLoading()

            dataSource.selectedTabSubject.send(dataSource.loadedTabs[1])
            dataSource.selectedTabSubject.send(dataSource.loadedTabs[4])
            dataSource.selectedTabSubject.send(dataSource.loadedTabs[5])

            selectedUrlTab.reload()
        }
    }

    func testWhenTabNumberExceedsMaximumForLazyLoadingThenAdjacentTabsAreLoadedFirst() async throws {
        let maxNumberOfLazyLoadedTabs = TabLazyLoader<TabLazyLoaderDataSourceMock>.Const.maxNumberOfLazyLoadedTabs
        let reloadExpectation = expectation(description: "TabMock.reload() called")
        reloadExpectation.expectedFulfillmentCount = maxNumberOfLazyLoadedTabs + 1

        var reloadedTabsIndices = [Int]()

        // add 2 * max number tabs, ordered by selected timestamp ascending
        for i in 0..<(2 * maxNumberOfLazyLoadedTabs) {
            let tab = TabMock(isUrl: true, url: "http://\(i).com".url!, selectedTimestamp: Date(timeIntervalSince1970: .init(i)))
            tab.reloadClosure = { tab in
                Task { @MainActor in
                    reloadedTabsIndices.append(i)
                    tab.loadingFinishedSubject.send(tab)
                    reloadExpectation.fulfill()
                }
            }
            dataSource.loadedTabs.append(tab)
        }

        // select tab #3, this will cause loading tabs adjacent to #3, and then from the end of the array (based on timestamp)
        dataSource.selectedTab = dataSource.loadedTabs[3]
        dataSource.selectedTabIndex = .unpinned(3)

        let lazyLoader = try XCTUnwrap(TabLazyLoader(dataSource: dataSource))

        await waitForLoadingDidFinishEvent(lazyLoader, and: [reloadExpectation]) {
            lazyLoader.scheduleLazyLoading()
            dataSource.selectedTab?.reload()
        }

        XCTAssertEqual(reloadedTabsIndices, [3, 4, 2, 5, 1, 6, 0, 7, 8, 9, 10, 39, 38, 37, 36, 35, 34, 33, 32, 31, 30])
    }

    /**
     * This test sets up 2 tabs suitable for lazy loading.
     * When the first one is lazy loaded, it artificially triggers currently selected tab reload.
     * This effectively pauses lazy loading and prevents the other tab from being reloaded
     * until currently selected tab is marked as done loading.
     */
    func testWhenSelectedTabIsLoadingThenLazyLoadingIsPaused() async throws {
        var reloadedTabsUrls = [URL?]()

        let tabReloadClosure: (TabMock) -> Void = { tab in
            reloadedTabsUrls.append(tab.url)
            tab.loadingFinishedSubject.send(tab)
        }

        let oldTab = TabMock(isUrl: true, url: "http://old.com".url, selectedTimestamp: .init(timeIntervalSince1970: 0))
        let newTab = TabMock(isUrl: true, url: "http://new.com".url, selectedTimestamp: .init(timeIntervalSince1970: 1))

        oldTab.reloadClosure = tabReloadClosure
        newTab.reloadClosure = { [unowned self] tab in
            // mark currently selected tab as reloading, causing lazy loading to pause
            self.dataSource.isSelectedTabLoading = true
            self.dataSource.isSelectedTabLoadingSubject.send(true)
            tabReloadClosure(tab)
        }

        dataSource.loadedTabs = [.mockNotUrl, newTab, oldTab]
        dataSource.selectedTab = dataSource.loadedTabs.first

        let lazyLoader = try XCTUnwrap(TabLazyLoader(dataSource: dataSource))

        var isLazyLoadingPausedEvents: [Bool] = []
        lazyLoader.isLazyLoadingPausedPublisher.sink(receiveValue: { isLazyLoadingPausedEvents.append($0) }).store(in: &cancellables)

        await waitForLoadingDidFinishEvent(lazyLoader) {
            lazyLoader.scheduleLazyLoading()

            // The lazy loader's reaction to selection is deferred to the next
            // runloop turn, so spin until the first reload lands before asserting.
            let deadline = Date(timeIntervalSinceNow: 1)
            while reloadedTabsUrls.isEmpty && Date() < deadline {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            }
            XCTAssertEqual(reloadedTabsUrls, [newTab.url])

            // unpause lazy loading here
            dataSource.isSelectedTabLoading = false
            dataSource.isSelectedTabLoadingSubject.send(false)
        }

        XCTAssertEqual(reloadedTabsUrls, [newTab.url, oldTab.url])
        XCTAssertEqual(isLazyLoadingPausedEvents, [false, true, false])
    }

    func testWhenPinnedTabIsSelectedThenUnloadedTabMaterializationStartsFromFirstUnpinnedTab() async throws {
        let reloadExpectation = expectation(description: "TabMock.reload() called")
        reloadExpectation.expectedFulfillmentCount = 3

        // A non-URL tab is selected (pinned), so loading starts immediately.
        dataSource.selectedTab = .mockNotUrl
        dataSource.selectedTabIndex = .pinned(2)

        // No loaded tabs — only unloaded ones. This ensures findTabToLoad() returns nil
        // and the loader falls through to findNextUnloadedTabIndex() → materialize().
        dataSource.loadedTabs = []
        dataSource.loadedPinnedTabs = []
        dataSource.unloadedTabCount = 3
        dataSource.totalTabCount = 3

        // Track which tabs are still unloaded. Once materialized, a tab must no longer
        // report as unloaded — otherwise the loader keeps materializing the same index.
        var unloadedIndices: Set<Int> = [0, 1, 2]
        dataSource.isUnloadedHandler = { unloadedIndices.contains($0) }

        var materializedIndices = [Int]()
        dataSource.materializeHandler = { index in
            materializedIndices.append(index.item)
            unloadedIndices.remove(index.item)
            return TabMock(isUrl: true, reloadExpectation: reloadExpectation)
        }

        let lazyLoader = try XCTUnwrap(TabLazyLoader(dataSource: dataSource))

        await waitForLoadingDidFinishEvent(lazyLoader, and: [reloadExpectation]) {
            lazyLoader.scheduleLazyLoading()
        }

        // With a pinned tab selected, materialization should start from the first unpinned
        // tab (index 0) and expand outward, not from the pinned tab's positional index.
        XCTAssertEqual(materializedIndices, [0, 1, 2])
    }

    // The lazy loader's reaction to a selection-driven `isSelectedTabLoading = false`
    // must be asynchronous. If it fires synchronously, it can re-enter
    // `tabCollection.replaceTab → didReplaceTabAt → reloadItems` while a tab insert
    // is mid-flight on the collection view, raising NSInternalInconsistencyException
    // (APPLE-MACOS-BD7).
    @MainActor
    func testWillReloadNextTab_DoesNotMaterializeSynchronously() {
        var materializeCount = 0
        let selected = TabMock(isUrl: false)
        dataSource.selectedTab = selected
        dataSource.totalTabCount = 1
        dataSource.unloadedTabCount = 1
        dataSource.isUnloadedHandler = { _ in true }
        dataSource.materializeHandler = { _ in
            materializeCount += 1
            return TabMock()
        }

        let lazyLoader = TabLazyLoader(dataSource: dataSource)!
        lazyLoader.scheduleLazyLoading()

        dataSource.isSelectedTabLoadingSubject.send(false)
        XCTAssertEqual(materializeCount, 0, "materialize must not fire synchronously")
    }

    @MainActor
    func waitForLoadingDidFinishEvent<DataSource>(
        _ lazyLoader: TabLazyLoader<DataSource>,
        and otherExpectations: [XCTestExpectation] = [],
        expectedDidFinishValue expectedValue: Bool = true,
        file: StaticString = #file,
        line: UInt = #line,
        _ block: () -> Void
    ) async {

        let expectation = self.expectation(description: "loadingDidFinish")
        var result = false
        let cancellable = lazyLoader.lazyLoadingDidFinishPublisher.sink { didLoadAnyTabs in
            result = didLoadAnyTabs
            expectation.fulfill()
        }

        block()

        await fulfillment(of: otherExpectations + [expectation], timeout: 2)
        cancellable.cancel()
        XCTAssertEqual(result, expectedValue, file: file, line: line)
    }
}
