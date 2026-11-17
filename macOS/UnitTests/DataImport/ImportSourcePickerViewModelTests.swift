//
//  ImportSourcePickerViewModelTests.swift
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
import BrowserServicesKit
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class ImportSourcePickerViewModelTests: XCTestCase {
    func testUpdateAvailableImportSources_replacesGridAndExpandsToKeepSelectedSourceVisible() {
        let viewModel = pickerViewModel(availableSources: [.chrome, .bitwarden], selectedSource: .bitwarden)
        let newSources: [DataImport.Source] = [.chrome, .chromium, .edge, .firefox, .bitwarden]

        viewModel.updateAvailableImportSources(newSources)

        XCTAssertTrue(viewModel.isPickerExpanded)
        XCTAssertEqual(viewModel.visibleOptions, newSources)
    }

    func testUpdateAvailableImportSources_collapsedPicker_showsFirstFourOfNewSources() {
        let viewModel = pickerViewModel(availableSources: [.chrome, .bitwarden], selectedSource: .chrome)

        viewModel.updateAvailableImportSources([.chrome, .chromium, .edge, .firefox, .bitwarden])

        XCTAssertFalse(viewModel.isPickerExpanded)
        XCTAssertEqual(viewModel.visibleOptions, [.chrome, .chromium, .edge, .firefox])
        XCTAssertTrue(viewModel.shouldShowExpandButton)
    }

    func testUpdateSelectedSource_sourceFilterEnabled_showsItForPasswordManager() {
        let viewModel = pickerViewModel(availableSources: [.chrome, .bitwarden], selectedSource: .chrome, isSourceFilterEnabled: true)

        viewModel.updateSelectedSource(.bitwarden)

        XCTAssertEqual(viewModel.selectedSource, .bitwarden)
        XCTAssertTrue(viewModel.shouldShowTypeSelector)
    }

    func testInit_allTypesWithHistory_listsHistoryLastAndNamesItInTheTypeButton() {
        let selectedTypes: [DataImport.DataType] = [.history, .passwords, .bookmarks]

        let viewModel = pickerViewModel(selectedImportTypes: selectedTypes)

        XCTAssertEqual(viewModel.typeButtonTitle, UserText.importTypeSelectionTitleAllWithHistory)
        XCTAssertEqual(viewModel.importTypeItems.map(\.dataType), [.bookmarks, .passwords, .history])
    }

    func testTypeSelectionDone_bookmarksAndHistory_namesBothInTheTypeButton() {
        let viewModel = pickerViewModel(selectedImportTypes: [.history, .passwords, .bookmarks])
        viewModel.importTypeItems[1].isSelected = false

        viewModel.typeSelectionDone()

        XCTAssertEqual(viewModel.typeButtonTitle, UserText.importTypeSelectionTitleBookmarksAndHistory)
    }

    private func pickerViewModel(
        availableSources: [DataImport.Source] = [.chrome],
        selectedSource: DataImport.Source = .chrome,
        selectedImportTypes: [DataImport.DataType] = [.bookmarks, .passwords],
        isSourceFilterEnabled: Bool = false
    ) -> ImportSourcePickerViewModel {
        ImportSourcePickerViewModel(
            availableSources: availableSources,
            selectedSource: selectedSource,
            selectedImportTypes: selectedImportTypes,
            selectableImportTypes: selectedImportTypes,
            shouldShowSyncButton: false,
            isSourceFilterEnabled: isSourceFilterEnabled,
            onSourceSelected: { _ in },
            onTypesSelected: { _ in },
            onSyncSelected: {}
        )
    }
}
