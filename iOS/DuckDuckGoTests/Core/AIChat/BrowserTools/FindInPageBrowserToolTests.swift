//
//  FindInPageBrowserToolTests.swift
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
final class FindInPageBrowserToolTests: XCTestCase {
    private var reader: FindInPageStubReader!

    override func setUp() {
        super.setUp()
        reader = FindInPageStubReader()
    }

    override func tearDown() {
        reader = nil
        super.tearDown()
    }

    func testMatchesAndNoMatchesReturnCompleteContract() async {
        let (tool, context, _) = make(content: "Games and games", truncated: true)
        let found = await tool.execute(arguments: ["query": "GAMES", "maxMatches": 1], context: context)
        guard case .success(let raw) = found else { return XCTFail("Expected matches: \(found)") }
        XCTAssertEqual(tool.clientToolResult(from: raw), .success([
            "tabId": "owner", "title": "Page", "url": "https://a.example/page", "query": "GAMES",
            "matchCount": 2, "matches": [["snippet": "Games and games", "matchIndex": 0]],
            "truncated": true, "contentTruncated": true, "matchIndexesReliable": false
        ]))

        let absent = await tool.execute(arguments: ["query": "missing"], context: context)
        guard case .success(let noMatches) = absent else { return XCTFail("Expected empty success: \(absent)") }
        XCTAssertEqual(tool.clientToolResult(from: noMatches), .success([
            "tabId": "owner", "title": "Page", "url": "https://a.example/page", "query": "missing",
            "matchCount": 0, "matches": [], "truncated": false, "contentTruncated": true, "matchIndexesReliable": false
        ]))
    }

    func testCaseSensitivityAndNonOverlappingCount() async {
        let (tool, context, _) = make(content: "aaa AAA aaa")
        for (sensitive, count): (Bool, Int) in [(false, 3), (true, 2)] {
            let result = await tool.execute(arguments: ["query": "aa", "caseSensitive": .bool(sensitive), "maxMatches": 1], context: context)
            guard case .success(let value) = result else { XCTFail("Expected matches: \(result)"); continue }
            XCTAssertEqual(value["matchCount"], .int(count))
            XCTAssertEqual(value["matches"], [["snippet": "aaa AAA aaa", "matchIndex": 0]])
            XCTAssertEqual(value["truncated"], true)
        }
    }

    func testDefaultAndMaximumSnippetCountsDoNotLimitTotal() async {
        let (tool, context, _) = make(content: String(repeating: "a ", count: 51))
        for (arguments, expectedCount): (JSONValue, Int) in [(["query": "a"], 10), (["query": "a", "maxMatches": 50], 50)] {
            let result = await tool.execute(arguments: arguments, context: context)
            guard case .success(let value) = result else { XCTFail("Expected matches: \(result)"); continue }
            XCTAssertEqual(value["matchCount"], 51)
            XCTAssertEqual(value["matches"]?.arrayValue?.count, expectedCount)
            XCTAssertEqual(value["matches"]?.arrayValue?.last?["matchIndex"], .int(expectedCount - 1))
            XCTAssertEqual(value["truncated"], true)
        }
    }

    func testSearchIncludesTextBeyondReadTabContentResponseLimit() async {
        let content = String(repeating: "e\u{301}", count: 1501) + " needle"
        let (tool, context, _) = make(content: content)
        let result = await tool.execute(arguments: ["query": "needle"], context: context)
        guard case .success(let value) = result else { return XCTFail("Expected match: \(result)") }
        XCTAssertEqual(value["matchCount"], 1)
        XCTAssertEqual(value["matches"]?.arrayValue?.first?["matchIndex"], 0)
        XCTAssertTrue(value["matches"]?.arrayValue?.first?["snippet"]?.stringValue?.hasSuffix("needle") == true)
        XCTAssertEqual(value["contentTruncated"], false)
        XCTAssertEqual(value["truncated"], false)
    }

