//
//  SwitchToTabBrowserToolTests.swift
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
final class SwitchToTabBrowserToolTests: XCTestCase {
    private func tab(_ id: String, fire: Bool = false) -> Tab {
        Tab(uid: id, link: Link(title: id, url: URL(string: "https://\(id).example")!), fireTab: fire)
    }

    private func context(_ scope: BrowserToolScope, burner: Bool = false) -> BrowserToolCallContext {
        BrowserToolCallContext(ownerTabID: scope.ownerTabID, ownerWindowToken: scope.token, isBurner: burner)
    }

    func testSuccessSelectsExactObjectAndClientResultContainsOnlyIdentifier() async throws {
        let owner = tab("owner")
        let target = tab("target")
        var selected: Tab?
        let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { [owner, target] })
        let scope = BrowserToolScope(owner: owner, source: source, selectedTabID: { owner.uid },
                                     selectTab: { selected = $0; return true })
        let tool = SwitchToTabBrowserTool(scopeProvider: { _ in scope })
        XCTAssertEqual(tool.permissionMode, .auto)
        let result = await tool.execute(arguments: ["tabId": "target"], context: context(scope))
        guard case .success(let value) = result else { return XCTFail("Expected successful selection") }
        XCTAssertTrue(selected === target)
        XCTAssertEqual(value["tabId"], .string("target"))
        XCTAssertEqual(tool.clientToolResult(from: value), .success(["tabId": "target"]))
        XCTAssertEqual(tool.clientToolResult(from: ["tabId": "target", "title": "secret", "url": "https://secret.example", "extra": true]),
                       .success(["tabId": "target"]))
    }

    func testInvalidArgumentsDoNotSelectTab() async {
        let owner = tab("owner")
        var selections = 0
        let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { [owner] })
        let scope = BrowserToolScope(owner: owner, source: source, selectedTabID: { owner.uid },
                                     selectTab: { _ in selections += 1; return true })
        let tool = SwitchToTabBrowserTool(scopeProvider: { _ in scope })
        let inputs: [JSONValue?] = [nil, .null, [:], ["tabId": .null], ["tabId": 1], ["tabId": true],
                                    ["tabId": ""], ["tabId": []], .string("owner")]
        for input in inputs {
            let result = await tool.execute(arguments: input, context: context(scope))
            XCTAssertEqual(result, .failure(.invalidArguments), "Input: \(String(describing: input))")
        }
        XCTAssertEqual(selections, 0)
    }

    func testMissingFireAndNonexactIdentifiersDoNotSelectTab() async {
        let owner = tab("owner")
        let target = tab("target")
        let fire = tab("fire", fire: true)
        var selections = 0
        let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { [owner, target, fire] })
        let scope = BrowserToolScope(owner: owner, source: source, selectedTabID: { owner.uid },
                                     selectTab: { _ in selections += 1; return true })
        let tool = SwitchToTabBrowserTool(scopeProvider: { _ in scope })
        for identifier in ["unknown", "fire", " target", "TARGET"] {
            let result = await tool.execute(arguments: ["tabId": .string(identifier)], context: context(scope))
            XCTAssertEqual(result, .failure(.notFound))
        }
        XCTAssertEqual(selections, 0)
    }

    func testDuckAIURLsAreNotSelectable() async {
        for address in ["https://duck.ai/", "https://duck.ai/chat", "https://duckduckgo.com/?q=hello&ia=chat"] {
            let owner = tab("owner")
            let target = Tab(uid: "chat", link: Link(title: "Chat", url: URL(string: address)!), fireTab: false)
            var selections = 0
            let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { [owner, target] })
            let scope = BrowserToolScope(owner: owner, source: source, selectedTabID: { owner.uid },
                                         selectTab: { _ in selections += 1; return true })
            let tool = SwitchToTabBrowserTool(scopeProvider: { _ in scope })

            let result = await tool.execute(arguments: ["tabId": "chat"], context: context(scope))

            XCTAssertEqual(result, .failure(.notFound))
            XCTAssertEqual(selections, 0)
        }
    }

    func testInvalidContextUnavailableProviderAndInvalidOwnerNeverSelect() async {
        let owner = tab("owner")
        let target = tab("target")
        var tabs = [owner, target]
        var selections = 0
        var available = true
        let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { tabs })
        let scope = BrowserToolScope(owner: owner, source: source, selectedTabID: { owner.uid },
                                     selectTab: { _ in selections += 1; return true })
        let tool = SwitchToTabBrowserTool(scopeProvider: { _ in available ? scope : nil })
        let contexts = [context(scope, burner: true),
                        BrowserToolCallContext(ownerTabID: "other", ownerWindowToken: scope.token, isBurner: false),
                        BrowserToolCallContext(ownerTabID: owner.uid, ownerWindowToken: "other", isBurner: false),
                        BrowserToolCallContext(ownerTabID: owner.uid, isBurner: false)]
        for invalid in contexts {
            let result = await tool.execute(arguments: ["tabId": "target"], context: invalid)
            XCTAssertEqual(result, .failure(.unavailable))
        }
        available = false
        let unavailable = await tool.execute(arguments: ["tabId": "target"], context: context(scope))
        XCTAssertEqual(unavailable, .failure(.unavailable))
        available = true
        for current in [[target], [tab("owner"), target]] {
            tabs = current
            let result = await tool.execute(arguments: ["tabId": "target"], context: context(scope))
            XCTAssertEqual(result, .failure(.unavailable))
        }
        tabs = [owner, target]
        scope.revoke()
        let revoked = await tool.execute(arguments: ["tabId": "target"], context: context(scope))
        XCTAssertEqual(revoked, .failure(.unavailable))
        XCTAssertEqual(selections, 0)
    }

    func testFireOwnerOrSourceNeverSelects() async {
        for ownerIsFire in [false, true] {
            for sourceIsFire in [false, true] where ownerIsFire || sourceIsFire {
                let owner = tab("owner", fire: ownerIsFire)
                let target = tab("target")
                var selections = 0
                let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: sourceIsFire ? .fire : .normal,
                                                      tabsProvider: { [owner, target] })
                let scope = BrowserToolScope(owner: owner, source: source, selectedTabID: { owner.uid },
                                             selectTab: { _ in selections += 1; return true })
                let tool = SwitchToTabBrowserTool(scopeProvider: { _ in scope })
                let result = await tool.execute(arguments: ["tabId": "target"], context: context(scope))
                XCTAssertEqual(result, .failure(.unavailable))
                XCTAssertEqual(selections, 0)
            }
        }
    }

    func testSelectionFailureReturnsUnavailable() async {
        let owner = tab("owner")
        let target = tab("target")
        var selections = 0
        let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { [owner, target] })
        let scope = BrowserToolScope(owner: owner, source: source, selectedTabID: { owner.uid },
                                     selectTab: { _ in selections += 1; return false })
        let tool = SwitchToTabBrowserTool(scopeProvider: { _ in scope })

        let result = await tool.execute(arguments: ["tabId": "target"], context: context(scope))

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertEqual(selections, 1)
    }

    func testConfirmedSelectionRemainsSuccessfulAfterSynchronousScopeChanges() async {
        for mutation in ["revoke", "removeTarget", "replaceTarget", "removeOwner", "replaceOwner"] {
            let owner = tab("owner")
            let target = tab("target")
            var tabs = [owner, target]
            var selections = 0
            var revoke: () -> Void = {}
            let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { tabs })
            let scope = BrowserToolScope(owner: owner, source: source, selectedTabID: { owner.uid }, selectTab: { selected in
                selections += 1
                XCTAssertTrue(selected === target)
                switch mutation {
                case "revoke": revoke()
                case "removeTarget": tabs = [owner]
                case "replaceTarget": tabs = [owner, self.tab("target")]
                case "removeOwner": tabs = [target]
                case "replaceOwner": tabs = [self.tab("owner"), target]
                default: XCTFail("Unexpected mutation")
                }
                return true
            })
            revoke = { [weak scope] in scope?.revoke() }
            let tool = SwitchToTabBrowserTool(scopeProvider: { _ in scope })
            let result = await tool.execute(arguments: ["tabId": "target"], context: context(scope))
            guard case .success(let value) = result else { return XCTFail("Expected successful selection for mutation: \(mutation)") }
            XCTAssertEqual(value["tabId"], .string("target"))
            XCTAssertEqual(selections, 1)
        }
    }
}
