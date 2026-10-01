//
//  WebExtensionAPICompatibilityLogViewModelTests.swift
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

import WebExtensions
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@available(macOS 15.4, *)
@MainActor
final class WebExtensionAPICompatibilityLogViewModelTests: XCTestCase {

    private func row(_ id: Int, name: String, version: String, api: String = "chrome.foo") -> WebExtensionAPICompatibilityLogViewModel.Row {
        let entry = WebExtensionAPICompatibilityLog.Entry(line: "missing \(api) ext=\(name) v=\(version)")!
        return .init(id: id, date: Date(), entry: entry)
    }

    private func makeViewModel() -> WebExtensionAPICompatibilityLogViewModel {
        WebExtensionAPICompatibilityLogViewModel(rows: [
            row(0, name: "Bitwarden", version: "1.0"),
            row(1, name: "Other Ext", version: "2.0"),
            row(2, name: "Bitwarden", version: "1.0", api: "chrome.bar"),
        ])
    }

    func testThatNoSelectionShowsAllRows() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.filteredRows.map(\.id), [0, 1, 2])
    }

    func testThatSelectionLimitsRowsToThatExtension() {
        let viewModel = makeViewModel()
        viewModel.selectedExtension = "Bitwarden v1.0"

        XCTAssertEqual(viewModel.filteredRows.map(\.id), [0, 2])
    }

    func testThatExtensionLabelsListEachExtensionOnce() {
        XCTAssertEqual(makeViewModel().extensionLabels, ["Bitwarden v1.0", "Other Ext v2.0"])
    }

    func testThatSelectedExtensionWithoutEntriesStaysInLabelsAndShowsNoRows() {
        let viewModel = makeViewModel()
        viewModel.selectedExtension = "Quiet v3.0"

        XCTAssertTrue(viewModel.extensionLabels.contains("Quiet v3.0"))
        XCTAssertTrue(viewModel.filteredRows.isEmpty)
    }

    func testThatDifferentVersionsOfAnExtensionAreSeparateLabels() {
        let viewModel = WebExtensionAPICompatibilityLogViewModel(rows: [
            row(0, name: "Bitwarden", version: "1.0"),
            row(1, name: "Bitwarden", version: "2.0"),
        ])

        XCTAssertEqual(viewModel.extensionLabels, ["Bitwarden v1.0", "Bitwarden v2.0"])
    }
}
