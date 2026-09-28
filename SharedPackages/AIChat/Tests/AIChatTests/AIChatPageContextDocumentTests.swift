//
//  AIChatPageContextDocumentTests.swift
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
@testable import AIChat

/// Covers the document carrier (`data` + `mimeType`) added for PDF page context.
final class AIChatPageContextDocumentTests: XCTestCase {

    private func json(_ context: AIChatPageContextData) throws -> [String: Any] {
        let encoded = try JSONEncoder().encode(context)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    }

    // MARK: - mimeType

    func testDecodingPayloadWithoutMIMETypeFallsBackToHTML() throws {
        // The payload Content-Scope-Scripts sends back carries no mimeType; decoding must not fail.
        let payload = """
        {"title": "Example", "favicon": [], "url": "https://example.com", "content": "text", "truncated": false, "fullContentLength": 4}
        """
        let decoded = try JSONDecoder().decode(AIChatPageContextData.self, from: Data(payload.utf8))

        XCTAssertEqual(decoded.mimeType, AIChatPageContextData.htmlMIMEType)
        XCTAssertNil(decoded.data)
    }

    func testDecodingPreservesMIMETypeAndData() throws {
        let payload = """
        {"title": "Doc", "favicon": [], "url": "https://example.com/a.pdf", "content": "", "truncated": false, "fullContentLength": 0, "mimeType": "application/pdf", "data": "JVBERi0="}
        """
        let decoded = try JSONDecoder().decode(AIChatPageContextData.self, from: Data(payload.utf8))

        XCTAssertEqual(decoded.mimeType, AIChatPageContextData.pdfMIMEType)
        XCTAssertEqual(decoded.data, "JVBERi0=")
        XCTAssertTrue(decoded.isDocument)
    }

    func testEveryPayloadEncodesMIMEType() throws {
        let markdown = AIChatPageContextData(title: "Example", favicon: [], url: "https://example.com", content: "text", truncated: false, fullContentLength: 4)

        XCTAssertEqual(try json(markdown)["mimeType"] as? String, AIChatPageContextData.htmlMIMEType)
        XCTAssertNil(try json(markdown)["data"], "A markdown context must not put a data key on the wire")
    }

    // MARK: - One carrier per context

    func testDocumentContextCarriesBytesAndNoMarkdown() throws {
        let document = AIChatPageContextData.document(
            title: "Spec",
            url: "https://example.com/spec.pdf",
            mimeType: AIChatPageContextData.pdfMIMEType,
            data: "JVBERi0="
        )

        XCTAssertTrue(document.isDocument)
        XCTAssertTrue(document.hasAttachedPage)
        XCTAssertEqual(document.content, "")
        XCTAssertFalse(document.truncated)
        XCTAssertEqual(document.fullContentLength, 0)

        let encoded = try json(document)
        XCTAssertEqual(encoded["data"] as? String, "JVBERi0=")
        XCTAssertEqual(encoded["content"] as? String, "")
    }

    func testDocumentContextWithoutBytesIsNotAnAttachedPage() {
        let refused = AIChatPageContextData.document(
            title: "Huge",
            url: "https://example.com/huge.pdf",
            mimeType: AIChatPageContextData.pdfMIMEType,
            data: nil,
            attachable: false
        )

        XCTAssertFalse(refused.isDocument)
        XCTAssertFalse(refused.hasAttachedPage)
        XCTAssertEqual(refused.attachable, false)
        XCTAssertEqual(refused.mimeType, AIChatPageContextData.pdfMIMEType)
    }

    func testMarkdownContextIsAnAttachedPage() {
        let markdown = AIChatPageContextData(title: "Example", favicon: [], url: "https://example.com", content: "text", truncated: false, fullContentLength: 4)

        XCTAssertFalse(markdown.isDocument)
        XCTAssertTrue(markdown.hasAttachedPage)
    }

    func testIsEmptyAccountsForDocumentBytes() {
        let bytesOnly = AIChatPageContextData.document(
            title: "",
            url: "https://example.com/a.pdf",
            mimeType: AIChatPageContextData.pdfMIMEType,
            data: "JVBERi0="
        )

        XCTAssertFalse(bytesOnly.isEmpty(), "A context carrying document bytes isn't empty")
    }

    // MARK: - Copy helpers

    func testCopyHelpersPreserveEveryOtherField() {
        let original = AIChatPageContextData(
            title: "Example",
            favicon: [AIChatPageContextData.PageContextFavicon(href: "https://example.com/f.ico", rel: "icon")],
            url: "https://example.com/a.pdf",
            content: "",
            truncated: false,
            fullContentLength: 0,
            attachable: true,
            tabId: "tab-1",
            pageTypeSignals: AIChatPageTypeSignals(jsonLdType: ["Article"], ogType: "article", lang: "en"),
            attached: true,
            mimeType: AIChatPageContextData.pdfMIMEType,
            data: "JVBERi0="
        )

        let newFavicon = [AIChatPageContextData.PageContextFavicon(href: "data:image/png;base64,abc", rel: "icon")]
        let copy = original.withFavicon(newFavicon)

        XCTAssertEqual(copy.favicon, newFavicon)
        XCTAssertEqual(copy.tabId, "tab-1")
        XCTAssertEqual(copy.pageTypeSignals, original.pageTypeSignals)
        XCTAssertEqual(copy.attached, true)
        XCTAssertEqual(copy.mimeType, AIChatPageContextData.pdfMIMEType)
        XCTAssertEqual(copy.data, "JVBERi0=")

        XCTAssertEqual(original.withAttachable(false).attachable, false)
        XCTAssertEqual(original.withAttachable(false).data, "JVBERi0=")
        XCTAssertNil(original.withTabId(nil).tabId)
        XCTAssertEqual(original.withTabId(nil).mimeType, AIChatPageContextData.pdfMIMEType)
    }
}
