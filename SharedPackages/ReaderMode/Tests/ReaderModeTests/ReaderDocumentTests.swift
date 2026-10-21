//
//  ReaderDocumentTests.swift
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
import Testing
@testable import ReaderMode

struct ReaderDocumentTests {

    private func article(title: String = "Title", siteName: String? = nil) -> ReaderArticle {
        ReaderArticle(url: URL(string: "https://example.com/a")!, title: title, siteName: siteName, contentHTML: "<p>Body</p>", textLength: 4)
    }

    @available(macOS 13, *)
    @Test("Title and site name are HTML-escaped", .timeLimit(.minutes(1)))
    func escapesTitleAndSiteName() {
        let html = ReaderDocument.html(for: article(title: "<script>alert(1)</script> & \"q\"", siteName: "<b>Site</b>"), theme: .designSystem)

        #expect(!html.contains("<script>"))
        #expect(!html.contains("<b>Site</b>"))
        #expect(html.contains("<h1>&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;q&quot;</h1>"))
        #expect(html.contains("&lt;b&gt;Site&lt;/b&gt;"))
    }

    @available(macOS 13, *)
    @Test("Document carries a CSP that blocks scripts", .timeLimit(.minutes(1)))
    func containsContentSecurityPolicy() {
        let html = ReaderDocument.html(for: article(), theme: .designSystem)

        #expect(html.contains("<meta http-equiv=\"Content-Security-Policy\" content=\"\(ReaderDocument.contentSecurityPolicy)\">"))
        #expect(ReaderDocument.contentSecurityPolicy.hasPrefix("default-src 'none';"))
    }

    @available(macOS 13, *)
    @Test("Content is embedded and site line is omitted without a site name", .timeLimit(.minutes(1)))
    func embedsContent() {
        let html = ReaderDocument.html(for: article(), theme: .designSystem)

        #expect(html.contains("<p>Body</p>"))
        #expect(!html.contains("class=\"site\""))
    }
}
