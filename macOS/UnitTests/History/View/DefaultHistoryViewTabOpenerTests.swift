//
//  DefaultHistoryViewTabOpenerTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import DuckDuckGo_Privacy_Browser

final class CapturingURLOpener: URLOpening {

    func open(_ url: URL, source: DuckDuckGo_Privacy_Browser.Tab.TabContent.URLSource, target window: NSWindow?, event: NSEvent?) {
        openCalls.append(url)
    }

    func openInNewTab(_ urls: [URL], sourceWindow: NSWindow?) {
        openInNewTabCalls.append(urls)
    }

    func openInNewWindow(_ urls: [URL], sourceWindow: NSWindow?) {
        openInNewWindowCalls.append(urls)
    }

    func openInNewFireWindow(_ urls: [URL], sourceWindow: NSWindow?) {
        openInNewFireWindowCalls.append(urls)
    }

    var openCalls: [URL] = []
    var openInNewTabCalls: [[URL]] = []
    var openInNewWindowCalls: [[URL]] = []
    var openInNewFireWindowCalls: [[URL]] = []
}

final class DefaultHistoryViewTabOpenerTests: XCTestCase {
    var tabOpener: DefaultHistoryViewTabOpener!
    var urlOpener: CapturingURLOpener!
    var dialogPresenter: CapturingHistoryViewDeleteDialogPresenter!

    override func setUp() async throws {
        urlOpener = CapturingURLOpener()
        dialogPresenter = CapturingHistoryViewDeleteDialogPresenter()
        tabOpener = DefaultHistoryViewTabOpener(urlOpener: { self.urlOpener })
        tabOpener.dialogPresenter = dialogPresenter
    }

    override func tearDown() {
        dialogPresenter = nil
        tabOpener = nil
        urlOpener = nil
    }

    // MARK: - open

    @MainActor
    func testThatOpenCallsURLOpener() async throws {
        let url = try XCTUnwrap("https://example.com".url)
        tabOpener.open(url)
        XCTAssertEqual(urlOpener.openCalls, [url])
    }

    // MARK: - openInNewTab

    @MainActor
    func testThatOpenInNewTabCallsURLOpener() async throws {
        let url = try XCTUnwrap("https://example.com".url)
        await tabOpener.openInNewTab([url])
        XCTAssertEqual(urlOpener.openInNewTabCalls, [[url]])
        XCTAssertEqual(dialogPresenter.showMultipleTabsDialogCalls.count, 0)
    }

    @MainActor
    func testWhenOpenInNewTabIsCalledWithTooManyURLsThenConfirmationDialogIsShown() async throws {
        let urls = try (1...50).map { try XCTUnwrap("https://example\($0).com".url) }
        await tabOpener.openInNewTab(urls)
        XCTAssertEqual(dialogPresenter.showMultipleTabsDialogCalls, [50])
    }

    @MainActor
    func testWhenOpenInNewTabIsCalledWithTooManyURLsAndDialogIsRejectedThenURLOpenerIsNotCalled() async throws {
        dialogPresenter.multipleTabsDialogResponse = .cancel
        let urls = try (1...50).map { try XCTUnwrap("https://example\($0).com".url) }
        await tabOpener.openInNewTab(urls)
        XCTAssertEqual(dialogPresenter.showMultipleTabsDialogCalls, [50])
        XCTAssertEqual(urlOpener.openInNewTabCalls.count, 0)
    }

    @MainActor
    func testWhenOpenInNewTabIsCalledWithTooManyURLsAndDialogIsAcceptedThenURLOpenerIsCalled() async throws {
        dialogPresenter.multipleTabsDialogResponse = .open
        let urls = try (1...50).map { try XCTUnwrap("https://example\($0).com".url) }
        await tabOpener.openInNewTab(urls)
        XCTAssertEqual(dialogPresenter.showMultipleTabsDialogCalls, [50])
        XCTAssertEqual(urlOpener.openInNewTabCalls, [urls])
    }

    // MARK: - openInNewWindow

    @MainActor
    func testThatOpenInNewWindowCallsURLOpener() async throws {
        let url = try XCTUnwrap("https://example.com".url)
        await tabOpener.openInNewWindow([url])
        XCTAssertEqual(urlOpener.openInNewWindowCalls, [[url]])
        XCTAssertEqual(dialogPresenter.showMultipleTabsDialogCalls.count, 0)
    }

