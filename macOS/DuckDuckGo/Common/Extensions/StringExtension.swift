//
//  StringExtension.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Common
import FoundationExtensions
import Foundation
import UniformTypeIdentifiers

extension String {

    // MARK: - General

    func escapedJavaScriptString() -> String {
        self.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static let unicodeHtmlCharactersMapping: [Character: String] = [
        "&": "&amp;",
        "\"": "&quot;",
        "'": "&apos;",
        "<": "&lt;",
        ">": "&gt;",
        "/": "&#x2F;",
        "!": "&excl;",
        "$": "&#36;",
        "%": "&percnt;",
        "=": "&#61;",
        "#": "&#35;",
        "@": "&#64;",
        "[": "&#91;",
        "\\": "&#92;",
        "]": "&#93;",
        "^": "&#94;",
        "`": "&#97;",
        "{": "&#123;",
        "}": "&#125;",
    ]
    func escapedUnicodeHtmlString() -> String {
        var result = ""

        for character in self {
            if let mapped = Self.unicodeHtmlCharactersMapping[character] {
                result.append(mapped)
            } else {
                result.append(character)
            }
        }

        return result
    }

    func replacingInvalidFileNameCharacters(with replacement: String = "_") -> String {
        replacingOccurrences(of: "[~#@*+%{}<>\\[\\]|\"\\_^\\/:\\\\]", with: replacement, options: .regularExpression)
    }

    var isBlank: Bool {
        self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Strips invisible / tofu-prone format characters while preserving emoji ZWJ
    /// sequences, emoji variation selectors, and Arabic/Persian ZWNJ/ZWJ shaping.
    ///
    /// Always removes Tags, ZWSP, WJ, soft hyphen, BOM, and C0/C1 controls other than
    /// tab/newline/carriage-return. Conditionally keeps ZWNJ/ZWJ/VS only when not
    /// adjacent to Latin (anti-smuggling) and needed for Arabic script or emoji.
    func removingInvisibleFormatCharacters() -> String {
        let scalars = Array(unicodeScalars)
        var kept: [Unicode.Scalar] = []
        kept.reserveCapacity(scalars.count)

        for index in scalars.indices {
            let scalar = scalars[index]

            switch scalar {
            case "\t", "\n", "\r":
                kept.append(scalar)
                continue
            default:
                break
            }

            if CharacterSet.controlCharacters.contains(scalar) {
                continue
            }

            if !scalar.properties.isDefaultIgnorableCodePoint {
                kept.append(scalar)
                continue
            }

            let value = scalar.value
            let isJoiner = value == 0x200C || value == 0x200D
            let isVariationSelector = value >= 0xFE00 && value <= 0xFE0F
            guard isJoiner || isVariationSelector else { continue }

            if Self.shouldKeepConditionalIgnorable(at: index, in: scalars) {
                kept.append(scalar)
            }
        }

        return String(String.UnicodeScalarView(kept))
    }

    private static func shouldKeepConditionalIgnorable(at index: Int, in scalars: [Unicode.Scalar]) -> Bool {
        let scalar = scalars[index]
        let value = scalar.value
        let isJoiner = value == 0x200C || value == 0x200D
        let isVariationSelector = value >= 0xFE00 && value <= 0xFE0F

        let prev = findScriptNeighbor(in: scalars, from: index, direction: -1)
        let next = findScriptNeighbor(in: scalars, from: index, direction: 1)

        if isLatinScript(prev) || isLatinScript(next) {
            return false
        }

        if isJoiner && (isArabicScript(prev) || isArabicScript(next)) {
            return true
        }

        if (isJoiner || isVariationSelector) && (isEmojiRelated(prev) || isEmojiRelated(next)) {
            return true
        }

        return false
    }

    private static func findScriptNeighbor(in scalars: [Unicode.Scalar], from index: Int, direction: Int) -> Unicode.Scalar? {
        var j = index + direction
        while j >= 0 && j < scalars.count {
            let value = scalars[j].value
            let isJoiner = value == 0x200C || value == 0x200D
            let isVariationSelector = value >= 0xFE00 && value <= 0xFE0F
            if isJoiner || isVariationSelector {
                j += direction
                continue
            }
            return scalars[j]
        }
        return nil
    }

    private static func isLatinScript(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        return String(scalar).range(of: #"\p{Script=Latin}"#, options: .regularExpression) != nil
    }

    private static func isArabicScript(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        return String(scalar).range(of: #"\p{Script=Arabic}"#, options: .regularExpression) != nil
    }

    private static func isEmojiRelated(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        let value = scalar.value
        if value == 0x200C || value == 0x200D { return true }
        if value >= 0xFE00 && value <= 0xFE0F { return true }
        if value >= 0x1F3FB && value <= 0x1F3FF { return true }
        if scalar.properties.isEmoji { return true }
        return String(scalar).range(of: #"\p{Extended_Pictographic}"#, options: .regularExpression) != nil
    }

    // MARK: - URL

    var url: URL? {
        return URL(trimmedAddressBarString: self)
    }

    static let localhost = "localhost"

    func dropSubdomain() -> String? {
        TLD().domain(self)
    }

    static func uniqueFilename(for fileType: UTType? = nil) -> String {
        let fileName = UUID().uuidString

        if let ext = fileType?.preferredFilenameExtension {
            return fileName.appending("." + ext)
        }

        return fileName
    }

    // MARK: - Mutating

    @inlinable mutating func prepend(_ string: String) {
        self = string + self
    }

    // MARK: - Prefix

    func hasOrIsPrefix(of other: String) -> Bool {
        return hasPrefix(other) || other.hasPrefix(self)
    }

}
