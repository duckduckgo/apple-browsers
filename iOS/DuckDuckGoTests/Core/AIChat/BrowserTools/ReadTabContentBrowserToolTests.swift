//
//  ReadTabContentBrowserToolTests.swift
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
final class ReadTabContentBrowserToolTests: XCTestCase {

    private var reader: StubPageContentReader!

    override func setUp() {
        super.setUp()
        reader = StubPageContentReader()
    }

    override func tearDown() {
        reader = nil
        super.tearDown()
    }

    func testWhenTabIdIsOmittedThenTheOwnerTabIsRead() async throws {
        let (tool, context, _) = make()
        reader.pageContext = AIChatPageContextData(title: "Owner", favicon: [], url: "https://a.example", content: "body", truncated: false, fullContentLength: 4)

        let result = await tool.execute(arguments: nil, context: context)

        guard case .success(let payload) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(reader.requestedTabID, context.ownerTabID)
        XCTAssertEqual(payload["tabId"], .string(context.ownerTabID))
        XCTAssertEqual(payload["title"], "Owner")
        XCTAssertEqual(payload["content"], "body")
        XCTAssertEqual(payload["truncated"], false)
        XCTAssertEqual(payload["fullContentLength"], 4)
    }

    func testWhenContentExceedsTheClientToolLimitThenOnlyTheClientResultIsCut() async throws {
        let (tool, context, _) = make()
        let content = String(repeating: "a", count: BrowserToolOutputLimits.content + 10)
        reader.pageContext = AIChatPageContextData(title: "t", favicon: [AIChatPageContextData.PageContextFavicon(href: "https://a.example/f.ico", rel: "icon")],
                                                   url: "https://a.example", content: content, truncated: false,
                                                   fullContentLength: content.count, attachable: false)

        let result = await tool.execute(arguments: nil, context: context)
        guard case .success(let pagePayload) = result else { return XCTFail("expected success, got \(result)") }
        let clientResult = tool.clientToolResult(from: pagePayload)

        XCTAssertEqual(pagePayload["content"]?.stringValue, content)
        XCTAssertNotNil(pagePayload["favicon"])
        guard case .success(let payload) = clientResult else { return XCTFail("expected success, got \(clientResult)") }
        XCTAssertEqual(payload.objectValue?.keys.sorted(),
                       ["attachable", "attached", "content", "fullContentLength", "tabId", "title", "truncated", "url"])
        XCTAssertEqual(payload["content"]?.stringValue?.count, BrowserToolOutputLimits.content)
        XCTAssertEqual(payload["truncated"], true)
        XCTAssertEqual(payload["fullContentLength"], .int(content.count))
        XCTAssertEqual(payload["attachable"], false)
        XCTAssertEqual(payload["attached"], false)
    }

    func testWhenURLContainsSensitiveComponentsThenOnlyTheClientURLIsRedacted() async {
        let (tool, context, _) = make()
        let cases: [(original: String, expected: String)] = [
            ("https://user:password@example.com/path?token=secret#private", "https://example.com/path"),
            ("https://user:password@example.com/path", "https://example.com/path"),
            ("https://user@example.com", "https://example.com"),
            ("https://example.com/path?token=secret", "https://example.com/path"),
            ("https://example.com/path#private", "https://example.com/path"),
            ("https://us%40er:pa%3Ass@example.com/path", "https://example.com/path"),
            ("https://first@last:password@example.com/path", "https://example.com/path"),
            ("https://user:password@example.com/path@name", "https://example.com/path@name"),
            ("https://example.com/path@name", "https://example.com/path@name"),
            ("https://user:password@[2001:db8::1]:8443/a%2Fb%3Fc%23d%40e", "https://[2001:db8::1]:8443/a%2Fb%3Fc%23d%40e"),
            ("https://example.com/path?token=secret#fragment", "https://example.com/path"),
            ("https://example.com/path#fragment?token=secret", "https://example.com/path"),
            ("https://example.com/path", "https://example.com/path"),
            ("", "")
        ]

        for testCase in cases {
            reader.pageContext = AIChatPageContextData(title: "Title", favicon: [], url: testCase.original, content: "body",
                                                       truncated: false, fullContentLength: 4, attachable: false)
            guard case .success(let raw) = await tool.execute(arguments: nil, context: context),
                  case .success(let result) = tool.clientToolResult(from: raw) else { return XCTFail("Expected content") }

            XCTAssertEqual(raw["url"]?.stringValue, testCase.original)
            XCTAssertEqual(result["url"]?.stringValue, testCase.expected, testCase.original)
            XCTAssertEqual(result["title"], raw["title"])
            XCTAssertEqual(result["content"], raw["content"])
            XCTAssertEqual(result["truncated"], false)
            XCTAssertEqual(result["fullContentLength"], 4)
            XCTAssertEqual(result["tabId"], .string(context.ownerTabID))
            XCTAssertEqual(result["attachable"], false)
            XCTAssertEqual(result["attached"], false)
        }
    }

