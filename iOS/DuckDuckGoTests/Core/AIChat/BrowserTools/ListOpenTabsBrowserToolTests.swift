//
//  ListOpenTabsBrowserToolTests.swift
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

import AIChat
import Core
import XCTest
@testable import DuckDuckGo

@MainActor
final class ListOpenTabsBrowserToolTests: XCTestCase {
    private func tab(_ id: String, _ url: String, fire: Bool = false) -> Tab {
        Tab(uid: id, link: Link(title: id, url: URL(string: url)!), fireTab: fire)
    }

    private func context(_ scope: BrowserToolScope, burner: Bool = false) -> BrowserToolCallContext {
        BrowserToolCallContext(ownerTabID: scope.ownerTabID, ownerWindowToken: scope.token,
                              isBurner: burner)
    }

    private func pages(_ result: BrowserToolResult) throws -> [JSONValue] {
        guard case .success(let value) = result else { XCTFail("Expected successful listing"); return [] }
        return try XCTUnwrap(value["tabs"]?.arrayValue)
    }

    func testFreshModelOrderSelectionAndFilteringWithoutPageAccess() async throws {
        let owner = tab("owner", "https://owner.example")
        let selected = tab("selected", "https://selected.example")
        let chat = tab("chat", "https://duck.ai/chat")
        let custom = tab("custom", "https://dev.example/chat?x=1")
        let ordinary = tab("ordinary", "about:blank")
        var tabs = [ordinary, owner, tab("fire", "https://fire.example", fire: true), Tab(fireTab: false), chat, custom, selected]
        var selectedID: String? = selected.uid
        var pageReads = 0
        var acquisitions = 0
        let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { tabs },
                                              pageProvider: { _ in pageReads += 1; return nil },
                                              acquirePage: { _ in acquisitions += 1; return nil })
        let scope = BrowserToolScope(owner: owner, source: source, selectedTabID: { selectedID })
        let tool = ListOpenTabsBrowserTool(scopeProvider: { _ in scope })
        let first = try pages(await tool.execute(arguments: [:], context: context(scope)))
        XCTAssertEqual(first.compactMap { $0["tabId"]?.stringValue }, ["ordinary", "owner", "custom", "selected"])
        XCTAssertEqual(first.map { $0["isCurrentTab"] }, [.bool(false), .bool(false), .bool(false), .bool(true)])
        XCTAssertEqual(first.first?["isAttachable"], .bool(false))
        XCTAssertEqual(first.last?["isAttachable"], .bool(true))
        XCTAssertEqual(first.last?["title"], .string("selected"))
        XCTAssertEqual(first.last?["url"], .string("https://selected.example"))

