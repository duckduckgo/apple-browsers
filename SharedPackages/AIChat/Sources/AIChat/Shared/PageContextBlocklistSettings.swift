//
//  PageContextBlocklistSettings.swift
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

public struct MediaCategoryRule: Codable, Equatable {
    public let urlExtensions: [String]?
    public let contentTypes: [String]?
    public let contentTypePrefixes: [String]?

    public init(urlExtensions: [String]? = nil, contentTypes: [String]? = nil, contentTypePrefixes: [String]? = nil) {
        self.urlExtensions = urlExtensions
        self.contentTypes = contentTypes
        self.contentTypePrefixes = contentTypePrefixes
    }
}

public struct PageContextBlocklistSettings: Equatable {
    public let categories: [String: MediaCategoryRule]

    public init(categories: [String: MediaCategoryRule]) {
        self.categories = categories
    }

    public init?(blocklist: Any?) {
        guard let dict = blocklist as? [String: Any], !dict.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let decoded = try? JSONDecoder().decode([String: MediaCategoryRule].self, from: data),
              !decoded.isEmpty else {
            return nil
        }
        self.categories = decoded
    }
}