    func testMalformedArgumentsAreRejectedBeforeReading() async {
        let (tool, context, _) = make()
        let inputs: [JSONValue?] = [nil, .null, "text", [:], ["query": 1], ["query": " \n\t"],
                                    ["query": "a", "caseSensitive": "yes"], ["query": "a", "caseSensitive": .null],
                                    ["query": "a", "maxMatches": 0], ["query": "a", "maxMatches": 51],
                                    ["query": "a", "maxMatches": 1.5], ["query": "a", "maxMatches": true],
                                    ["query": "a", "maxMatches": "1"], ["query": "a", "tabId": 7]]
        for arguments in inputs {
            let result = await tool.execute(arguments: arguments, context: context)
            XCTAssertEqual(result, .failure(.invalidArguments), "\(String(describing: arguments))")
        }
        XCTAssertNil(reader.requestedTabID)
    }

    func testUnicodeQueryLimitUsesScalarsAndPreservesOriginalQuery() async {
        let query = String(repeating: "e\u{301}", count: 499) + " a"
        let (tool, context, _) = make(content: query)
        let accepted = await tool.execute(arguments: ["query": .string(query)], context: context)
        guard case .success(let value) = accepted else { return XCTFail("Expected query at limit: \(accepted)") }
        XCTAssertEqual(value["query"], .string(query))
        XCTAssertEqual(value["matchCount"], 1)
        let rejected = await tool.execute(arguments: ["query": .string(query + "a")], context: context)
        XCTAssertEqual(rejected, .failure(.invalidArguments))
    }

    func testUnicodeSnippetsBoundContextAndLongMatchesByScalars() throws {
        let padding = String(repeating: "👩🏽‍💻e\u{301}", count: 20)
        let found = FindInPageBrowserTool.search(content: padding + " needle " + padding, query: "needle", caseSensitive: true, maxMatches: 1)
        XCTAssertEqual(found.matchCount, 1)
        XCTAssertEqual(found.matches.first?.snippet.unicodeScalars.count, 86)
        XCTAssertTrue(found.matches.first?.snippet.contains(" needle ") == true)

        let longQuery = String(repeating: "👩🏽‍💻", count: 30)
        let long = FindInPageBrowserTool.search(content: longQuery + " " + longQuery, query: longQuery, caseSensitive: true, maxMatches: 1)
        XCTAssertEqual(long.matchCount, 2)
        XCTAssertEqual(long.matches.first?.snippet, String(repeating: "👩🏽‍💻", count: 25))
        XCTAssertEqual(long.matches.first?.snippet.unicodeScalars.count, 100)

        let query = String(repeating: "needle", count: 12)
        let extended = FindInPageBrowserTool.search(content: padding + query + padding, query: query, caseSensitive: true, maxMatches: 1)
        let snippet = try XCTUnwrap(extended.matches.first?.snippet)
        XCTAssertTrue(snippet.contains(query))
        XCTAssertEqual(snippet.unicodeScalars.count, 100)
        XCTAssertEqual(FindInPageBrowserTool.search(content: "a  b\tneedle\n", query: "needle", caseSensitive: false, maxMatches: 1).matches.first?.snippet, "a b needle")
    }

    func testClientResultRedactsURLBeforeClippingAndClipsUnicodeMetadata() async {
        let (tool, context, _) = make()
        let long = String(repeating: "👩🏽‍💻e\u{301}", count: 700)
        let url = "https://user:" + long + "@example.com/" + String(repeating: "x", count: 1300) + "?secret=value#private"
        reader.pageContext = AIChatPageContextData(title: long, favicon: [], url: url, content: "needle", truncated: false, fullContentLength: 6)
        let result = await tool.execute(arguments: ["query": "needle"], context: context)
        guard case .success(let raw) = result,
              case .success(let value) = tool.clientToolResult(from: raw) else { return XCTFail("Expected mapped result") }
        XCTAssertEqual(raw["url"], .string(url))
        XCTAssertEqual(value["url"], .string("https://example.com/" + String(repeating: "x", count: 1260)))
        XCTAssertEqual(value["title"]?.stringValue?.unicodeScalars.count, 256)
        XCTAssertEqual(value["matches"], [["snippet": "needle", "matchIndex": 0]])
    }

