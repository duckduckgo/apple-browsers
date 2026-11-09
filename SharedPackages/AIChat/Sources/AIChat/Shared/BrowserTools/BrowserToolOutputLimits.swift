//
//  BrowserToolOutputLimits.swift
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

/// Field limits from the client-tools contract, applied at the browser-tools boundary only.
public enum BrowserToolOutputLimits {
    public static let title = 256
    public static let url = 1280
    public static let content = 3000
    public static let snippet = 100
    public static let query = 1000

    /// JSON Schema `maxLength` counts code points, so this cuts by Unicode scalar.
    public static func clip(_ value: String, to limit: Int) -> String {
        guard value.unicodeScalars.count > limit else { return value }
        return String(String.UnicodeScalarView(value.unicodeScalars.prefix(limit)))
    }

    /// Clips a string value and leaves anything else untouched.
    public static func clip(_ value: JSONValue?, to limit: Int) -> JSONValue? {
        guard case .string(let text)? = value else { return value }
        return .string(clip(text, to: limit))
    }

    public static func fits(_ value: String, within limit: Int) -> Bool {
        value.unicodeScalars.count <= limit
    }
}
