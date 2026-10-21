//
//  WebExtensionAPICompatibilityLogTests.swift
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

import XCTest
@testable import WebExtensions

final class WebExtensionAPICompatibilityLogTests: XCTestCase {

    // MARK: - Line Format

    func testLineHasKindAPIExtensionAndVersion() {
        let line = WebExtensionAPICompatibilityLog.line(kind: .stubbed, api: "chrome.notifications.create",
                                                        extensionName: "Bitwarden", version: "2025.1.0")

        XCTAssertEqual(line, "stubbed chrome.notifications.create ext=Bitwarden v=2025.1.0")
    }

    func testEntryParsesTheLineItWasWrittenAs() {
        for kind in WebExtensionAPICompatibilityKind.allCases {
            let entry = WebExtensionAPICompatibilityLog.Entry(kind: kind, api: "chrome.tabs.query",
                                                              extensionName: "Bitwarden", version: "1.2.3")
            let line = WebExtensionAPICompatibilityLog.line(kind: kind, api: entry.api,
                                                            extensionName: entry.extensionName, version: entry.version)

            XCTAssertEqual(WebExtensionAPICompatibilityLog.Entry(line: line), entry)
        }
    }

    func testEntryParsesANameWithSpacesAndMarkers() {
        let line = WebExtensionAPICompatibilityLog.line(kind: .missing, api: "permission:idle",
                                                        extensionName: "My ext=Manager v=2 Pro", version: "3.0")

        let entry = WebExtensionAPICompatibilityLog.Entry(line: line)

        XCTAssertEqual(entry?.extensionName, "My ext=Manager v=2 Pro")
        XCTAssertEqual(entry?.version, "3.0")
        XCTAssertEqual(entry?.api, "permission:idle")
    }

    func testEntryRejectsLinesThatAreNotLogLines() {
        let lines = ["", "hello", "stubbed", "unknown chrome.a ext=X v=1", "stubbed chrome.a v=1 ext=X",
                     "stubbed chrome.a extra ext=X v=1", "stubbed ext=X v=1"]
        for line in lines {
            XCTAssertNil(WebExtensionAPICompatibilityLog.Entry(line: line), line)
        }
    }

    // MARK: - Fields

    func testSanitizedFieldKeepsOneLineOfBoundedLength() {
        XCTAssertEqual(WebExtensionAPICompatibilityLog.sanitizedField("Bit\nwarden\t"), "Bit warden")
        XCTAssertEqual(WebExtensionAPICompatibilityLog.sanitizedField(nil), "unknown")
        XCTAssertEqual(WebExtensionAPICompatibilityLog.sanitizedField("  "), "unknown")
        XCTAssertEqual(WebExtensionAPICompatibilityLog.sanitizedField(String(repeating: "a", count: 200)).count, 80)
    }

    // MARK: - Reporter

    func testReporterWritesTheFirstOccurrenceOfAnIssueOnly() {
        var lines: [String] = []
        let reporter = WebExtensionAPICompatibilityReporter { lines.append($0) }

        reporter.report(kind: .stubbed, api: "chrome.a.b", extensionName: "One", version: "1")
        reporter.report(kind: .stubbed, api: "chrome.a.b", extensionName: "One", version: "1")
        reporter.report(kind: .missing, api: "chrome.a.b", extensionName: "One", version: "1")
        reporter.report(kind: .stubbed, api: "chrome.a.b", extensionName: "Two", version: "1")
        reporter.report(kind: .stubbed, api: "chrome.a.b", extensionName: "One", version: "2")

        XCTAssertEqual(lines, ["stubbed chrome.a.b ext=One v=1",
                               "missing chrome.a.b ext=One v=1",
                               "stubbed chrome.a.b ext=Two v=1",
                               "stubbed chrome.a.b ext=One v=2"])
    }
}
