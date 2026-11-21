//
//  PageTranslationUnit.swift
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

import Foundation

/// A piece of page text C-S-S's `pageTranslation` extracted. With `html`, `text` holds the unit's HTML.
public struct PageTranslationUnit: Decodable, Equatable, Sendable {
    public let id: Int
    public let text: String
    public let html: Bool
    /// 1 when the unit was in the viewport at extraction.
    public let vp: Int

    public var isVisible: Bool { vp != 0 }

    public init(id: Int, text: String, html: Bool, vp: Int) {
        self.id = id
        self.text = text
        self.html = html
        self.vp = vp
    }
}

/// A translated unit for C-S-S to apply: `text` for plain units, `tree` (translate-kit's JSON tree) for HTML ones.
public struct PageTranslationUpdate: Encodable, Equatable, Sendable {
    public let id: Int
    public let text: String?
    public let tree: String?

    public init(id: Int, text: String? = nil, tree: String? = nil) {
        self.id = id
        self.text = text
        self.tree = tree
    }
}