    func testWhenUserInfoExceedsURLLimitThenItIsRemovedBeforeClipping() async {
        let (tool, context, _) = make()
        let username = String(repeating: "u", count: BrowserToolOutputLimits.url + 100)
        let original = "https://\(username):password@example.com/safe/path?token=secret#private"
        reader.pageContext = AIChatPageContextData(title: "Title", favicon: [], url: original, content: "body",
                                                   truncated: false, fullContentLength: 4)

        guard case .success(let raw) = await tool.execute(arguments: nil, context: context),
              case .success(let result) = tool.clientToolResult(from: raw) else { return XCTFail("Expected content") }

        XCTAssertEqual(raw["url"]?.stringValue, original)
        XCTAssertEqual(result["url"], "https://example.com/safe/path")
        XCTAssertEqual(result["content"], "body")
        XCTAssertEqual(result["truncated"], false)
        XCTAssertEqual(result["attached"], false)
    }

    func testWhenRedactedURLExceedsLimitThenUnicodePathIsClippedByScalar() async {
        let (tool, context, _) = make()
        let safeURL = "https://example.com/" + String(repeating: "👩🏽‍💻e\u{301}", count: 300)
        let original = safeURL.replacingOccurrences(of: "://", with: "://user:password@") + "?token=secret#private"
        let expected = "https://example.com/" + String(repeating: "👩🏽‍💻e\u{301}", count: 210)
        reader.pageContext = AIChatPageContextData(title: "Title", favicon: [], url: original, content: "body",
                                                   truncated: false, fullContentLength: 4)

        guard case .success(let raw) = await tool.execute(arguments: nil, context: context),
              case .success(let result) = tool.clientToolResult(from: raw) else { return XCTFail("Expected content") }

        XCTAssertEqual(raw["url"]?.stringValue, original)
        XCTAssertEqual(result["url"]?.stringValue, expected)
        XCTAssertEqual(result["url"]?.stringValue?.unicodeScalars.count, BrowserToolOutputLimits.url)
        XCTAssertEqual(result["content"], "body")
        XCTAssertEqual(result["truncated"], false)
        XCTAssertEqual(result["attached"], false)
    }

    func testWhenThePageIsADocumentThenTheClientResultIsUnavailable() async throws {
        let (tool, context, _) = make()
        reader.pageContext = .document(title: "t", url: "https://a.example/doc.pdf", mimeType: AIChatPageContextData.pdfMIMEType, data: "JVBERi0=")

        let result = await tool.execute(arguments: nil, context: context)
        guard case .success(let pagePayload) = result else { return XCTFail("expected success, got \(result)") }

        XCTAssertEqual(tool.clientToolResult(from: pagePayload), .failure(.unavailable))
    }

    func testWhenTabIdNamesAnotherTabInTheWindowThenThatTabIsRead() async {
        let (tool, context, other) = make()

        _ = await tool.execute(arguments: ["tabId": .string(other.uid)], context: context)

        XCTAssertEqual(reader.requestedTabID, other.uid)
    }

    func testWhenTabIdIsNotInTheOwnerWindowThenCallIsNotFound() async {
        let (tool, context, _) = make()

        let result = await tool.execute(arguments: ["tabId": "elsewhere"], context: context)

        XCTAssertEqual(result, .failure(.notFound))
        XCTAssertNil(reader.requestedTabID)
    }

    func testWhenArgumentsAreMalformedThenTheyAreInvalid() async {
        let (tool, context, _) = make()

        let notObject = await tool.execute(arguments: "x", context: context)
        let badTabID = await tool.execute(arguments: ["tabId": 5], context: context)

        XCTAssertEqual(notObject, .failure(.invalidArguments))
        XCTAssertEqual(badTabID, .failure(.invalidArguments))
    }

    func testWhenNoPageContextCanBeReadThenCallIsUnavailable() async {
        let (tool, context, _) = make()
        reader.pageContext = nil

        let result = await tool.execute(arguments: [:], context: context)

        XCTAssertEqual(result, .failure(.unavailable))
    }

