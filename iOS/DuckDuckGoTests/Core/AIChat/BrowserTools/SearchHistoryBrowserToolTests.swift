//
//  SearchHistoryBrowserToolTests.swift
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
@testable import Core
import FeatureFlags_iOS
@testable import History
import XCTest
@testable import DuckDuckGo

@MainActor
final class SearchHistoryBrowserToolTests: XCTestCase {

    private var history: BrowserToolHistoryManager!
    private var tool: SearchHistoryBrowserTool!
    private var scope: BrowserToolScope!
    private var retainedEntries: [HistoryEntry] = []

    override func setUp() {
        super.setUp()
        history = BrowserToolHistoryManager(historyCoordinator: NullHistoryCoordinator(), isEnabledByUser: true, historyFeatureEnabled: true)
        let owner = Tab(uid: "owner", link: Link(title: "Owner", url: URL(string: "https://a.example")!), fireTab: false)
        let scope = BrowserToolScope(owner: owner, source: MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal,
                                                                                  tabsProvider: { [owner] }), selectedTabID: { owner.uid })
        self.scope = scope
        tool = SearchHistoryBrowserTool(historyManager: history, scopeProvider: { _ in scope })
    }

    override func tearDown() {
        tool = nil
        history = nil
        retainedEntries = []
        super.tearDown()
    }

    func testTitleAndURLMatchCaseInsensitivelyNewestFirst() async throws {
        _ = visit("https://apple.com/mac", title: "Mac", at: 100)
        _ = visit("https://example.com/", title: "Buy apples", at: 300)
        _ = visit("https://other.org/", title: "Nothing", at: 200)
        history.entries = retainedEntries

        let results = try await rows(["query": "APPLE"])

        XCTAssertEqual(results.map { $0["url"] }, ["https://example.com/", "https://apple.com/mac"])
        XCTAssertEqual(results.first?["visitedAt"], "1970-01-01T00:05:00.000Z")
    }

    func testAbsentNullAndBlankQueriesReturnMultipleVisitsNewestFirst() async throws {
        _ = visit("https://a.example/", title: "A", at: 100)
        let entry = retainedEntries[0]
        entry.visits.insert(Visit(date: Date(timeIntervalSince1970: 200), historyEntry: entry))
        history.entries = retainedEntries
        for arguments: JSONValue? in [nil, .null, [:], ["query": .null], ["query": " "]] {
            let results = try await rows(arguments)
            XCTAssertEqual(results.map { $0["visitedAt"] }, ["1970-01-01T00:03:20.000Z", "1970-01-01T00:01:40.000Z"])
        }
    }

    func testInclusiveDateOnlyAndISODateBounds() async throws {
        for seconds: TimeInterval in [-1, 0, 0.5, 86_399.999, 86_400] {
            _ = visit("https://a.example/", title: "A", at: seconds)
        }
        history.entries = retainedEntries

        let day = try await rows(["startDate": "1970-01-01", "endDate": "1970-01-01"])
        XCTAssertEqual(day.map { $0["visitedAt"] }, ["1970-01-01T23:59:59.999Z", "1970-01-01T00:00:00.500Z", "1970-01-01T00:00:00.000Z"])
        let instants = try await rows(["startDate": "1970-01-01T00:00:00Z", "endDate": "1970-01-01T00:00:00.500Z"])
        XCTAssertEqual(instants.map { $0["visitedAt"] }, ["1970-01-01T00:00:00.500Z", "1970-01-01T00:00:00.000Z"])
    }

    func testMalformedArgumentsAreRejected() async {
        let inputs: [JSONValue] = [
            "x", ["query": 1], ["query": true], ["limit": 0], ["limit": 51], ["limit": "10"],
            ["limit": .double(1.5)], ["limit": .null], ["startDate": "soon"], ["endDate": false],
            ["startDate": "2026-02-30"], ["endDate": "2026-13-01"], ["startDate": "2026-2-03"],
            ["startDate": "2026-09-24", "endDate": "2026-09-23"]
        ]
        for input in inputs {
            let result = await tool.execute(arguments: input, context: context())
            XCTAssertEqual(result, .failure(.invalidArguments), "Input: \(input)")
        }
    }

    func testQueryLengthCountsUnicodeScalars() async throws {
        let accepted = try await rows(["query": .string(String(repeating: "e\u{301}", count: 500))])
        XCTAssertTrue(accepted.isEmpty)
        let rejected = await tool.execute(arguments: ["query": .string(String(repeating: "e\u{301}", count: 501))], context: context())
        XCTAssertEqual(rejected, .failure(.invalidArguments))
    }

    func testDisabledHistoryDoesNotReadRetainedEntries() async throws {
        _ = visit("https://a.example/", title: "A", at: 100)
        history.entries = retainedEntries
        history.isEnabledByUser = false

        let results = try await rows(nil)

        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(history.reads, 0)
    }

    func testDefaultAndMaximumResultLimits() async throws {
        for index in 1...55 {
            _ = visit("https://a.example/", title: "Visit \(index)", at: TimeInterval(index))
        }
        history.entries = retainedEntries

        let defaults = try await rows(nil)
        let maximum = try await rows(["limit": 50])

        XCTAssertEqual(defaults.count, 10)
        XCTAssertEqual(defaults.first?["title"], "Visit 55")
        XCTAssertEqual(defaults.last?["title"], "Visit 46")
        XCTAssertEqual(maximum.count, 50)
        XCTAssertEqual(maximum.last?["title"], "Visit 6")
    }

    func testClientProjectionClipsUnicodeAndRedactsBeforeClipping() throws {
        let long = String(repeating: "e\u{301}", count: 1000)
        let credentials = String(repeating: "private", count: 300)
        let result = tool.clientToolResult(from: ["results": [
            ["title": .string(long), "url": .string("https://" + long), "visitedAt": "now"],
            ["title": "Doc", "url": .string("https://\(credentials):password@visible.example/doc?token=private#secret"), "visitedAt": "then"]
        ]])
        guard case .success(let payload) = result else { return XCTFail("Expected client result") }
        let results = try XCTUnwrap(payload["results"]?.arrayValue)
        XCTAssertEqual(results[0]["title"]?.stringValue, String(repeating: "e\u{301}", count: 128))
        XCTAssertEqual(results[0]["url"]?.stringValue?.unicodeScalars.count, 1280)
        XCTAssertEqual(results[0]["visitedAt"], "now")
        XCTAssertEqual(results[1]["url"], "https://visible.example/doc")
    }

    func testSearchOnlyMatchesVisibleMetadataIncludingFallbackTitle() async throws {
        let title = String(repeating: "a", count: BrowserToolOutputLimits.title) + "hiddenTitle"
        let path = String(repeating: "b", count: BrowserToolOutputLimits.url) + "hiddenPath"
        _ = visit("https://privateUser:privatePassword@visible.example/\(path)?querySecret#fragmentSecret", title: title, at: 1)
        _ = visit("https://fallback.example/docs", title: " ", at: 2)
        history.entries = retainedEntries

        for term in ["privateUser", "privatePassword", "querySecret", "fragmentSecret", "hiddenTitle", "hiddenPath"] {
            let results = try await rows(["query": .string(term)])
            XCTAssertTrue(results.isEmpty, "Hidden term matched: \(term)")
        }
        let visible = try await rows(["query": "VISIBLE.EXAMPLE"])
        XCTAssertEqual(visible.count, 1)
        let fallback = try await rows(["query": "FALLBACK.EXAMPLE/DOCS"])
        XCTAssertEqual(fallback.first?["title"], "fallback.example/docs")
    }

    func testFireAndRevokedScopesCannotReadHistory() async {
        let fire = await tool.execute(arguments: nil, context: context(isBurner: true))
        scope.revoke()
        let revoked = await tool.execute(arguments: nil, context: context())
        XCTAssertEqual(fire, .failure(.unavailable))
        XCTAssertEqual(revoked, .failure(.unavailable))
        XCTAssertEqual(history.reads, 0)
    }

    func testNativePermissionPersistsAllowAndDeniesWithoutReadingHistory() async {
        _ = visit("https://private:password@a.example/doc?token=secret#secret", title: "A", at: 100)
        history.entries = retainedEntries
        let fixture = BrowserToolsBridgeFixture(enabledFlags: [.aiChatBrowserTools, .aiChatBrowserToolSearchHistory],
                                               capabilities: [.searchHistory], historyManager: history)
        defer { fixture.cleanUp() }
        fixture.presenter.autoAnswer = .always
        fixture.presenter.onPresent = { XCTAssertEqual(self.history.reads, 0) }
        let params: [String: Any] = ["callId": "call", "capability": ["name": "searchHistory", "version": 1], "input": [:]]
        let expected = ExecuteClientToolResponse.success(callId: "call", value: ["results": [
            ["title": "A", "url": "https://a.example/doc", "visitedAt": "1970-01-01T00:01:40.000Z"]
        ]])

        let first = await fixture.handler.executeClientTool(params: params, source: fixture.script)
        let stored = await fixture.handler.executeClientTool(params: params, source: fixture.script)
        XCTAssertEqual(first, expected)
        XCTAssertEqual(stored, expected)
        XCTAssertEqual(fixture.presenter.prompts.map(\.toolName), ["searchHistory"])
        XCTAssertEqual(fixture.service.permissions.state(forToolNamed: "searchHistory"), .allow)
        fixture.presenter.onPresent = nil
        fixture.service.permissions.setState(.ask, forToolNamed: "searchHistory")
        fixture.presenter.autoAnswer = .never
        let reads = history.reads
        let denied = await fixture.handler.executeClientTool(params: params, source: fixture.script)
        XCTAssertEqual(denied, .failure(callId: "call", error: .denied))
        XCTAssertEqual(fixture.service.permissions.state(forToolNamed: "searchHistory"), .deny)
        XCTAssertEqual(history.reads, reads)
        XCTAssertTrue(fixture.webView.permissionPrompts.isEmpty)
    }

    func testMainAndToolFlagsDynamicallyGateDiscoveryAndInvocationBeforePrompt() async {
        let fixture = BrowserToolsBridgeFixture(enabledFlags: [], capabilities: nil, historyManager: history)
        defer { fixture.cleanUp() }
        let service = fixture.service
        let states: [[FeatureFlag]] = [[], [.aiChatBrowserTools], [.aiChatBrowserToolSearchHistory],
                                      [.aiChatBrowserTools, .aiChatBrowserToolSearchHistory], [.aiChatBrowserTools],
                                      [.aiChatBrowserTools, .aiChatBrowserToolSearchHistory]]
        let params: [String: Any] = ["callId": "call", "capability": ["name": "searchHistory", "version": 1], "input": [:]]
        for state in states {
            fixture.flags.enabledFeatureFlags = state
            let enabled = state.contains(.aiChatBrowserTools) && state.contains(.aiChatBrowserToolSearchHistory)
            XCTAssertEqual(service.configuration(for: fixture.script)?.capabilities, enabled ? [.searchHistory] : nil)
            XCTAssertEqual(service.catalog.tool(named: "searchHistory") != nil, enabled)
            let prompts = fixture.presenter.prompts.count
            let reads = history.reads
            let result = await fixture.handler.executeClientTool(params: params, source: fixture.script)
            XCTAssertEqual(result, enabled ? .success(callId: "call", value: ["results": []]) : .failure(callId: "call", error: .unavailable))
            XCTAssertEqual(fixture.presenter.prompts.count, prompts + (enabled ? 1 : 0))
            XCTAssertEqual(history.reads, reads + (enabled ? 1 : 0))
        }
    }

    private func rows(_ arguments: JSONValue?) async throws -> [JSONValue] {
        let result = await tool.execute(arguments: arguments, context: context())
        guard case .success(let raw) = result, case .success(let value) = tool.clientToolResult(from: raw) else {
            XCTFail("Expected history results, got \(result)")
            return []
        }
        return try XCTUnwrap(value["results"]?.arrayValue)
    }

    private func visit(_ url: String, title: String, at seconds: TimeInterval) -> Visit {
        let date = Date(timeIntervalSince1970: seconds)
        let entry = HistoryEntry(url: URL(string: url)!)
        entry.title = title
        entry.lastVisit = date
        let visit = Visit(date: date, historyEntry: entry)
        entry.visits = [visit]
        retainedEntries.append(entry)
        return visit
    }

    private func context(isBurner: Bool = false) -> BrowserToolCallContext {
        BrowserToolCallContext(ownerTabID: "owner", ownerWindowToken: scope.token, isBurner: isBurner)
    }
}

private final class BrowserToolHistoryManager: MockHistoryManager {
    var entries: BrowsingHistory = []
    private(set) var reads = 0
    override var history: BrowsingHistory? {
        reads += 1
        return entries
    }
}
