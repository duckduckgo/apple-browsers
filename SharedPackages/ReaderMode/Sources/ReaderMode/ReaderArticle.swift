//
//  ReaderArticle.swift
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

/// An article extracted from a page, with its content reduced to a safe subset of HTML.
public struct ReaderArticle: Equatable, Sendable {
    public let url: URL
    public let title: String
    public let author: String?
    public let siteName: String?
    /// Sanitized article body.
    public let contentHTML: String
    public let textLength: Int

    /// Sanitizes `contentHTML`, so no caller can create an article that carries unsafe markup.
    public init(url: URL, title: String, author: String? = nil, siteName: String?, contentHTML: String, textLength: Int) {
        self.url = url
        self.title = title
        self.author = author
        self.siteName = siteName
        self.contentHTML = (try? ReaderDocument.sanitize(contentHTML, title: title, author: author, baseURL: url)) ?? ""
        self.textLength = textLength
    }
}
