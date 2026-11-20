//
//  CPMWindowMatchingTests.swift
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

import XCTest
@testable import WebExtensions

/// Matches a message of the extension to its tab by the tab's index and window, with the window found from the order
/// in which WebKit got the windows, through windows and tabs that are opened, closed, reordered and moved.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMWindowMatchingTests: XCTestCase {

    private var date = Date(timeIntervalSince1970: 1_000_000)
    private let pixels = WindowMatchingPixels()
    private let browser = FakeBrowser(extensionIdentifier: "cpm")
    private lazy var monitor = CPMMessagingHealthMonitor(pixelFiring: pixels,
                                                         isUnmeasuredPage: { _ in false },
                                                         silenceWindow: 30,
                                                         messageTolerance: 2,
                                                         now: { [unowned self] in self.date })

    override func setUp() async throws {
        try await super.setUp()
        monitor.tabIdentifierAtExtensionPosition = browser.tabIdentifier(extensionIdentifier:index:windowRank:windowCount:)
    }

    // MARK: - Same page in several windows

    func testSamePageAtTheSameIndexInTwoWindowsIsToldByWindow() {
        let first = browser.openWindow(tabs: ["a"])
        let second = browser.openWindow(tabs: ["b"])
        commit("a")
        commit("b")

        answer("b", in: second)
        XCTAssertEqual(monitor.waitingTabIdentifiers, ["a"])

        answer("a", in: first)
        XCTAssertEqual(monitor.waitingTabIdentifiers, [])
    }

    func testOnlyTheTabThatAnsweredLeavesTheSilentReport() {
        _ = browser.openWindow(tabs: ["a"])
        let second = browser.openWindow(tabs: ["b"])
        commit("a")
        commit("b")

        answer("b", in: second)
        date.addTimeInterval(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.stages, [.noMark], "the twin in the first window heard nothing")
    }

    func testALateMessageOfAnAnsweredTabDoesNotAnswerItsTwin() {
        let first = browser.openWindow(tabs: ["a"])
        _ = browser.openWindow(tabs: ["b"])
        commit("a")
        commit("b")
        answer("a", in: first)

        answer("a", in: first)

        XCTAssertEqual(monitor.waitingTabIdentifiers, ["b"])
    }

    func testAMarkReachesOnlyTheTabItIsAbout() {
        let first = browser.openWindow(tabs: ["a"])
        let second = browser.openWindow(tabs: ["b"])
        commit("a")
        commit("b")

        mark(.siteChecked, tab: "b", in: second)
        mark(.configRead, tab: "a", in: first)
        date.addTimeInterval(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(Set(pixels.stages), [.reached(.siteChecked), .reached(.configRead)])
    }

    func testTheWindowTellsTwinsOfAnyRank() {
        let windows = (1...4).map { browser.openWindow(tabs: ["t\($0)"]) }
        windows.indices.forEach { commit("t\($0 + 1)") }

        for (offset, window) in windows.enumerated().reversed() {
            answer("t\(offset + 1)", in: window)
            let expected = Set((0..<offset).map { "t\($0 + 1)" })
            XCTAssertEqual(monitor.waitingTabIdentifiers, expected)
        }
    }

    // MARK: - Windows

    func testNewWindowOpenedLaterGetsTheNextRank() {
        let first = browser.openWindow(tabs: ["a"])
        commit("a")
        answer("a", in: first)

        let second = browser.openWindow(tabs: ["b"])
        let third = browser.openWindow(tabs: ["c"])
        commit("b")
        commit("c")
        answer("c", in: third)

        XCTAssertEqual(monitor.waitingTabIdentifiers, ["b"])
        _ = second
    }

    func testClosingAWindowKeepsTheRankOfTheOthers() {
        let first = browser.openWindow(tabs: ["a"])
        let second = browser.openWindow(tabs: ["b"])
        let third = browser.openWindow(tabs: ["c"])
        ["a", "b", "c"].forEach { commit($0) }

        browser.close(first)
        answer("c", in: third)
        XCTAssertEqual(monitor.waitingTabIdentifiers, ["a", "b"])

        answer("b", in: second)
        XCTAssertEqual(monitor.waitingTabIdentifiers, ["a"])
    }

    func testClosingTheLastWindowAndOpeningANewOne() {
        let first = browser.openWindow(tabs: ["a"])
        commit("a")
        answer("a", in: first)
        browser.close(first)

        let second = browser.openWindow(tabs: ["b"])
        let third = browser.openWindow(tabs: ["c"])
        commit("b")
        commit("c")
        answer("c", in: third)

        XCTAssertEqual(monitor.waitingTabIdentifiers, ["b"])
        _ = second
    }

    func testWindowsAlreadyOpenWhenTheExtensionLoadsAreNumberedFocusedFirst() {
        let first = browser.addWindow(tabs: ["a"])
        let second = browser.addWindow(tabs: ["b"])
        let third = browser.addWindow(tabs: ["c"])
        ["a", "b", "c"].forEach { commit($0) }

        browser.loadExtension(focused: third)
        answer("a", in: first)
        XCTAssertEqual(monitor.waitingTabIdentifiers, ["b", "c"])

        answer("c", in: third)
        XCTAssertEqual(monitor.waitingTabIdentifiers, ["b"])
        _ = second
    }

    func testTheAppListingTheWindowsInAnotherOrderDoesNotChangeTheMatch() {
        let first = browser.openWindow(tabs: ["a"])
        let second = browser.openWindow(tabs: ["b"])
        commit("a")
        commit("b")

        browser.bringToFront(second)
        answer("a", in: first)

        XCTAssertEqual(monitor.waitingTabIdentifiers, ["b"])
    }

    // MARK: - Tabs

    func testReorderingTabsInAWindowFollowsTheNewIndex() {
        _ = browser.openWindow(tabs: ["a", "b"])
        let second = browser.openWindow(tabs: ["c", "d"])
        ["a", "b", "c", "d"].forEach { commit($0) }

        browser.move("d", to: second, at: 0)
        answer("d", in: second)
        XCTAssertEqual(monitor.waitingTabIdentifiers, ["a", "b", "c"])

        answer("c", in: second)
        XCTAssertEqual(monitor.waitingTabIdentifiers, ["a", "b"])
    }

    func testDraggingATabToAnotherWindow() {
        let first = browser.openWindow(tabs: ["a", "b"])
        let second = browser.openWindow(tabs: ["c"])
        ["a", "b", "c"].forEach { commit($0) }

        browser.move("b", to: second, at: 0)
        answer("b", in: second)
        answer("a", in: first)

        XCTAssertEqual(monitor.waitingTabIdentifiers, ["c"])
    }

    func testDraggingATabToANewWindow() {
        let first = browser.openWindow(tabs: ["a", "b"])
        commit("a")
        commit("b")

        let second = browser.openWindow(tabs: [])
        browser.move("b", to: second, at: 0)
        answer("b", in: second)

        XCTAssertEqual(monitor.waitingTabIdentifiers, ["a"])
        _ = first
    }

    func testClosingATabShiftsTheIndexesAfterIt() {
        let window = browser.openWindow(tabs: ["a", "b", "c"])
        ["a", "b", "c"].forEach { commit($0) }

        browser.closeTab("a", in: window)
        answer("c", in: window)

        XCTAssertEqual(monitor.waitingTabIdentifiers, ["a", "b"])
    }

    func testPinnedTabsAreSharedAndShiftTheIndexesOfEveryWindow() {
        browser.pinned = ["p"]
        let first = browser.openWindow(tabs: ["a"])
        let second = browser.openWindow(tabs: ["b"])
        ["p", "a", "b"].forEach { commit($0) }

        answer("p", in: second)
        XCTAssertEqual(monitor.waitingTabIdentifiers, ["a", "b"])

        answer("b", in: second)
        XCTAssertEqual(monitor.waitingTabIdentifiers, ["a"])
        _ = first
    }

    func testPinningATabMovesItInFrontOfTheOthers() {
        let first = browser.openWindow(tabs: ["a", "b"])
        _ = browser.openWindow(tabs: ["c"])
        ["a", "b", "c"].forEach { commit($0) }

        browser.pin("b")
        answer("b", in: first)
        XCTAssertEqual(monitor.waitingTabIdentifiers, ["a", "c"])

        answer("a", in: first)
        XCTAssertEqual(monitor.waitingTabIdentifiers, ["c"])
    }

    // MARK: - When the tab cannot be told

    func testAnotherNumberOfWindowsInTheExtensionFallsBackToThePage() {
        let first = browser.openWindow(tabs: ["a"])
        _ = browser.openWindow(tabs: ["b"])
        commit("a")
        commit("b")

        browser.hiddenWindowIds = [9_999]
        answer("a", in: first)

        XCTAssertEqual(monitor.waitingTabIdentifiers, [], "every waiting tab of the page is answered")
    }

    func testAMessageWithoutAPositionFallsBackToThePage() {
        let first = browser.openWindow(tabs: ["a"])
        _ = browser.openWindow(tabs: ["b"])
        commit("a")
        commit("b")

        answer("a", in: first, withPosition: false)

        XCTAssertEqual(monitor.waitingTabIdentifiers, [])
    }

    func testAMessageForAnIndexThatHoldsNoTabFallsBackToThePage() {
        let window = browser.openWindow(tabs: ["a"])
        commit("a")

        answer("a", in: window, index: 7)

        XCTAssertEqual(monitor.waitingTabIdentifiers, [])
    }

    func testAMessageAboutAnotherPageOfTheTabFallsBackToThePage() {
        let first = browser.openWindow(tabs: ["a"])
        _ = browser.openWindow(tabs: ["b"])
        commit("a", path: "new")
        commit("b", path: "old")

        answer("a", in: first, page: "old")

        XCTAssertEqual(monitor.waitingTabIdentifiers, ["a"], "the position says tab a, whose page is another one: the page decides")
    }

    // MARK: - Helpers

    private func url(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }

    private func commit(_ tab: String, path: String = "same") {
        monitor.handle(.navigationCommitted(tabIdentifier: tab, url: url(path), navigationKind: .other, extensionIsLoaded: true))
    }

    /// The message the extension sends for `tab`, with the index, window and windows the browser reports now.
    private func position(of tab: String, in window: FakeBrowser.Window, index: Int?) -> CPMExtensionTabPosition {
        let position = browser.position(of: tab, in: window)
        return CPMExtensionTabPosition(tabIndex: index ?? position.index, windowId: position.windowId, windowIds: position.windowIds)
    }

    private func answer(_ tab: String, in window: FakeBrowser.Window, page: String = "same", index: Int? = nil,
                        withPosition: Bool = true) {
        let position = withPosition ? position(of: tab, in: window, index: index) : nil
        monitor.handle(.dashboardResponse(url: url(page), extensionIdentifier: browser.extensionIdentifier, position: position))
    }

    private func mark(_ stage: CPMInitStage, tab: String, in window: FakeBrowser.Window) {
        let position = position(of: tab, in: window, index: nil)
        monitor.handle(.initProgress(url: url("same"), stage: stage, extensionIdentifier: browser.extensionIdentifier, position: position))
    }
}