        selectedID = chat.uid
        tabs = [selected, chat, owner]
        let second = try pages(await tool.execute(arguments: ["limit": 1], context: context(scope)))
        XCTAssertEqual(second.compactMap { $0["tabId"]?.stringValue }, ["selected"])
        XCTAssertEqual(second.first?["isCurrentTab"], .bool(false))
        XCTAssertEqual(pageReads, 0)
        XCTAssertEqual(acquisitions, 0)
    }

    func testDuckAIURLsAreExcludedAndOtherPagesRemainListed() async throws {
        let owner = tab("owner", "https://owner.example")
        let tabs = [owner, tab("custom", "https://dev.example/chat"),
                    tab("homepage", "https://duckduckgo.com/"),
                    tab("chat", "https://duck.ai/chat"),
                    tab("production", "https://duckduckgo.com/?q=hello&ia=chat")]
        let scope = BrowserToolScope(owner: owner,
                                     source: MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { tabs }),
                                     selectedTabID: { nil })
        let tool = ListOpenTabsBrowserTool(scopeProvider: { _ in scope })
        let result = try pages(await tool.execute(arguments: [:], context: context(scope)))
        XCTAssertEqual(result.compactMap { $0["tabId"]?.stringValue }, ["owner", "custom", "homepage"])
        XCTAssertEqual(result.map { $0["isAttachable"] }, [.bool(true), .bool(true), .bool(false)])
    }

    func testLimitsRejectInvalidValuesAndDefaultToFifty() async throws {
        let owner = tab("owner", "https://owner.example")
        let tabs = [owner] + (1...55).map { tab("tab-\($0)", "https://example.com/\($0)") }
        let scope = BrowserToolScope(owner: owner,
                                     source: MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { tabs }),
                                     selectedTabID: { nil })
        let tool = ListOpenTabsBrowserTool(scopeProvider: { _ in scope })
        let invalid: [JSONValue] = [["limit": 0], ["limit": -1], ["limit": 51], ["limit": .double(1.5)],
                                    ["limit": .double(1)], ["limit": "1"], ["limit": true], ["limit": .null]]
        for arguments in invalid {
            let result = await tool.execute(arguments: arguments, context: context(scope))
            XCTAssertEqual(result, .failure(.invalidArguments), "Input: \(String(describing: arguments))")
        }
        let validInputs: [JSONValue?] = [nil, [:], ["limit": 50]]
        for input in validInputs {
            let result = try pages(await tool.execute(arguments: input, context: context(scope)))
            XCTAssertEqual(result.count, 50)
            XCTAssertEqual(result.last?["tabId"], .string("tab-49"))
        }
        let one = try pages(await tool.execute(arguments: ["limit": 1], context: context(scope)))
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one.first?["tabId"], .string("owner"))
    }

    func testScopeProviderAndScopeAreRecheckedOnEveryExecution() async {
        let owner = tab("owner", "https://owner.example")
        var tabs = [owner]
        let scope = BrowserToolScope(owner: owner,
                                     source: MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { tabs }),
                                     selectedTabID: { nil })
        var available = true
        let tool = ListOpenTabsBrowserTool(scopeProvider: { _ in available ? scope : nil })
        let initial = await tool.execute(arguments: [:], context: context(scope))
        guard case .success = initial else { return XCTFail("Expected available owner") }
        available = false
        let blocked = await tool.execute(arguments: [:], context: context(scope))
        XCTAssertEqual(blocked, .failure(.unavailable))
        available = true
        let fire = await tool.execute(arguments: [:], context: context(scope, burner: true))
        XCTAssertEqual(fire, .failure(.unavailable))
        tabs = [Tab(uid: owner.uid, fireTab: false)]
        let replaced = await tool.execute(arguments: [:], context: context(scope))
        XCTAssertEqual(replaced, .failure(.unavailable))
        tabs = [owner]
        scope.revoke()
        let revoked = await tool.execute(arguments: [:], context: context(scope))
        XCTAssertEqual(revoked, .failure(.unavailable))
    }

    func testClientResultClipsUnicodeScalarsAndPreservesAdditionalTabFields() throws {
        let tool = ListOpenTabsBrowserTool(scopeProvider: { _ in nil })
        let title = String(repeating: "😀", count: 255) + "e\u{301}tail"
        let url = String(repeating: "😀", count: 1279) + "e\u{301}tail"
        let value: JSONValue = ["tabs": [["tabId": "id", "title": .string(title), "url": .string(url),
                                          "isCurrentTab": true, "isAttachable": false, "extra": "secret"]], "extra": true]
        let result = tool.clientToolResult(from: value)
        let page = try XCTUnwrap(pages(result).first)
        XCTAssertEqual(page["title"]?.stringValue, String(repeating: "😀", count: 255) + "e")
        XCTAssertEqual(page["url"]?.stringValue, String(repeating: "😀", count: 1279) + "e")
        let expected: JSONValue = ["tabs": [["tabId": "id", "title": .string(String(repeating: "😀", count: 255) + "e"),
                                             "url": .string(String(repeating: "😀", count: 1279) + "e"),
                                             "isCurrentTab": true, "isAttachable": false, "extra": "secret"]]]
        XCTAssertEqual(result, .success(expected))
        XCTAssertEqual(tool.clientToolResult(from: [:]), .failure(.unavailable))
        XCTAssertEqual(tool.clientToolResult(from: ["tabs": [[:]]]), .success(["tabs": [[:]]]))
    }
}
