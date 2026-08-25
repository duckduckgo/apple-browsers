//
//  DocumentPageContextProviderTests.swift
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

final class MockMainResourceDataProvider: MainResourceDataProviding {
    var data: Data?

    init(data: Data?) {
        self.data = data
    }

    @MainActor
    func mainResourceData(timeout: TimeInterval) async -> Data? {
        data
    }
}

@MainActor
final class DocumentPageContextProviderTests: XCTestCase {

    private let url = URL(string: "https://example.com/spec.pdf")!

    private func pdfData(byteCount: Int = 32) -> Data {
        var data = Data("%PDF-1.7\n".utf8)
        data.append(Data(repeating: 0x41, count: max(0, byteCount - data.count)))
        return data
    }

    // MARK: - isSupportedDocument

    func testMIMETypeIdentifiesADocument() {
        XCTAssertTrue(DocumentPageContextProvider.isSupportedDocument(mimeType: "application/pdf", url: url))
        XCTAssertFalse(DocumentPageContextProvider.isSupportedDocument(mimeType: "text/html", url: url),
                       "The MIME type wins over the URL extension when we have one")
    }

    func testURLExtensionIsUsedWhenMIMETypeIsMissing() {
        XCTAssertTrue(DocumentPageContextProvider.isSupportedDocument(mimeType: nil, url: url))
        XCTAssertTrue(DocumentPageContextProvider.isSupportedDocument(mimeType: "", url: url))
        XCTAssertFalse(DocumentPageContextProvider.isSupportedDocument(mimeType: nil, url: URL(string: "https://example.com/page")!))
    }

    // MARK: - makeDocumentContext

    func testAttachesDocumentBytes() async throws {
        let bytes = pdfData()
        let result = await DocumentPageContextProvider.makeDocumentContext(
            webView: MockMainResourceDataProvider(data: bytes),
            url: url,
            title: "Spec"
        )

        guard case .document(let context) = result else {
            return XCTFail("Expected a document context, got \(result)")
        }
        XCTAssertEqual(context.data, bytes.base64EncodedString())
        XCTAssertEqual(context.mimeType, AIChatPageContextData.pdfMIMEType)
        XCTAssertEqual(context.url, url.absoluteString)
        XCTAssertEqual(context.title, "Spec")
        XCTAssertEqual(context.content, "", "Bytes and markdown are exclusive carriers")
        XCTAssertNil(context.attachable)
    }

    func testDocumentOverTheCeilingIsRefusedWithoutBytes() async throws {
        let result = await DocumentPageContextProvider.makeDocumentContext(
            webView: MockMainResourceDataProvider(data: pdfData(byteCount: 64)),
            url: url,
            title: "Huge",
            maxBytes: 32
        )

        guard case .tooLarge(let context) = result else {
            return XCTFail("Expected the document to be refused, got \(result)")
        }
        XCTAssertNil(context.data, "A refused document must not ship its bytes across the bridge")
        XCTAssertEqual(context.attachable, false)
        XCTAssertEqual(context.mimeType, AIChatPageContextData.pdfMIMEType)
    }

    func testDocumentAtTheCeilingIsAttached() async throws {
        let bytes = pdfData(byteCount: 32)
        let result = await DocumentPageContextProvider.makeDocumentContext(
            webView: MockMainResourceDataProvider(data: bytes),
            url: url,
            title: "Exactly at the limit",
            maxBytes: bytes.count
        )

        guard case .document = result else {
            return XCTFail("Expected a document context, got \(result)")
        }
    }

    func testUnreadableBytesAreUnavailable() async throws {
        let missing = await DocumentPageContextProvider.makeDocumentContext(
            webView: MockMainResourceDataProvider(data: nil),
            url: url,
            title: "Spec"
        )
        XCTAssertEqual(missing, .unavailable)

        let notAPDF = await DocumentPageContextProvider.makeDocumentContext(
            webView: MockMainResourceDataProvider(data: Data("<html></html>".utf8)),
            url: url,
            title: "Spec"
        )
        XCTAssertEqual(notAPDF, .unavailable, "Bytes that aren't a PDF are never handed over")
    }

    // MARK: - metadataContext

    func testMetadataContextSaysWhatTheTabIsWithoutHandingItOver() {
        let context = DocumentPageContextProvider.metadataContext(url: url, title: "Spec", attachable: true, attached: false)

        XCTAssertNil(context.data)
        XCTAssertEqual(context.mimeType, AIChatPageContextData.pdfMIMEType)
        XCTAssertEqual(context.attachable, true)
        XCTAssertEqual(context.attached, false)
        XCTAssertFalse(context.hasAttachedPage)
    }
}