/// Windows and tabs as the app and WebKit see them. The app hands a window to WebKit when it opens it, or all
/// of them in the order of `openWindows` (the focused one first) when the extension loads; WebKit numbers a window
/// from one growing counter when it first gets it, and the extension reports the ascending ids of its windows.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class FakeBrowser {

    final class Window {
        var tabs: [String]
        init(tabs: [String]) { self.tabs = tabs }
    }

    struct Position {
        let index: Int
        let windowId: Int
        let windowIds: [Int]
    }

    let extensionIdentifier: String
    let order = WebExtensionWindowOrder()
    var pinned: [String] = []
    var hiddenWindowIds: [Int] = []
    private(set) var windows: [Window] = []
    private var webKitIds: [ObjectIdentifier: Int] = [:]
    private var counter = 100

    init(extensionIdentifier: String) {
        self.extensionIdentifier = extensionIdentifier
    }

    func openWindow(tabs: [String]) -> Window {
        let window = addWindow(tabs: tabs)
        handOver(window)
        return window
    }

    /// A window opened before the extension loaded, not yet handed to WebKit.
    func addWindow(tabs: [String]) -> Window {
        let window = Window(tabs: tabs)
        windows.append(window)
        return window
    }

    func loadExtension(focused: Window) {
        let ordered = [focused] + windows.filter { $0 !== focused }
        ordered.forEach { handOver($0) }
    }

    func close(_ window: Window) {
        windows.removeAll { $0 === window }
    }

    func bringToFront(_ window: Window) {
        windows.removeAll { $0 === window }
        windows.insert(window, at: 0)
    }

    func move(_ tab: String, to window: Window, at index: Int) {
        windows.forEach { $0.tabs.removeAll { $0 == tab } }
        window.tabs.insert(tab, at: min(index, window.tabs.count))
    }

    func closeTab(_ tab: String, in window: Window) {
        window.tabs.removeAll { $0 == tab }
    }

    func pin(_ tab: String) {
        windows.forEach { $0.tabs.removeAll { $0 == tab } }
        pinned.append(tab)
    }

    func position(of tab: String, in window: Window) -> Position {
        let index = (pinned + window.tabs).firstIndex(of: tab) ?? 0
        let ids = windows.compactMap { webKitIds[ObjectIdentifier($0)] } + hiddenWindowIds
        return Position(index: index, windowId: webKitIds[ObjectIdentifier(window)] ?? 0, windowIds: ids.sorted())
    }

    /// What the platform answers the monitor: the tab at the index of the window with that rank of the open windows.
    func tabIdentifier(extensionIdentifier: String, index: Int, windowRank: Int, windowCount: Int) -> String? {
        let ordered = order.windows(in: extensionIdentifier).compactMap { $0 as? Window }
        let open = ordered.filter { window in windows.contains { $0 === window } }
        guard open.count == windowCount, open.indices.contains(windowRank) else { return nil }
        let tabs = pinned + open[windowRank].tabs
        return tabs.indices.contains(index) ? tabs[index] : nil
    }

    private func handOver(_ window: Window) {
        order.register(window, in: extensionIdentifier)
        guard webKitIds[ObjectIdentifier(window)] == nil else { return }
        counter += 7
        webKitIds[ObjectIdentifier(window)] = counter
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class WindowMatchingPixels: WebExtensionPixelFiring {
    private(set) var stages: [CPMLastStage] = []

    func fire(_ event: WebExtensionPixelEvent) {
        guard case .cpmMessagingBreakage(let lastStage, _) = event else { return }
        stages.append(lastStage)
    }
}
