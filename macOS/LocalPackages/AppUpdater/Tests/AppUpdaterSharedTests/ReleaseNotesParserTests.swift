//
//  ReleaseNotesParserTests.swift
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

import AppUpdaterShared
import BrowserServicesKit
import XCTest

final class ReleaseNotesParserTests: XCTestCase {

    func testParseReleaseNotes_withEmptyDescription() {
        let description: String? = nil
        let (standard, subscription) = ReleaseNotesParser.parseReleaseNotes(from: description)

        XCTAssertTrue(standard.isEmpty)
        XCTAssertTrue(subscription.isEmpty)
    }

    func testParseReleaseNotes_withOnlyStandardNotes() {
        let description = """
        <h3>What's new</h3>
        <ul>
            <li>New feature A</li>
            <li>Improvement B</li>
        </ul>
        """
        let (standard, subscription) = ReleaseNotesParser.parseReleaseNotes(from: description)

        XCTAssertEqual(standard, ["New feature A", "Improvement B"])
        XCTAssertTrue(subscription.isEmpty)
    }

    func testParseReleaseNotes_withOnlySubscriptionNotes() {
        let description = """
        <h3>For DuckDuckGo subscribers</h3>
        <ul>
            <li>Exclusive feature X</li>
            <li>Exclusive improvement Y</li>
        </ul>
        """
        let (standard, subscription) = ReleaseNotesParser.parseReleaseNotes(from: description)

        XCTAssertTrue(standard.isEmpty)
        XCTAssertEqual(subscription, ["Exclusive feature X", "Exclusive improvement Y"])
    }

    func testParseReleaseNotes_withBothSections() {
        let description = """
        <h3>What's new</h3>
        <ul>
            <li>New feature A</li>
            <li>Improvement B</li>
        </ul>
        <h3>For DuckDuckGo subscribers</h3>
        <ul>
            <li>Exclusive feature X</li>
            <li>Exclusive improvement Y</li>
        </ul>
        """
        let (standard, subscription) = ReleaseNotesParser.parseReleaseNotes(from: description)

        XCTAssertEqual(standard, ["New feature A", "Improvement B"])
        XCTAssertEqual(subscription, ["Exclusive feature X", "Exclusive improvement Y"])
    }

    /// The section header carries a `style` attribute in real appcast payloads (see the real-data
    /// fixtures below). Matching must be on the header text, not an exact tag.
    func testParseReleaseNotes_withStyledHeader() {
        let description = """
        <h3 style="font-size:14px">What's new</h3>
        <ul>
            <li>New feature A</li>
        </ul>
        """
        let (standard, _) = ReleaseNotesParser.parseReleaseNotes(from: description)

        XCTAssertEqual(standard, ["New feature A"])
    }

    /// Multi-byte characters (e.g. `⌘`) and HTML entities (e.g. `&amp;`) must survive parsing.
    /// This guards against libxml2's HTML parser defaulting to ISO-8859-1 for the byte stream.
    func testParseReleaseNotes_preservesUnicodeAndEntities() {
        let description = """
        <h3>What's new</h3>
        <ul>
            <li>Open Duck.ai with the ⌘+E shortcut &amp; enjoy it.</li>
        </ul>
        """
        let (standard, _) = ReleaseNotesParser.parseReleaseNotes(from: description)

        XCTAssertEqual(standard, ["Open Duck.ai with the ⌘+E shortcut & enjoy it."])
    }

    func testParseReleaseNotes_withMissingSectionsReturnsEmpty() {
        let description = "<p>No release notes here.</p>"
        let (standard, subscription) = ReleaseNotesParser.parseReleaseNotes(from: description)

        XCTAssertTrue(standard.isEmpty)
        XCTAssertTrue(subscription.isEmpty)
    }

    /// Behavioral note: the legacy regex/`NSAttributedString` parser silently dropped an unterminated
    /// `<li>` item. The `XMLDocument` parser recovers it instead (libxml2 closes the tag), which is the
    /// safer behavior. This is the one intentional divergence from the legacy parser and is excluded
    /// from the equivalence test below.
    func testParseReleaseNotes_recoversUnterminatedListItem() {
        let description = """
        <h3>What's new</h3>
        <ul>
            <li>New feature A</li>
            <li>Improvement B
        </ul>
        <h3>For DuckDuckGo subscribers</h3>
        <ul>
            <li>Exclusive feature X</li>
            <li>Exclusive improvement Y</li>
        </ul>
        """
        let (standard, subscription) = ReleaseNotesParser.parseReleaseNotes(from: description)

        XCTAssertEqual(standard, ["New feature A", "Improvement B"])
        XCTAssertEqual(subscription, ["Exclusive feature X", "Exclusive improvement Y"])
    }

    // MARK: - Real appcast fixtures

    func testParseReleaseNotes_realAppcastSingleItem() {
        let (standard, subscription) = ReleaseNotesParser.parseReleaseNotes(from: Self.realStandardOnly)

        XCTAssertEqual(standard, ["Bug fixes and improvements."])
        XCTAssertTrue(subscription.isEmpty)
    }