    @MainActor
    func testWhenOpenInNewWindowIsCalledWithTooManyURLsThenConfirmationDialogIsShown() async throws {
        let urls = try (1...50).map { try XCTUnwrap("https://example\($0).com".url) }
        await tabOpener.openInNewWindow(urls)
        XCTAssertEqual(dialogPresenter.showMultipleTabsDialogCalls, [50])
    }

    @MainActor
    func testWhenOpenInNewWindowIsCalledWithTooManyURLsAndDialogIsRejectedThenURLOpenerIsNotCalled() async throws {
        dialogPresenter.multipleTabsDialogResponse = .cancel
        let urls = try (1...50).map { try XCTUnwrap("https://example\($0).com".url) }
        await tabOpener.openInNewWindow(urls)
        XCTAssertEqual(dialogPresenter.showMultipleTabsDialogCalls, [50])
        XCTAssertEqual(urlOpener.openInNewWindowCalls.count, 0)
    }

    @MainActor
    func testWhenOpenInNewWindowIsCalledWithTooManyURLsAndDialogIsAcceptedThenURLOpenerIsCalled() async throws {
        dialogPresenter.multipleTabsDialogResponse = .open
        let urls = try (1...50).map { try XCTUnwrap("https://example\($0).com".url) }
        await tabOpener.openInNewWindow(urls)
        XCTAssertEqual(dialogPresenter.showMultipleTabsDialogCalls, [50])
        XCTAssertEqual(urlOpener.openInNewWindowCalls, [urls])
    }

    // MARK: - openInNewFireWindow

    @MainActor
    func testThatOpenInNewFireWindowCallsURLOpener() async throws {
        let url = try XCTUnwrap("https://example.com".url)
        await tabOpener.openInNewFireWindow([url])
        XCTAssertEqual(urlOpener.openInNewFireWindowCalls, [[url]])
        XCTAssertEqual(dialogPresenter.showMultipleTabsDialogCalls.count, 0)
    }

    @MainActor
    func testWhenOpenInNewFireWindowIsCalledWithTooManyURLsThenConfirmationDialogIsShown() async throws {
        let urls = try (1...50).map { try XCTUnwrap("https://example\($0).com".url) }
        await tabOpener.openInNewFireWindow(urls)
        XCTAssertEqual(dialogPresenter.showMultipleTabsDialogCalls, [50])
    }

    @MainActor
    func testWhenOpenInNewFireWindowIsCalledWithTooManyURLsAndDialogIsRejectedThenURLOpenerIsNotCalled() async throws {
        dialogPresenter.multipleTabsDialogResponse = .cancel
        let urls = try (1...50).map { try XCTUnwrap("https://example\($0).com".url) }
        await tabOpener.openInNewFireWindow(urls)
        XCTAssertEqual(dialogPresenter.showMultipleTabsDialogCalls, [50])
        XCTAssertEqual(urlOpener.openInNewFireWindowCalls.count, 0)
    }

    @MainActor
    func testWhenOpenInNewFireWindowIsCalledWithTooManyURLsAndDialogIsAcceptedThenURLOpenerIsCalled() async throws {
        dialogPresenter.multipleTabsDialogResponse = .open
        let urls = try (1...50).map { try XCTUnwrap("https://example\($0).com".url) }
        await tabOpener.openInNewFireWindow(urls)
        XCTAssertEqual(dialogPresenter.showMultipleTabsDialogCalls, [50])
        XCTAssertEqual(urlOpener.openInNewFireWindowCalls, [urls])
    }
}

private extension DefaultHistoryViewTabOpener {
    @MainActor func open(_ url: URL) {
        open(url, window: nil)
    }
    @MainActor func openInNewTab(_ urls: [URL]) async {
        await openInNewTab(urls, sourceWindow: nil)
    }
    @MainActor func openInNewWindow(_ urls: [URL]) async {
        await openInNewWindow(urls, sourceWindow: nil)
    }
    @MainActor func openInNewFireWindow(_ urls: [URL]) async {
        await openInNewFireWindow(urls, sourceWindow: nil)
    }
}
