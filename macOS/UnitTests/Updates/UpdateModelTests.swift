//
//  UpdateModelTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import DuckDuckGo_Privacy_Browser

final class UpdateModelTests: XCTestCase {

    // MARK: - ReleaseMetadata Initialization Tests

    func testUpdate_InitFromReleaseMetadata_RegularUpdate() {
        // Given
        let releaseMetadata = ReleaseMetadata(
            latestVersion: "1.0.1",
            buildNumber: 101,
            releaseDate: "2025-01-01T00:00:00Z",
            isCritical: false
        )

        // When
        let update = Update(releaseMetadata: releaseMetadata, isInstalled: false)

        // Then
        XCTAssertEqual(update.version, "1.0.1")
        XCTAssertEqual(update.build, "101")
        XCTAssertEqual(update.type, Update.UpdateType.regular)
        XCTAssertFalse(update.isInstalled)
        XCTAssertEqual(update.releaseNotes, []) // App Store doesn't provide detailed release notes
        XCTAssertEqual(update.releaseNotesSubscription, [])
        XCTAssertFalse(update.needsLatestReleaseNote)
    }

    func testUpdate_InitFromReleaseMetadata_CriticalUpdate() {
        // Given
        let releaseMetadata = ReleaseMetadata(
            latestVersion: "1.0.2",
            buildNumber: 102,
            releaseDate: "2025-01-02T00:00:00Z",
            isCritical: true
        )

        // When
        let update = Update(releaseMetadata: releaseMetadata, isInstalled: true)

        // Then
        XCTAssertEqual(update.version, "1.0.2")
        XCTAssertEqual(update.build, "102")
        XCTAssertEqual(update.type, Update.UpdateType.critical)
        XCTAssertTrue(update.isInstalled)
        XCTAssertEqual(update.releaseNotes, []) // App Store doesn't provide detailed release notes
        XCTAssertEqual(update.releaseNotesSubscription, [])
        XCTAssertFalse(update.needsLatestReleaseNote)
    }

    // MARK: - Update Type Classification Tests

    func testUpdateType_RegularUpdate() {
        // Given
        let update = Update(
            isInstalled: false,
            type: .regular,
            version: "1.0.1",
            build: "101",
            date: Date(),
            releaseNotes: ["Bug fixes"],
            releaseNotesSubscription: [],
            needsLatestReleaseNote: false
        )

        // Then
        XCTAssertEqual(update.type, Update.UpdateType.regular)
    }

    func testUpdateType_CriticalUpdate() {
        // Given
        let update = Update(
            isInstalled: false,
            type: .critical,
            version: "1.0.1",
            build: "101",
            date: Date(),
            releaseNotes: ["Critical security fix"],
            releaseNotesSubscription: [],
            needsLatestReleaseNote: false
        )

        // Then
        XCTAssertEqual(update.type, Update.UpdateType.critical)
    }

    // MARK: - Title Formatting Tests

    func testTitle_FormatsDateCorrectlyForEnglishUS() {
        // Given
        let calendar = Calendar(identifier: .gregorian)
        let components = DateComponents(year: 2022, month: 1, day: 15)
        let specificDate = calendar.date(from: components) ?? Date()

        let formatter = Update.releaseDateFormatter()
        formatter.locale = Locale(identifier: "en_US")

        let update = Update(
            isInstalled: false,
            type: Update.UpdateType.regular,
            version: "1.0.1",
            build: "101",
            date: specificDate,
            releaseNotes: ["Bug fixes"],
            releaseNotesSubscription: [],
            needsLatestReleaseNote: false,
            dateFormatterProvider: formatter
        )

        // When
        let title = update.title

        // Then
        XCTAssertEqual(title, "January 15, 2022")
    }

    // MARK: - Edge Cases

    func testUpdate_WithEmptyReleaseNotes() {
        // Given
        let releaseMetadata = ReleaseMetadata(
            latestVersion: "1.0.0",
            buildNumber: 100,
            releaseDate: "2025-01-01T00:00:00Z",
            isCritical: false
        )

        // When
        let update = Update(releaseMetadata: releaseMetadata, isInstalled: false)

        // Then
        XCTAssertEqual(update.releaseNotes, [])
        XCTAssertEqual(update.releaseNotesSubscription, [])
        XCTAssertEqual(update.type, Update.UpdateType.regular)
    }

    func testUpdate_WithLargeVersionNumber() {
        // Given
        let releaseMetadata = ReleaseMetadata(
            latestVersion: "999.999.999",
            buildNumber: 999999,
            releaseDate: "2025-12-31T23:59:59Z",
            isCritical: false
        )

        // When
        let update = Update(releaseMetadata: releaseMetadata, isInstalled: false)

        // Then
        XCTAssertEqual(update.version, "999.999.999")
        XCTAssertEqual(update.build, "999999")
    }

    // MARK: - Equality and Comparison Tests

    func testUpdate_PropertiesMatchReleaseMetadata() {
        // Given
        let releaseMetadata = ReleaseMetadata(
            latestVersion: "2.5.0",
            buildNumber: 250,
            releaseDate: "2025-06-15T12:00:00Z",
            isCritical: true
        )

        // When
        let update = Update(releaseMetadata: releaseMetadata, isInstalled: true)

        // Then
        XCTAssertEqual(update.version, releaseMetadata.latestVersion)
        XCTAssertEqual(update.build, String(releaseMetadata.buildNumber))
        XCTAssertEqual(update.releaseNotes, []) // App Store doesn't provide detailed release notes via API
        XCTAssertEqual(update.releaseNotesSubscription, [])
        XCTAssertEqual(update.type, releaseMetadata.isCritical ? Update.UpdateType.critical : Update.UpdateType.regular)
    }
}