    func testParseReleaseNotes_realAppcastMultipleItems() {
        let (standard, subscription) = ReleaseNotesParser.parseReleaseNotes(from: Self.realMultiItem)

        XCTAssertEqual(standard, [
            "You can now open and close the Duck.ai sidebar with the ⌘+E keyboard shortcut. If you have text selected when using the shortcut to open Duck.ai, it will automatically be pasted into the sidebar.",
            "We fixed a bug that caused the website permission dialog to appear in the middle of the page instead of up in the left side of the address bar where it should be.",
            "Any issues you may have experienced with autocomplete when the browser update reminder was visible have also been fixed.",
            "As usual, this update includes other bug fixes and improvements."
        ])
        XCTAssertTrue(subscription.isEmpty)
    }

    // MARK: - Equivalence with the legacy parser

    /// Proves the new `XMLDocument` parser produces identical output to the original regex /
    /// `NSAttributedString` implementation (reproduced verbatim as `LegacyReleaseNotesParser`)
    /// for every well-formed input. The only known divergence — recovery of malformed/unterminated
    /// list items — is covered separately by `testParseReleaseNotes_recoversUnterminatedListItem`.
    func testParseReleaseNotes_matchesLegacyParserForWellFormedHTML() {
        let fixtures = [
            Self.realStandardOnly,
            Self.realMultiItem,
            Self.syntheticBothSections,
            "<h3 style=\"font-size:14px\">What's new</h3><ul><li>Open Duck.ai with the ⌘+E shortcut &amp; enjoy it.</li></ul>",
            "<p>No release notes here.</p>"
        ]

        for fixture in fixtures {
            let new = ReleaseNotesParser.parseReleaseNotes(from: fixture)
            let legacy = LegacyReleaseNotesParser.parseReleaseNotes(from: fixture)
            XCTAssertEqual(new.0, legacy.0, "Standard notes differ for fixture:\n\(fixture)")
            XCTAssertEqual(new.1, legacy.1, "Subscription notes differ for fixture:\n\(fixture)")
        }
    }

    // MARK: - Fixtures

    private static let realStandardOnly = """
    <h3 style="font-size:14px">What's new</h3>
    <ul>
    <li>Bug fixes and improvements.</li>
    </ul>
    """

    private static let realMultiItem = """
    <h3 style="font-size:14px">What's new</h3>
    <ul>
    <li>You can now open and close the Duck.ai sidebar with the ⌘+E keyboard shortcut. If you have text selected when using the shortcut to open Duck.ai, it will automatically be pasted into the sidebar.</li>
    <li>We fixed a bug that caused the website permission dialog to appear in the middle of the page instead of up in the left side of the address bar where it should be.</li>
    <li>Any issues you may have experienced with autocomplete when the browser update reminder was visible have also been fixed.</li>
    <li>As usual, this update includes other bug fixes and improvements.</li>
    </ul>
    """

    private static let syntheticBothSections = """
    <h3>What's new</h3>
    <ul>
        <li>New feature A</li>
        <li>Improvement B</li>
    </ul>
    <h3>For DuckDuckGo subscribers</h3>
    <ul>
        <li>Exclusive feature X</li>
        <li>Exclusive improvement Y</li>
    </ul>
    """
}

/// Verbatim copy of the original `ReleaseNotesParser` implementation (regex + `NSAttributedString`),
/// kept in the test target only, as the reference for the equivalence test above.
private enum LegacyReleaseNotesParser {

    static func parseReleaseNotes(from description: String?) -> ([String], [String]) {
        guard let description else { return ([], []) }

        var standardReleaseNotes = [String]()
        var subscriptionReleaseNotes = [String]()

        let standardPattern = "<h3[^>]*>What's new</h3>\\s*<ul>(.*?)</ul>"
        let subscriptionPattern = "<h3[^>]*>For DuckDuckGo subscribers</h3>\\s*<ul>(.*?)</ul>"

        do {
            let standardRegex = try NSRegularExpression(pattern: standardPattern, options: .dotMatchesLineSeparators)
            let subscriptionRegex = try NSRegularExpression(pattern: subscriptionPattern, options: .dotMatchesLineSeparators)

            if let standardMatch = standardRegex.firstMatch(in: description, options: [], range: NSRange(location: 0, length: description.utf16.count)) {
                if let range = Range(standardMatch.range(at: 1), in: description) {
                    let standardList = String(description[range])
                    standardReleaseNotes = extractListItems(from: standardList)
                }
            }

            if let subscriptionMatch = subscriptionRegex.firstMatch(in: description, options: [], range: NSRange(location: 0, length: description.utf16.count)) {
                if let range = Range(subscriptionMatch.range(at: 1), in: description) {
                    let subscriptionList = String(description[range])
                    subscriptionReleaseNotes = extractListItems(from: subscriptionList)
                }
            }
        } catch {
            assertionFailure("Error creating regular expression: \(error)")
        }

        return (standardReleaseNotes, subscriptionReleaseNotes)
    }

    private static func extractListItems(from list: String) -> [String] {
        var items = [String]()
        let pattern = "<li>(.*?)</li>"

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
            let matches = regex.matches(in: list, options: [], range: NSRange(location: 0, length: list.utf16.count))

            for match in matches {
                if let range = Range(match.range(at: 1), in: list) {
                    let item = String(list[range])

                    if let data = item.data(using: .utf8),
                       let attributedString = try? NSAttributedString(data: data,
                                                                      options: [.documentType: NSAttributedString.DocumentType.html,
                                                                                .characterEncoding: String.Encoding.utf8.rawValue],
                                                                      documentAttributes: nil) {
                        items.append(attributedString.string)
                    }
                }
            }
        } catch {
            assertionFailure("Error creating regular expression: \(error)")
        }

        return items
    }
}
