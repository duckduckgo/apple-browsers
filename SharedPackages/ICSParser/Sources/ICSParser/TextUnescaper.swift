//
//  TextUnescaper.swift
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

/// RFC 5545 §3.3.11 text escape handling for property values like SUMMARY, DESCRIPTION,
/// and LOCATION. Recognised sequences: `\n` and `\N` (newline), `\,`, `\;`, `\\`.
enum TextUnescaper {

    static func unescape(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        var iterator = value.makeIterator()
        while let character = iterator.next() {
            guard character == "\\" else {
                result.append(character)
                continue
            }
            guard let next = iterator.next() else {
                result.append(character)
                break
            }
            switch next {
            case "n", "N":
                result.append("\n")
            case ",":
                result.append(",")
            case ";":
                result.append(";")
            case "\\":
                result.append("\\")
            default:
                result.append(character)
                result.append(next)
            }
        }
        return result
    }
}