    func testWhenCalledInAFireWindowThenCallIsUnavailable() async {
        let (tool, ownerContext, _) = make()
        let context = BrowserToolCallContext(ownerTabID: ownerContext.ownerTabID,
                                             ownerWindowToken: ownerContext.ownerWindowToken,
                                             isBurner: true)

        let result = await tool.execute(arguments: nil, context: context)

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertNil(reader.requestedTabID)
    }

    func testWhenDescribedThenItAsksForPermission() {
        let (tool, _, _) = make()

        XCTAssertEqual(tool.name, "readTabContent")
        XCTAssertEqual(tool.permissionMode, .ask)
    }


    func testScalarLimitsAndOriginalLengthPreserveUnicodeContract() async throws {
        let (tool, context, _) = make()
        let content = String(repeating: "👩🏽‍💻e\u{301}", count: 700)
        reader.pageContext = AIChatPageContextData(title: content, favicon: [], url: content, content: content,
                                                   truncated: false, fullContentLength: 1)
        guard case .success(let raw) = await tool.execute(arguments: nil, context: context),
              case .success(let result) = tool.clientToolResult(from: raw) else { return XCTFail("Expected content") }
        XCTAssertEqual(result["content"]?.stringValue?.unicodeScalars.count, 3000)
        XCTAssertEqual(result["title"]?.stringValue?.unicodeScalars.count, 256)
        XCTAssertEqual(result["url"]?.stringValue?.unicodeScalars.count, 1280)
        XCTAssertEqual(result["fullContentLength"], .int(content.unicodeScalars.count))
        XCTAssertEqual(result["truncated"], true)
        XCTAssertEqual(result["attached"], false)
    }

    func testNullBlankAndAbsentTargetAlwaysReadOwner() async {
        let (tool, context, _) = make()
        for arguments: JSONValue? in [nil, .null, [:], ["tabId": .null], ["tabId": " "]] {
            _ = await tool.execute(arguments: arguments, context: context)
            XCTAssertEqual(reader.requestedTabID, context.ownerTabID)
        }
    }

    func testInjectedReaderCannotReturnAfterScopeRevocationOrTargetReplacement() async {
        for replaceTarget in [false, true] {
            let owner = Tab(uid: "owner", link: Link(title: "Owner", url: URL(string: "https://a.example")!), fireTab: false)
            var tabs = [owner]
            let scope = BrowserToolScope(owner: owner, source: MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal,
                                                                                      tabsProvider: { tabs }), selectedTabID: { owner.uid })
            let context = BrowserToolCallContext(ownerTabID: owner.uid, ownerWindowToken: scope.token, isBurner: false)
            let reader = StubPageContentReader()
            reader.pageContext = AIChatPageContextData(title: "Owner", favicon: [], url: "https://a.example", content: "body", truncated: false, fullContentLength: 4)
            reader.beforeReturn = {
                if replaceTarget { tabs = [Tab(uid: owner.uid, link: owner.link, fireTab: false)] } else { scope.revoke() }
            }
            let tool = ReadTabContentBrowserTool(scopeProvider: { _ in scope }, reader: reader)
            let result = await tool.execute(arguments: [:], context: context)
            XCTAssertEqual(result, .failure(.unavailable))
            XCTAssertEqual(reader.requestedTabID, owner.uid)
        }
    }

    private func make() -> (ReadTabContentBrowserTool, BrowserToolCallContext, Tab) {
        let owner = Tab(uid: "owner", link: Link(title: "Owner", url: URL(string: "https://a.example")!), fireTab: false)
        let other = Tab(uid: "other", link: Link(title: "Other", url: URL(string: "https://b.example")!), fireTab: false)
        let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { [owner, other] })
        let scope = BrowserToolScope(owner: owner, source: source, selectedTabID: { other.uid })
        reader.pageContext = AIChatPageContextData(title: "t", favicon: [], url: "https://a.example", content: "a", truncated: false, fullContentLength: 1)
        let tool = ReadTabContentBrowserTool(scopeProvider: { _ in scope }, reader: reader)
        let context = BrowserToolCallContext(ownerTabID: owner.uid, ownerWindowToken: scope.token, isBurner: false)
        return (tool, context, other)
    }
}

private final class StubPageContentReader: BrowserToolPageContentReading {
    var pageContext: AIChatPageContextData?
    var beforeReturn: (() -> Void)?
    private(set) var requestedTabID: String?

    func pageContext(for tab: Tab, in scope: BrowserToolScope) async -> AIChatPageContextData? {
        requestedTabID = tab.uid
        beforeReturn?()
        return pageContext
    }
}
