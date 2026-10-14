//
//  RawJSONSettingsLocator.swift
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

/// Finds the bytes of each feature's `settings`, and each sub-feature's, in a privacy configuration.
///
/// `JSONSerialization` gives objects in hash order, so a configuration written back from its parsed
/// form loses the key order of the downloaded one. Copying `settings` from these ranges keeps it.
///
/// The input is expected to be JSON that `JSONSerialization` has already accepted. Anything the
/// locator does not recognise gives `nil` rather than a guess.
struct RawJSONSettingsLocator {

    struct FeatureSettingsRanges: Equatable {
        let settings: Range<Int>?
        let subfeatureSettings: [String: Range<Int>]
    }

    let bytes: [UInt8]

    init(data: Data) {
        self.bytes = [UInt8](data)
    }

    /// The ranges in `bytes` of the `settings` values, keyed by feature name.
    /// A feature or sub-feature whose value is not an object is left out.
    func locate() -> [String: FeatureSettingsRanges]? {
        guard let root = objectMembers(in: bytes.indices),
              let featuresRange = root["features"],
              let features = objectMembers(in: featuresRange) else { return nil }

        var result = [String: FeatureSettingsRanges]()
        for (name, featureRange) in features {
            guard let feature = objectMembers(in: featureRange) else { continue }

            var subfeatureSettings = [String: Range<Int>]()
            if let subfeaturesRange = feature["features"], let subfeatures = objectMembers(in: subfeaturesRange) {
                for (subfeatureName, subfeatureRange) in subfeatures {
                    if let settings = objectMembers(in: subfeatureRange)?["settings"] {
                        subfeatureSettings[subfeatureName] = settings
                    }
                }
            }
            result[name] = FeatureSettingsRanges(settings: feature["settings"], subfeatureSettings: subfeatureSettings)
        }
        return result
    }

    /// The value range of each member of the object in `range`. A repeated key keeps its last value.
    private func objectMembers(in range: Range<Int>) -> [String: Range<Int>]? {
        var index = skipWhitespace(from: range.lowerBound)
        guard index < range.upperBound, bytes[index] == .openBrace else { return nil }

        var members = [String: Range<Int>]()
        index = skipWhitespace(from: index + 1)
        if index < range.upperBound, bytes[index] == .closeBrace {
            return members
        }

        while index < range.upperBound {
            guard let keyEnd = endOfString(at: index), let key = decodeKey(index..<keyEnd) else { return nil }

            index = skipWhitespace(from: keyEnd)
            guard index < range.upperBound, bytes[index] == .colon else { return nil }

            let valueStart = skipWhitespace(from: index + 1)
            guard let valueEnd = endOfValue(at: valueStart), valueEnd <= range.upperBound else { return nil }
            members[key] = valueStart..<valueEnd

            index = skipWhitespace(from: valueEnd)
            guard index < range.upperBound else { return nil }
            if bytes[index] == .closeBrace {
                return members
            }
            guard bytes[index] == .comma else { return nil }
            index = skipWhitespace(from: index + 1)
        }
        return nil
    }

    private func skipWhitespace(from start: Int) -> Int {
        var index = start
        while index < bytes.count, bytes[index].isJSONWhitespace {
            index += 1
        }
        return index
    }

    /// The index after the closing quote of the string that opens at `start`.
    private func endOfString(at start: Int) -> Int? {
        guard start < bytes.count, bytes[start] == .quote else { return nil }

        var index = start + 1
        while index < bytes.count {
            switch bytes[index] {
            case .backslash: index += 2
            case .quote: return index + 1
            default: index += 1
            }
        }
        return nil
    }

    /// The index after the value that starts at `start`.
    private func endOfValue(at start: Int) -> Int? {
        guard start < bytes.count else { return nil }

        switch bytes[start] {
        case .quote:
            return endOfString(at: start)
        case .openBrace, .openBracket:
            return endOfContainer(at: start)
        default:
            var index = start
            while index < bytes.count, !bytes[index].endsJSONScalar {
                index += 1
            }
            return index > start ? index : nil
        }
    }

    /// The index after the object or array that opens at `start`.
    private func endOfContainer(at start: Int) -> Int? {
        var depth = 0
        var index = start
        while index < bytes.count {
            switch bytes[index] {
            case .quote:
                guard let stringEnd = endOfString(at: index) else { return nil }
                index = stringEnd
                continue
            case .openBrace, .openBracket:
                depth += 1
            case .closeBrace, .closeBracket:
                depth -= 1
                if depth == 0 {
                    return index + 1
                }
            default:
                break
            }
            index += 1
        }
        return nil
    }

    /// The key in the quoted string at `range`. Only a key holding an escape goes through `JSONSerialization`.
    private func decodeKey(_ range: Range<Int>) -> String? {
        let quoted = bytes[range]
        guard quoted.contains(.backslash) else {
            return String(decoding: quoted.dropFirst().dropLast(), as: UTF8.self)
        }
        return (try? JSONSerialization.jsonObject(with: Data(quoted), options: .fragmentsAllowed)) as? String
    }
}

private extension UInt8 {
    static let quote = UInt8(ascii: "\"")
    static let backslash = UInt8(ascii: "\\")
    static let openBrace = UInt8(ascii: "{")
    static let closeBrace = UInt8(ascii: "}")
    static let openBracket = UInt8(ascii: "[")
    static let closeBracket = UInt8(ascii: "]")
    static let colon = UInt8(ascii: ":")
    static let comma = UInt8(ascii: ",")

    var isJSONWhitespace: Bool {
        self == UInt8(ascii: " ") || self == UInt8(ascii: "\t") || self == UInt8(ascii: "\n") || self == UInt8(ascii: "\r")
    }

    var endsJSONScalar: Bool {
        isJSONWhitespace || self == .comma || self == .closeBrace || self == .closeBracket
    }
}
