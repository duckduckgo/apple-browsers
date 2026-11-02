//
//  ImportPasswordSourceTests.swift
//  DuckDuckGoTests
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
@testable import DuckDuckGo

final class ImportPasswordSourceTests: XCTestCase {

    func testWhenReadingAllCasesThenIdentifiersAreUnique() {
        let allCases = ImportPasswordSource.allCases
        let uniqueIDs = Set(allCases.map(\.id))

        XCTAssertEqual(allCases.count, 4)
        XCTAssertEqual(uniqueIDs.count, allCases.count)
    }

    func testWhenSectionIsImportFromThenSourcesMatchExpectedOrder() {
        XCTAssertEqual(
            ImportPasswordSource.Section.importFrom.sources,
            [.safari, .chrome, .passwordsApp]
        )
    }

    func testWhenSectionIsSyncFromThenOnlySyncSourceIsAvailable() {
        XCTAssertEqual(
            ImportPasswordSource.Section.syncFrom.sources,
            [.syncFromDuckDuckGo]
        )
    }

    func testWhenSourceIsSafariThenUploadActionsAreAvailable() {
        let safariSource = ImportPasswordSource.safari

        XCTAssertNotNil(safariSource.primaryButtonTitle)
        XCTAssertNotNil(safariSource.bottomSection)
    }

    func testWhenSourceIsNotSafariThenUploadActionsAreUnavailable() {
        let nonSafariSources: [ImportPasswordSource] = [.passwordsApp, .chrome, .syncFromDuckDuckGo]

        for source in nonSafariSources {
            XCTAssertNil(source.primaryButtonTitle)
            XCTAssertNil(source.bottomSection)
        }
    }

    func testWhenSourceIsSyncFromDuckDuckGoThenDetailScreenIsDisabled() {
        XCTAssertFalse(ImportPasswordSource.syncFromDuckDuckGo.hasDetailScreen)
        XCTAssertEqual(ImportPasswordSource.syncFromDuckDuckGo.detailTitle, ImportPasswordSource.syncFromDuckDuckGo.title)
    }

    func testWhenSourceRequiresStepByStepInstructionsThenStepCountMatchesConfiguration() {
        XCTAssertEqual(ImportPasswordSource.passwordsApp.steps.count, 3)
        XCTAssertEqual(ImportPasswordSource.chrome.steps.count, 3)
        XCTAssertTrue(ImportPasswordSource.safari.steps.isEmpty)
        XCTAssertTrue(ImportPasswordSource.syncFromDuckDuckGo.steps.isEmpty)
    }
}
