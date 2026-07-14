//
//  PageContextAttachabilityPolicyTests.swift
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

final class PageContextAttachabilityPolicyTests: XCTestCase {

    private var policy: PageContextAttachabilityPolicy {
        let settings = PageContextBlocklistSettings(categories: [
            "pdf": MediaCategoryRule(urlExtensions: [".pdf"], contentTypes: ["application/pdf"]),
            "image": MediaCategoryRule(urlExtensions: [".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".bmp"],
                                       contentTypePrefixes: ["image/"]),
            "video": MediaCategoryRule(urlExtensions: [".mp4", ".webm", ".avi", ".mov", ".mkv"],
                                       contentTypePrefixes: ["video/"]),
            "audio": MediaCategoryRule(urlExtensions: [".mp3", ".wav", ".ogg", ".flac", ".aac", ".m4a"],
                                       contentTypePrefixes: ["audio/"]),
            "archive": MediaCategoryRule(contentTypes: ["application/zip"])
        ])
        return PageContextAttachabilityPolicy(settings: settings)
    }

    private func url(_ s: String) -> URL { URL(string: s)! }

    // MARK: Step 1 — special pages

    func testWhenPlainPageThenAttachable() {
        XCTAssertTrue(policy.verdict(url: url("https://example.com/article"), mimeType: "text/html").isAttachable)
    }

    func testWhenNilURLThenPreventedInternalPage() {
        let v = policy.verdict(url: nil, mimeType: nil)
        XCTAssertFalse(v.isAttachable)
        XCTAssertEqual(v.preventionReason, PageContextExtractionOutcome.internalPageCategory)
    }

    func testWhenAboutBlankThenPreventedInternalPage() {
        let v = policy.verdict(url: url("about:blank"), mimeType: nil)
        XCTAssertEqual(v.preventionReason, PageContextExtractionOutcome.internalPageCategory)
    }

    func testWhenDuckAIHostThenPreventedInternalPage() {
        XCTAssertEqual(policy.verdict(url: url("https://duck.ai"), mimeType: "text/html").preventionReason,
                       PageContextExtractionOutcome.internalPageCategory)
    }

    func testWhenDDGInPageChatThenPreventedInternalPage() {
        XCTAssertEqual(policy.verdict(url: url("https://duckduckgo.com/?ia=chat"), mimeType: "text/html").preventionReason,
                       PageContextExtractionOutcome.internalPageCategory)
    }

    func testWhenSERPQueryThenAttachable() {
        XCTAssertTrue(policy.verdict(url: url("https://duckduckgo.com/?q=bread+recipe"), mimeType: "text/html").isAttachable)
    }

    // MARK: Step 2 — MIME authoritative

    func testWhenPDFContentTypeThenPreventedPDF() {
        // extension-less URL serving application/pdf (e.g. .../download)
        XCTAssertEqual(policy.verdict(url: url("https://example.com/download"), mimeType: "application/pdf").preventionReason, "pdf")
    }

    func testWhenImageContentTypePrefixThenPreventedImage() {
        XCTAssertEqual(policy.verdict(url: url("https://example.com/pic"), mimeType: "image/png").preventionReason, "image")
    }

    func testWhenVideoContentTypePrefixThenPreventedVideo() {
        XCTAssertEqual(policy.verdict(url: url("https://example.com/clip"), mimeType: "video/mp4").preventionReason, "video")
    }

    func testWhenAudioContentTypePrefixThenPreventedAudio() {
        XCTAssertEqual(policy.verdict(url: url("https://example.com/song"), mimeType: "audio/mpeg").preventionReason, "audio")
    }

    func testWhenArbitraryCategoryContentTypeThenPreventedByCategory() {
        XCTAssertEqual(policy.verdict(url: url("https://example.com/bundle"), mimeType: "application/zip").preventionReason, "archive")
    }

    func testWhenPNGURLButHTMLMIMEThenAttachable() {
        // MIME is authoritative: a .png URL actually serving an HTML page stays attachable.
        XCTAssertTrue(policy.verdict(url: url("https://example.com/photo.png"), mimeType: "text/html").isAttachable)
    }

    // MARK: Step 3 — extension fallback (MIME absent)

    func testWhenPDFExtensionNoMIMEThenPreventedPDF() {
        XCTAssertEqual(policy.verdict(url: url("https://example.com/report.PDF"), mimeType: nil).preventionReason, "pdf")
    }

    func testWhenImageExtensionNoMIMEThenPreventedImage() {
        XCTAssertEqual(policy.verdict(url: url("https://example.com/photo.jpg"), mimeType: nil).preventionReason, "image")
    }

    func testWhenVideoExtensionNoMIMEThenPreventedVideo() {
        XCTAssertEqual(policy.verdict(url: url("https://example.com/movie.mp4"), mimeType: nil).preventionReason, "video")
    }

    func testWhenAudioExtensionNoMIMEThenPreventedAudio() {
        XCTAssertEqual(policy.verdict(url: url("https://example.com/track.mp3"), mimeType: nil).preventionReason, "audio")
    }

    func testWhenFileURLPDFThenPreventedPDF() {
        XCTAssertEqual(policy.verdict(url: url("file:///Users/me/doc.pdf"), mimeType: nil).preventionReason, "pdf")
    }

    func testWhenFileURLHTMLThenAttachable() {
        XCTAssertTrue(policy.verdict(url: url("file:///Users/me/page.html"), mimeType: nil).isAttachable)
    }

    func testWhenEmptyMIMEFallsBackToExtension() {
        XCTAssertEqual(policy.verdict(url: url("https://example.com/report.pdf"), mimeType: "").preventionReason, "pdf")
    }
}
