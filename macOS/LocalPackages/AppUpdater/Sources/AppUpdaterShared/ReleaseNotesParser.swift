//
//  ReleaseNotesParser.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

public final class ReleaseNotesParser {

    /// Extracts the "What's new" and "For DuckDuckGo subscribers" bullet lists from an appcast
    /// item description.
    ///
    /// Parsing is done with `XMLDocument` (libxml2) rather than `NSAttributedString`'s HTML
    /// importer: the latter instantiates WebKit and must run on the main thread, which blocked
    /// app launch while release notes were parsed. `XMLDocument` is a pure libxml2 parse with no
    /// such dependency.
    public static func parseReleaseNotes(from description: String?) -> ([String], [String]) {
        guard let description else { return ([], []) }

        guard let document = htmlDocument(from: description) else { return ([], []) }

        let standardReleaseNotes = releaseNotes(in: document, forSectionTitled: "What's new")
        let subscriptionReleaseNotes = releaseNotes(in: document, forSectionTitled: "For DuckDuckGo subscribers")
        return (standardReleaseNotes, subscriptionReleaseNotes)
    }

    /// Parses the release notes HTML fragment into an `XMLDocument`.
    ///
    /// The fragment is prefixed with a `Content-Type` charset declaration. Without it, libxml2's
    /// HTML parser assumes ISO-8859-1 and mangles multi-byte characters (e.g. `⌘`). The HTML5
    /// `<meta charset>` shorthand is not honored by libxml2, so the `http-equiv` form is used.
    private static func htmlDocument(from description: String) -> XMLDocument? {
        let charsetDeclaration = #"<meta http-equiv="Content-Type" content="text/html; charset=utf-8">"#
        guard let data = (charsetDeclaration + description).data(using: .utf8) else { return nil }

        do {
            return try XMLDocument(data: data, options: [.documentTidyHTML])
        } catch {
            assertionFailure("Error parsing release notes HTML: \(error)")
            return nil
        }
    }

    /// Returns the plain-text list items from the `<ul>` immediately following the `<h3>` whose
    /// text matches `title`.
    private static func releaseNotes(in document: XMLDocument, forSectionTitled title: String) -> [String] {
        let xpath = "//h3[normalize-space(.)=\"\(title)\"]/following-sibling::ul[1]/li"
        guard let items = try? document.nodes(forXPath: xpath) else { return [] }

        return items.compactMap { item in
            guard let text = item.stringValue else { return nil }
            // Collapse runs of whitespace (including the newlines/indentation between tags) into
            // single spaces, matching how the HTML would render as plain text.
            let normalized = text.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return normalized.isEmpty ? nil : normalized
        }
    }
}