    func testDefaultTargetIsOwnerEvenWhenAnotherTabIsSelected() async {
        let (tool, context, _) = make()
        for arguments: JSONValue in [["query": "a"], ["query": "a", "tabId": .null], ["query": "a", "tabId": " "]] {
            let result = await tool.execute(arguments: arguments, context: context)
            guard case .success(let value) = result else { XCTFail("Expected owner result: \(result)"); continue }
            XCTAssertEqual(value["tabId"], "owner")
            XCTAssertEqual(reader.requestedTabID, "owner")
        }
    }

    func testExplicitTargetUsesOwnerScopeAndForeignTargetIsNotFound() async {
        let (tool, context, _) = make()
        let explicit = await tool.execute(arguments: ["query": "a", "tabId": "other"], context: context)
        guard case .success(let value) = explicit else { return XCTFail("Expected explicit target: \(explicit)") }
        XCTAssertEqual(value["tabId"], "other")
        XCTAssertEqual(reader.requestedTabID, "other")
        let foreign = await tool.execute(arguments: ["query": "a", "tabId": "elsewhere"], context: context)
        XCTAssertEqual(foreign, .failure(.notFound))
    }

    func testUnreadableOwnerDoesNotFallBackToSelectedReadableTab() async {
        let (tool, context, _) = make(ownerURL: "https://duck.ai/chat")
        let result = await tool.execute(arguments: ["query": "a"], context: context)
        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertNil(reader.requestedTabID)
    }

    func testUnavailableReaderAndDocumentPropagateUnavailable() async {
        let (tool, context, _) = make()
        reader.pageContext = nil
        let missing = await tool.execute(arguments: ["query": "a"], context: context)
        XCTAssertEqual(missing, .failure(.unavailable))
        reader.pageContext = .document(title: "Document", url: "https://a.example/doc.pdf", mimeType: AIChatPageContextData.pdfMIMEType, data: "JVBERi0=")
        let document = await tool.execute(arguments: ["query": "PDF"], context: context)
        XCTAssertEqual(document, .failure(.unavailable))
    }

    func testFireAndScopeRevocationCannotReturnContent() async {
        let (tool, context, scope) = make()
        let fire = BrowserToolCallContext(ownerTabID: context.ownerTabID, ownerWindowToken: context.ownerWindowToken, isBurner: true)
        let refused = await tool.execute(arguments: ["query": "a"], context: fire)
        XCTAssertEqual(refused, .failure(.unavailable))
        XCTAssertNil(reader.requestedTabID)
        reader.beforeReturn = { scope.revoke() }
        let revoked = await tool.execute(arguments: ["query": "a"], context: context)
        XCTAssertEqual(revoked, .failure(.unavailable))
    }

    private func make(content: String = "a", truncated: Bool = false, ownerURL: String = "https://a.example/page") -> (FindInPageBrowserTool, BrowserToolCallContext, BrowserToolScope) {
        let owner = Tab(uid: "owner", link: Link(title: "Owner", url: URL(string: ownerURL)!), fireTab: false)
        let other = Tab(uid: "other", link: Link(title: "Other", url: URL(string: "https://b.example")!), fireTab: false)
        let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { [owner, other] })
        let scope = BrowserToolScope(owner: owner, source: source, selectedTabID: { other.uid })
        reader.pageContext = AIChatPageContextData(title: "Page", favicon: [], url: "https://a.example/page", content: content,
                                                   truncated: truncated, fullContentLength: content.unicodeScalars.count)
        let context = BrowserToolCallContext(ownerTabID: owner.uid, ownerWindowToken: scope.token, isBurner: false)
        return (FindInPageBrowserTool(scopeProvider: { _ in scope }, reader: reader), context, scope)
    }
}

@MainActor
private final class FindInPageStubReader: BrowserToolPageContentReading {
    var pageContext: AIChatPageContextData?
    var beforeReturn: (() -> Void)?
    private(set) var requestedTabID: String?

    func pageContext(for tab: Tab, in scope: BrowserToolScope) async -> AIChatPageContextData? {
        requestedTabID = tab.uid
        beforeReturn?()
        return pageContext
    }
}
