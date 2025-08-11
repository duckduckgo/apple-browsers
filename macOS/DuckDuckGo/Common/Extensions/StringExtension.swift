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
import Foundation
import UniformTypeIdentifiers

extension String {

    // MARK: - General

    func truncated(length: Int, trailing: String = "…") -> String {
      return (self.count > length) ? self.prefix(length) + trailing : self
    }

    func truncated(length: Int, middle: String) -> String {
        guard self.count > length else { return self }

        let halfLength = length / 2
        let start = self.prefix(halfLength).trimmingCharacters(in: .whitespaces)
        let end = self.suffix(halfLength).trimmingCharacters(in: .whitespaces)
        return "\(start)\(middle)\(end)"
    }

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

    /// Used to cut string contents including and after a detected file path. Used to sanitize a string that may have a file path in it but should be excluded.
    /// This function will cut all content including and after the first file path, so shouldn't be used if you need to include content between multiple file paths.
    ///
    /// The intended use case for this function is to sanitize an error message that may contain a trailing file path, but the initial string contents are still valuable
    /// for debugging the issue.
    func strippingFilePaths() -> String {
        let pattern = #"(^|[\s\(\[\{:])(file://\S+|~(?=/)\S*|/\S+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return self
        }

        let nsRange = NSRange(startIndex..<endIndex, in: self)
        let matches = regex.matches(in: self, range: nsRange)

        guard let first = matches.first, let pathRange = Range(first.range(at: 2), in: self) else { return self }

        let head = self[..<pathRange.lowerBound]
        return head.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - URL

    var url: URL? {
        return URL(trimmedAddressBarString: self)
    }

    static let localhost = "localhost"

    func dropSubdomain() -> String? {
        let parts = components(separatedBy: ".")
        guard parts.count > 1 else { return nil }
        return parts.dropFirst().joined(separator: ".")
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
