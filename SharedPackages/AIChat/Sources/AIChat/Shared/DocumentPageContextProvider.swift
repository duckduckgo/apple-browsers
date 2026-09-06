//
//  DocumentPageContextProvider.swift
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

import Foundation

/// Builds page context for tabs the page-context user script can't read: documents rendered by
/// WebKit itself (PDFs today). Instead of markdown in `content`, these contexts carry the document's
/// bytes in `data`, which Duck.ai treats as an attachment.
///
/// Validation stays on the Duck.ai side — page count, tier limits, encryption, model support — with
/// one exception: `maxDocumentBytes`, a safety ceiling so a huge document can't be base64'd across
/// the JS bridge. Over it the context still says what the tab is, but hands over nothing.
public enum DocumentPageContextProvider {

    /// Ceiling on the document bytes native will hand over. Base64 inflates this by ~33% on the
    /// wire, and the whole payload crosses the bridge as one string.
    public static let maxDocumentBytes = 30 * 1024 * 1024

    private static let pdfMagicBytes = Data("%PDF-".utf8)

    public enum Result: Equatable {
        /// The document's bytes are attached.
        case document(AIChatPageContextData)
        /// Over `maxDocumentBytes` — context marked non-attachable, no bytes.
        case tooLarge(AIChatPageContextData)
        /// The bytes couldn't be read, or they aren't the document we expected.
        case unavailable
    }

    /// Whether this tab is a document handed over as bytes. Prefers the main-frame MIME type from the
    /// navigation response and falls back to the URL extension when it wasn't captured (a back/forward
    /// restore doesn't re-fire the response delegate).
    public static func isSupportedDocument(mimeType: String?, url: URL) -> Bool {
        if let mimeType, !mimeType.isEmpty {
            return mimeType.lowercased() == AIChatPageContextData.pdfMIMEType
        }
        return url.pathExtension.lowercased() == "pdf"
    }

    @MainActor
    public static func makeDocumentContext(webView: MainResourceDataProviding,
                                           url: URL,
                                           title: String,
                                           favicon: [AIChatPageContextData.PageContextFavicon] = [],
                                           maxBytes: Int = maxDocumentBytes,
                                           timeout: TimeInterval = 5) async -> Result {
        guard let data = await webView.mainResourceData(timeout: timeout),
              data.starts(with: pdfMagicBytes) else {
            return .unavailable
        }

        guard data.count <= maxBytes else {
            return .tooLarge(metadataContext(url: url, title: title, favicon: favicon, attachable: false))
        }

        return .document(AIChatPageContextData.document(
            title: title,
            favicon: favicon,
            url: url.absoluteString,
            mimeType: AIChatPageContextData.pdfMIMEType,
            data: await Task.detached(priority: .userInitiated) { data.base64EncodedString() }.value
        ))
    }

    /// A document context with no bytes: says what the tab is without handing it over. Used while
    /// auto-attach is off — the chip shows, and the bytes only follow once the user asks for them.
    public static func metadataContext(url: URL,
                                       title: String,
                                       favicon: [AIChatPageContextData.PageContextFavicon] = [],
                                       attachable: Bool? = nil,
                                       attached: Bool? = nil) -> AIChatPageContextData {
        AIChatPageContextData.document(
            title: title,
            favicon: favicon,
            url: url.absoluteString,
            mimeType: AIChatPageContextData.pdfMIMEType,
            data: nil,
            attachable: attachable,
            attached: attached
        )
    }
}
