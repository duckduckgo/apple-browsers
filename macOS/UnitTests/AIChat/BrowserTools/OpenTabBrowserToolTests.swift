//
//  OpenTabBrowserToolTests.swift
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

import AIChat
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class OpenTabBrowserToolTests: XCTestCase {

    private var openedTabs: BrowserToolOpenedTabs!
    private var waiter: StubPageLoadWaiter!
    private var collection: TabCollectionViewModel!
    private var manager: WindowControllersManagerMock!
    private var tool: OpenTabBrowserTool!
    private var context: BrowserToolCallContext!

    override func setUp() {
        super.setUp()
        openedTabs = BrowserToolOpenedTabs()
        waiter = StubPageLoadWaiter()
        let ownerTab = Tab(content: .url(URL(string: "https://duck.ai/")!, credential: nil, source: .ui))
        collection = TabCollectionViewModel(tabCollection: TabCollection(tabs: [.loaded(ownerTab)]),
                                            pinnedTabsManagerProvider: nil,
                                            burnerMode: .regular)
        manager = WindowControllersManagerMock()
        manager.customAllTabCollectionViewModels = [collection]
        tool = OpenTabBrowserTool(windowControllersManager: manager, openedTabs: openedTabs, loadWaiter: waiter)
        context = BrowserToolCallContext(ownerTabID: ownerTab.uuid,
                                         ownerWindowToken: AIChatTabPickerSource.windowToken(forCollection: collection),
                                         isBurner: false,
                                         supportsElicitationForm: true)
    }

    override func tearDown() {
        openedTabs = nil
        waiter = nil
        collection = nil
        manager = nil
        tool = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Arguments

    func testWhenURLIsMissingOrNotAWebURLThenArgumentsAreInvalid() async {
        let invalid: [JSONValue?] = [
            nil,
            [:],
            ["url": 42],
            ["url": ""],
            ["url": "example.com"],
            ["url": "https://"],
            ["url": "ftp://example.com/file"],
            ["url": "javascript:alert(1)"],
            ["url": "file:///etc/hosts"],
            ["url": "about:blank"],
            ["url": "duck://settings"]
        ]

        for arguments in invalid {
            let result = await tool.execute(arguments: arguments, context: context)
            XCTAssertEqual(result, .failure(.invalidArguments), "\(String(describing: arguments))")
        }
        XCTAssertEqual(collection.allTabsCount, 1)
        XCTAssertTrue(waiter.waitedTabs.isEmpty)
    }

    func testWhenURLHasSurroundingWhitespaceAndAnUppercaseSchemeThenItIsAccepted() {
        let url = OpenTabBrowserTool.webURL(from: " HTTPS://shop.example/item \n")

        XCTAssertEqual(url?.host, "shop.example")
        XCTAssertEqual(url?.path, "/item")
        XCTAssertEqual(OpenTabBrowserTool.webURL(from: "http://shop.example")?.host, "shop.example")
    }

    // MARK: - Opening

    func testWhenPageLoadsThenItOpensInTheBackgroundAndIsRecordedAsDuckAIs() async throws {
        let selectedBefore = collection.selectedTabViewModel?.tab

        let result = await tool.execute(arguments: ["url": "https://shop.example/item"], context: context)

        let payload = try XCTUnwrap(result.successPayload)
        let tabID = try XCTUnwrap(payload["tabId"]?.stringValue)
        XCTAssertEqual(payload["url"], "https://shop.example/item")
        XCTAssertEqual(payload["title"], "")
        XCTAssertEqual(payload["status"], "loaded")
        XCTAssertEqual(collection.allTabsCount, 2)
        XCTAssertTrue(collection.selectedTabViewModel?.tab === selectedBefore)
        XCTAssertTrue(openedTabs.contains(tabID, ownerTabID: context.ownerTabID))
        XCTAssertEqual(waiter.waitedTabs.map(\.uuid), [tabID])
    }

    func testWhenLoadTimesOutThenTheTabStaysAndStatusSaysSo() async throws {
        waiter.outcome = .timeout

        let result = await tool.execute(arguments: ["url": "https://slow.example"], context: context)

        let payload = try XCTUnwrap(result.successPayload)
        XCTAssertEqual(payload["status"], "timeout")
        XCTAssertEqual(collection.allTabsCount, 2)
    }

    /// A failure carries no tabId, so a tab left behind could never be closed by Duck.ai.
    func testWhenPageIsBlockedThenTheTabIsClosedAndTheCallFails() async {
        waiter.outcome = .blocked

        let result = await tool.execute(arguments: ["url": "https://blocked.example"], context: context)

        XCTAssertEqual(result, .failure(.blocked))
        XCTAssertEqual(collection.allTabsCount, 1)
        XCTAssertTrue(openedTabs.tabIDs(ownerTabID: context.ownerTabID).isEmpty)
    }

    func testWhenTheTabIsClosedWhileLoadingThenTheCallIsUnavailable() async {
        waiter.onWait = { [openedTabs, manager] tab in
            openedTabs?.remove(tab.uuid)
            BrowserToolTargetTab.closeUnpinnedTab(withID: tab.uuid, in: manager!)
        }

        let result = await tool.execute(arguments: ["url": "https://shop.example"], context: context)

        XCTAssertEqual(result, .failure(.unavailable))
    }

    func testWhenTheCallIsCancelledWhileLoadingThenTheTabIsClosed() async throws {
        waiter.suspendsUntilCancelled = true

        let task = Task { await tool.execute(arguments: ["url": "https://shop.example"], context: context) }
        try await waitUntil { !self.waiter.waitedTabs.isEmpty }
        task.cancel()
        let result = await task.value

        XCTAssertEqual(result, .failure(.cancelled))
        XCTAssertEqual(collection.allTabsCount, 1)
        XCTAssertTrue(openedTabs.tabIDs(ownerTabID: context.ownerTabID).isEmpty)
    }

    /// The path `notifications/cancelled` takes: the invoker cancels the call's task by its id.
    func testWhenAPendingCallIsCancelledThroughTheInvokerThenItAnswersCancelledAndTheTabIsClosed() async throws {
        waiter.suspendsUntilCancelled = true
        let invoker = makeInvoker()

        let call = Task {
            await invoker.invoke(toolNamed: "openTab", arguments: ["url": "https://shop.example"], context: context,
                                 callID: "call-1", elicitationPusher: nil)
        }
        try await waitUntil { !self.waiter.waitedTabs.isEmpty }
        XCTAssertEqual(collection.allTabsCount, 2)

        XCTAssertTrue(invoker.cancelCall(callID: "call-1", ownerTabID: context.ownerTabID))
        let result = await call.value

        XCTAssertEqual(result, .failure(.cancelled))
        XCTAssertEqual(collection.allTabsCount, 1)
        XCTAssertTrue(openedTabs.tabIDs(ownerTabID: context.ownerTabID).isEmpty)
    }

    // MARK: - Cap

    func testWhenTheChatAlreadyHasFiveTabsThenTheOldestIsClosed() async throws {
        let first = try await open(times: OpenTabBrowserTool.maxOpenTabsPerChat).first

        _ = await tool.execute(arguments: ["url": "https://sixth.example"], context: context)

        let remaining = openedTabs.tabIDs(ownerTabID: context.ownerTabID)
        XCTAssertEqual(remaining.count, OpenTabBrowserTool.maxOpenTabsPerChat)
        XCTAssertFalse(remaining.contains(try XCTUnwrap(first)))
        XCTAssertEqual(collection.allTabsCount, 1 + OpenTabBrowserTool.maxOpenTabsPerChat)
    }

    func testWhenTheOldestTabIsTheSelectedOneThenTheNextOldestIsClosedInstead() async throws {
        let opened = try await open(times: OpenTabBrowserTool.maxOpenTabsPerChat)
        let index = try XCTUnwrap(collection.indexInAllTabs(where: { $0.uuid == opened[0] }))
        collection.select(at: index)

        _ = await tool.execute(arguments: ["url": "https://sixth.example"], context: context)

        let remaining = openedTabs.tabIDs(ownerTabID: context.ownerTabID)
        XCTAssertTrue(remaining.contains(opened[0]))
        XCTAssertFalse(remaining.contains(opened[1]))
    }

    func testWhenAnotherChatHasFiveTabsThenThisChatsTabIsNotCapped() async throws {
        for index in 0..<OpenTabBrowserTool.maxOpenTabsPerChat {
            openedTabs.add("other-\(index)", ownerTabID: "other-chat")
        }

        let result = await tool.execute(arguments: ["url": "https://shop.example"], context: context)

        XCTAssertNotNil(result.successPayload)
        XCTAssertEqual(openedTabs.tabIDs(ownerTabID: "other-chat").count, OpenTabBrowserTool.maxOpenTabsPerChat)
    }

    // MARK: - Scope

    func testWhenTheWindowIsAFireWindowThenTheCallIsUnavailable() async {
        let fireContext = BrowserToolCallContext(ownerTabID: context.ownerTabID,
                                                 ownerWindowToken: context.ownerWindowToken,
                                                 isBurner: true,
                                                 supportsElicitationForm: true)

        let result = await tool.execute(arguments: ["url": "https://shop.example"], context: fireContext)

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertEqual(collection.allTabsCount, 1)
    }

    func testWhenTheWindowCannotBeResolvedThenTheCallIsUnavailable() async {
        let lostContext = BrowserToolCallContext(ownerTabID: context.ownerTabID,
                                                 ownerWindowToken: "gone",
                                                 isBurner: false,
                                                 supportsElicitationForm: true)

        let result = await tool.execute(arguments: ["url": "https://shop.example"], context: lostContext)

        XCTAssertEqual(result, .failure(.unavailable))
    }

    func testWhenDescribedThenItIsAutoModeAndReachesTheOpenWeb() {
        XCTAssertEqual(tool.name, "openTab")
        XCTAssertEqual(tool.permissionMode, .auto)
        XCTAssertEqual(tool.annotations?.readOnlyHint, false)
        XCTAssertEqual(tool.annotations?.openWorldHint, true)
    }

    // MARK: -

    private func open(times: Int) async throws -> [String] {
        var tabIDs: [String] = []
        for index in 0..<times {
            let result = await tool.execute(arguments: ["url": .string("https://shop\(index).example")], context: context)
            tabIDs.append(try XCTUnwrap(result.successPayload?["tabId"]?.stringValue))
        }
        return tabIDs
    }

    private func makeInvoker() -> BrowserToolInvoker {
        let configuration = AllToolsEnabled()
        return BrowserToolInvoker(catalog: BrowserToolCatalog(tools: [tool], configuration: configuration),
                                  configuration: configuration,
                                  permissions: NoStoredDecisions(),
                                  elicitations: AIChatElicitationCoordinator(timeout: 5),
                                  openedTabs: openedTabs)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition())
    }
}

@MainActor
final class StubPageLoadWaiter: BrowserToolPageLoadWaiting {
    var outcome: BrowserToolPageLoadOutcome = .loaded
    var suspendsUntilCancelled = false
    var onWait: ((Tab) -> Void)?
    private(set) var waitedTabs: [Tab] = []

    func waitUntilSettled(_ tab: Tab) async throws -> BrowserToolPageLoadOutcome {
        waitedTabs.append(tab)
        if suspendsUntilCancelled {
            try await Task.sleep(nanoseconds: 60 * NSEC_PER_SEC)
        }
        onWait?(tab)
        return outcome
    }
}

private final class AllToolsEnabled: BrowserToolsConfiguration {
    let isEnabled = true
    func isToolEnabled(named name: String) -> Bool { true }
}

private final class NoStoredDecisions: BrowserToolPermissionStoring {
    let storedDecisions: [String: BrowserToolPermissionState] = [:]
    func state(forToolNamed name: String) -> BrowserToolPermissionState { .ask }
    func setState(_ state: BrowserToolPermissionState, forToolNamed name: String) {}
    func clearAll() {}
}

extension BrowserToolResult {
    var successPayload: JSONValue? {
        guard case .success(let payload) = self else { return nil }
        return payload
    }
}
