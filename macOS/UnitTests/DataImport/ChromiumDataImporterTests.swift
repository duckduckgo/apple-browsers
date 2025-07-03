//
//  ChromiumDataImporterTests.swift
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

import Testing
@testable import DuckDuckGo_Privacy_Browser
@testable import BrowserServicesKit

class ChromiumDataImporterTests {

    @Test func testWhenImportingBookmarks_AndBookmarkImportSucceeds_ThenSummaryIsPopulated() async throws {
        let loginImporter = MockLoginImporter()
        let faviconManager = FaviconManagerMock()
        let bookmarkImporter = MockBookmarkImporter(importBookmarks: { _, _, _ in .init(successful: 1, duplicates: 2, failed: 3) })
        let importer = ChromiumDataImporter(profile: .init(browser: .chrome, profileURL: resourceURL()), loginImporter: loginImporter, bookmarkImporter: bookmarkImporter, faviconManager: faviconManager)

        let result = await importer.importData(types: [.bookmarks])

        #expect(result[.passwords] == nil)
        let bookmarks = try #require(result[.bookmarks]).get()
        #expect(bookmarks.successful == 1)
        #expect(bookmarks.duplicate == 2)
        #expect(bookmarks.failed == 3)
    }

    private func resourceURL() -> URL {
        let bundle = Bundle(for: ChromiumDataImporterTests.self)
        return bundle.resourceURL!.appendingPathComponent("DataImportResources/TestChromeData")
    }

}

extension ChromiumDataImporter {
    func importData(types: Set<DataImport.DataType>) async -> DataImportSummary {
        return await importData(types: types).task.value
    }
}
