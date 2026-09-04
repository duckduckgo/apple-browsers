//
//  AutofillLoginDetailsViewModelTests.swift
//  DuckDuckGo
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

import BrowserServicesKit
import Common
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import DuckDuckGo

@MainActor
final class AutofillLoginDetailsViewModelTests: XCTestCase {

    func testCopiedPasswordExpiresAfterSixtySeconds() throws {
        let pasteboard = RecordingPasteboard()
        let model = makeModel(pasteboard: pasteboard)
        model.password = "test-password"
        let beforeCopy = Date()

        model.copyToPasteboard(.password)

        let afterCopy = Date()
        XCTAssertEqual(pasteboard.copiedItems.first?[UTType.utf8PlainText.identifier] as? String, "test-password")
        let expiration = try XCTUnwrap(pasteboard.options[.expirationDate] as? Date)
        XCTAssertGreaterThanOrEqual(expiration, beforeCopy.addingTimeInterval(60))
        XCTAssertLessThanOrEqual(expiration, afterCopy.addingTimeInterval(60))
    }

    func testOtherFieldsAreCopiedWithoutExpiration() {
        let pasteboard = RecordingPasteboard()
        let model = makeModel(pasteboard: pasteboard)
        model.username = "test-user"
        model.address = "https://example.com"
        model.notes = "test-note"

        model.copyToPasteboard(.username)
        XCTAssertEqual(pasteboard.string, model.username)
        model.copyToPasteboard(.address)
        XCTAssertEqual(pasteboard.string, model.address)
        model.copyToPasteboard(.notes)
        XCTAssertEqual(pasteboard.string, model.notes)
        XCTAssertTrue(pasteboard.copiedItems.isEmpty)
        XCTAssertTrue(pasteboard.options.isEmpty)
    }

    private func makeModel(pasteboard: UIPasteboard) -> AutofillLoginDetailsViewModel {
        AutofillLoginDetailsViewModel(
            syncService: MockDDGSyncing(authState: .inactive, scheduler: CapturingScheduler(), isSyncInProgress: false),
            tld: TLD(),
            pasteboard: pasteboard)
    }
}

private final class RecordingPasteboard: UIPasteboard, @unchecked Sendable {
    var copiedItems: [[String: Any]] = []
    var options: [UIPasteboard.OptionsKey: Any] = [:]
    private var copiedString: String?

    override var string: String? {
        get { copiedString }
        set { copiedString = newValue }
    }

    override func setItems(_ items: [[String: Any]], options: [UIPasteboard.OptionsKey: Any] = [:]) {
        copiedItems = items
        self.options = options
    }
}
