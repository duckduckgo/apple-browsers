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

    /// An unterminated `<li>` item is recovered rather than dropped, because libxml2 closes the tag
    /// while parsing.
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
}
