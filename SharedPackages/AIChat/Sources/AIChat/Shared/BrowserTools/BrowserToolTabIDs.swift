//
//  BrowserToolTabIDs.swift
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

public enum BrowserToolTabIDs {
    case absent
    case ids([String])
    case invalid

    public init(arguments: JSONValue?, maxCount: Int) {
        guard let value = arguments?["tabIds"], value != .null else {
            self = .absent
            return
        }
        guard let values = value.arrayValue, !values.isEmpty, values.count <= maxCount else {
            self = .invalid
            return
        }
        var seen: Set<String> = []
        var ids: [String] = []
        for value in values {
            guard let id = value.stringValue?.trimmingCharacters(in: .whitespaces), !id.isEmpty else {
                self = .invalid
                return
            }
            if seen.insert(id).inserted { ids.append(id) }
        }
        self = .ids(ids)
    }
}
