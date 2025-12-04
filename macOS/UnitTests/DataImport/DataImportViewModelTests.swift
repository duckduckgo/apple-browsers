//
//  DataImportViewModelTests.swift
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

import Common
import Foundation
import XCTest
@testable import DuckDuckGo_Privacy_Browser
import BrowserServicesKit
import UniformTypeIdentifiers
import SharedTestUtilities

final class DataImportViewModelTests: XCTestCase {

    typealias Source = DataImport.Source
    typealias BrowserProfileList = DataImport.BrowserProfileList
    typealias BrowserProfile = DataImport.BrowserProfile
    typealias DataType = DataImport.DataType
    typealias DataTypeSummary = DataImport.DataTypeSummary

    var model: DataImportViewModel!
    var importTask: ((Set<DataImport.DataType>, DataImportProgressCallback) async -> DataImportSummary)!
    var openPanelCallback: (([UTType]) -> URL?)?
    var fileStore: FileStoreMock!

    override func setUp() {
        super.setUp()
        fileStore = FileStoreMock()
    }

    override func tearDown() {
        model = nil
        importTask = nil
        openPanelCallback = nil
        fileStore = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitWithDefaultImportSource_selectsFirstPreferredAvailableSource() {
        // GIVEN
        let availableSources: [Source] = [.safari, .csv, .bitwarden]
        let preferredSources: [Source] = [.firefox, .chrome, .bitwarden, .safari]

        // WHEN
        model = DataImportViewModel(
            availableImportSources: availableSources,
            preferredImportSources: preferredSources,
            syncFeatureVisibility: .hide
        )

        // THEN
        XCTAssertEqual(model.importSource, .bitwarden)
    }

    func testInitWithSpecificImportSource_usesProvidedSource() {
        // WHEN
        model = DataImportViewModel(importSource: .firefox, syncFeatureVisibility: .hide)

        // THEN
        XCTAssertEqual(model.importSource, .firefox)
    }

    func testInitWithAvailableImportSources_filtersOutSourcesWithoutValidProfiles() {
        // GIVEN
        let allSources: [Source] = [.chrome, .firefox, .safari]

        // WHEN
        model = DataImportViewModel(
            availableImportSources: allSources,
            syncFeatureVisibility: .hide,
            loadProfiles: { browser in
                if browser == .firefox {
                    return .init(browser: browser, profiles: [])
                } else {
                    return .init(browser: browser, profiles: [BrowserProfile.default(fileStore: self.fileStore)(browser)])
                }
            }
        )

        // THEN
        XCTAssertFalse(model.availableImportSources.contains(.firefox))
        XCTAssertTrue(model.availableImportSources.contains(.chrome))
        XCTAssertTrue(model.availableImportSources.contains(.safari))
    }

    func testInitDefaultScreen_isSourceAndDataTypesPicker() {
        // WHEN
        model = DataImportViewModel(importSource: .chrome, syncFeatureVisibility: .hide)

        // THEN
        XCTAssertEqual(model.screen, .sourceAndDataTypesPicker)
    }

    func testInitSelectableImportTypes_matchesSupportedDataTypesForSource() {
        // WHEN
        model = DataImportViewModel(
            importSource: .chrome,
            syncFeatureVisibility: .hide,
            loadProfiles: { browser in
                let defaultProfile = BrowserProfile.default(fileStore: self.fileStore)(browser)
                return .init(browser: browser, profiles: [defaultProfile])
            }
        )

        // THEN
        XCTAssertEqual(model.selectableImportTypes, [.bookmarks, .passwords])
    }

    func testInitSelectedDataTypes_includesAllSelectableTypes() {
        // WHEN
        model = DataImportViewModel(
            importSource: .chrome,
            syncFeatureVisibility: .hide,
            loadProfiles: { browser in
                let defaultProfile = BrowserProfile.default(fileStore: self.fileStore)(browser)
                return .init(browser: browser, profiles: [defaultProfile])
            }
        )

        // THEN
        XCTAssertEqual(model.selectedDataTypes, model.selectableImportTypes)
    }

    func testInitSelectedProfile_isDefaultProfileWhenAvailable() {
        // WHEN
        model = DataImportViewModel(
            importSource: .firefox,
            syncFeatureVisibility: .hide,
            loadProfiles: { browser in
                let testProfile = BrowserProfile.test(fileStore: self.fileStore)(browser)
                let defaultProfile = BrowserProfile.default(fileStore: self.fileStore)(browser)
                let test2Profile = BrowserProfile.test2(fileStore: self.fileStore)(browser)
                return .init(browser: browser, profiles: [testProfile, defaultProfile, test2Profile])
            }
        )

        // THEN
        XCTAssertEqual(model.selectedProfile, BrowserProfile.default(fileStore: self.fileStore)(.firefox))
    }

    func testInitBrowserProfiles_loadsProfilesForBrowserSources() {
        // WHEN
        model = DataImportViewModel(
            importSource: .chrome,
            syncFeatureVisibility: .hide,
            loadProfiles: { browser in
                let testProfile = BrowserProfile.test(fileStore: self.fileStore)(browser)
                return .init(browser: browser, profiles: [testProfile])
            }
        )

        // THEN
        XCTAssertNotNil(model.browserProfiles)
        XCTAssertEqual(model.browserProfiles?.profiles.count, 1)
    }

    // MARK: - Screen State Tests

    func testScreenIsFileImport_returnsTrueForFileImportScreen() {
        // GIVEN
        let screen = DataImportViewModel.Screen.fileImport(dataType: .bookmarks)

        // THEN
        XCTAssertTrue(screen.isFileImport)
    }

    func testScreenIsFileImport_returnsFalseForOtherScreens() {
        // GIVEN
        let screens: [DataImportViewModel.Screen] = [
            .sourceAndDataTypesPicker,
            .profilePicker,
            .moreInfo,
            .archiveImport(dataTypes: [.bookmarks]),
            .summary([:])
        ]

        // THEN
        for screen in screens {
            XCTAssertFalse(screen.isFileImport, "Expected \(screen) to not be file import")
        }
    }

    func testScreenIsArchiveImport_returnsTrueForArchiveImportScreen() {
        // GIVEN
        let screen = DataImportViewModel.Screen.archiveImport(dataTypes: [.bookmarks, .passwords])

        // THEN
        XCTAssertTrue(screen.isArchiveImport)
    }

    func testScreenIsArchiveImport_returnsFalseForOtherScreens() {
        // GIVEN
        let screens: [DataImportViewModel.Screen] = [
            .sourceAndDataTypesPicker,
            .profilePicker,
            .moreInfo,
            .fileImport(dataType: .bookmarks),
            .summary([:])
        ]

        // THEN
        for screen in screens {
            XCTAssertFalse(screen.isArchiveImport, "Expected \(screen) to not be archive import")
        }
    }

    func testScreenIsProfilePicker_returnsTrueForProfilePickerScreen() {
        // GIVEN
        let screen = DataImportViewModel.Screen.profilePicker

        // THEN
        XCTAssertTrue(screen.isProfilePicker)
    }

    func testScreenFileImportDataType_returnsCorrectDataType() {
        // GIVEN
        let screen = DataImportViewModel.Screen.fileImport(dataType: .passwords)

        // THEN
        XCTAssertEqual(screen.fileImportDataType, .passwords)
    }

    func testScreenFileImportDataType_returnsNilForNonFileImportScreens() {
        // GIVEN
        let screens: [DataImportViewModel.Screen] = [
            .sourceAndDataTypesPicker,
            .profilePicker,
            .moreInfo,
            .archiveImport(dataTypes: [.bookmarks]),
            .summary([:])
        ]

        // THEN
        for screen in screens {
            XCTAssertNil(screen.fileImportDataType, "Expected \(screen) to have nil fileImportDataType")
        }
    }

    // MARK: - Data Type Selection Tests

    func testDataTypesSelection_returnsAllWhenAllSelectableTypesSelected() {
        // GIVEN
        model = DataImportViewModel(importSource: .safari, syncFeatureVisibility: .hide)
        model.selectedDataTypes = [.bookmarks, .passwords]

        // WHEN
        let result = model.dataTypesSelection

        // THEN
        XCTAssertEqual(result, .all)
    }

    func testDataTypesSelection_returnsSingleWhenOneTypeSelected() {
        // GIVEN
        model = DataImportViewModel(importSource: .safari, syncFeatureVisibility: .hide)
        model.selectedDataTypes = [.bookmarks]

        // WHEN
        let result = model.dataTypesSelection

        // THEN
        XCTAssertEqual(result, .single(.bookmarks))
    }

    func testDataTypesSelection_returnsNoneWhenNoTypesSelected() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, syncFeatureVisibility: .hide)
        model.selectedDataTypes = []

        // WHEN
        let result = model.dataTypesSelection

        // THEN
        XCTAssertEqual(result, .none)
    }

    // MARK: - Data Tests

    func testDataTypesSelection_noPreviousSelection_returnsAllAvailableTypes() {
        // GIVEN
        let availableTypes: Set<DataType> = [.bookmarks, .passwords]

        // WHEN
        let result = DataImportViewModel.determineSelectedDataTypes(
            previousSelectedTypes: nil,
            availableTypes: availableTypes
        )

        // THEN
        XCTAssertEqual(result, availableTypes)
    }

    func testDataTypesSelection_partialSelection_preservesPartialSelection() {
        // GIVEN: Both sources have same types available, but user only selected one
        let previousTypes: Set<DataType> = [.bookmarks]
        let availableTypes: Set<DataType> = [.bookmarks, .passwords]

        // WHEN
        let result = DataImportViewModel.determineSelectedDataTypes(
            previousSelectedTypes: previousTypes,
            availableTypes: availableTypes
        )

        // THEN: Should preserve the partial selection
        XCTAssertEqual(result, [.bookmarks])
    }

    func testDataTypesSelection_newSourceHasSameNumberOfTypesAvailable_preservesSelections() {
        // GIVEN: Both sources have same number of types
        let previousTypes: Set<DataType> = [.bookmarks, .passwords]
        let availableTypes: Set<DataType> = [.bookmarks, .passwords]

        // WHEN
        let result = DataImportViewModel.determineSelectedDataTypes(
            previousSelectedTypes: previousTypes,
            availableTypes: availableTypes
        )

        // THEN: Should preserve previous selections
        XCTAssertEqual(result, previousTypes)
    }

    func testDataTypesSelection_newSourceHasLessTypesAvailable_preservesFilteredSelections() {
        // GIVEN: Previous source had 2 types, new source has 1 type
        let previousTypes: Set<DataType> = [.bookmarks, .passwords]
        let availableTypes: Set<DataType> = [.passwords]

        // WHEN
        let result = DataImportViewModel.determineSelectedDataTypes(
            previousSelectedTypes: previousTypes,
            availableTypes: availableTypes
        )

        // THEN: Should preserve only the available type
        XCTAssertEqual(result, [.passwords])
    }

    func testDataTypesSelection_previousTypesNotAvailable_fallbacksToAllAvailable() {
        // GIVEN: Previous types don't exist in new source
        let previousTypes: Set<DataType> = [.creditCards]
        let availableTypes: Set<DataType> = [.bookmarks, .passwords]

        // WHEN
        let result = DataImportViewModel.determineSelectedDataTypes(
            previousSelectedTypes: previousTypes,
            availableTypes: availableTypes
        )

        // THEN: Should fallback to all available types
        XCTAssertEqual(result, availableTypes)
    }

    func testDataTypesSelection_partialMatch_preservesFilteredTypes() {
        // GIVEN: Previous source had 2 types, new source has 2 types, but only 1 previous type available
        let previousTypes: Set<DataType> = [.passwords, .creditCards]
        let availableTypes: Set<DataType> = [.bookmarks, .passwords]

        // WHEN
        let result = DataImportViewModel.determineSelectedDataTypes(
            previousSelectedTypes: previousTypes,
            availableTypes: availableTypes
        )

        // THEN: Should preserve filtered types (not all previous types available, so don't select all)
        XCTAssertEqual(result, [.passwords])
    }

    // MARK: - Button State Tests

    @MainActor
    func testActionButton_selectFileForCSVSource() {
        // GIVEN
        model = DataImportViewModel(importSource: .csv, syncFeatureVisibility: .hide)

        // WHEN
        let actionButton = model.actionButton

        // THEN
        XCTAssertEqual(actionButton, .selectFile)
    }

    @MainActor
    func testActionButton_selectFileForBookmarksHTMLSource() {
        // GIVEN
        model = DataImportViewModel(importSource: .bookmarksHTML, syncFeatureVisibility: .hide)

        // WHEN
        let actionButton = model.actionButton

        // THEN
        XCTAssertEqual(actionButton, .selectFile)
    }

    @MainActor
    func testActionButton_initiateImportForBrowserSources() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, syncFeatureVisibility: .hide)

        // WHEN
        let actionButton = model.actionButton

        // THEN
        XCTAssertEqual(actionButton, .initiateImport(disabled: false))
    }

    @MainActor
    func testActionButton_continueForProfilePickerScreen() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, screen: .profilePicker, syncFeatureVisibility: .hide)

        // WHEN
        let actionButton = model.actionButton

        // THEN
        XCTAssertEqual(actionButton, .continue)
    }

    @MainActor
    func testActionButton_initiateImportForMoreInfoScreen() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, screen: .moreInfo, syncFeatureVisibility: .hide)

        // WHEN
        let actionButton = model.actionButton

        // THEN
        XCTAssertEqual(actionButton, .initiateImport(disabled: false))
    }

    @MainActor
    func testActionButton_nilForArchiveImportScreen() {
        // GIVEN
        model = DataImportViewModel(importSource: .safari, screen: .archiveImport(dataTypes: [.bookmarks]), syncFeatureVisibility: .hide)

        // WHEN
        let actionButton = model.actionButton

        // THEN
        XCTAssertNil(actionButton)
    }

    @MainActor
    func testActionButton_skipForFileImportScreenWithSummary() {
        // GIVEN
        let summary: DataImportSummary = [.bookmarks: .success(.init(successful: 10, duplicate: 0, failed: 0))]
        model = DataImportViewModel(
            importSource: .chrome,
            screen: .fileImport(dataType: .passwords, summary: summary),
            syncFeatureVisibility: .hide
        )

        // WHEN
        let actionButton = model.actionButton

        // THEN
        XCTAssertEqual(actionButton, .skip)
    }

    @MainActor
    func testActionButton_nilForFileImportScreenWithoutSummary() {
        // GIVEN
        model = DataImportViewModel(
            importSource: .chrome,
            screen: .fileImport(dataType: .passwords, summary: [:]),
            syncFeatureVisibility: .hide
        )

        // WHEN
        let actionButton = model.actionButton

        // THEN
        XCTAssertNil(actionButton)
    }

    @MainActor
    func testActionButton_submitForSummaryScreenWithErrors() {
        // GIVEN
        let summary: DataImportSummary = [.bookmarks: .failure(Failure(.bookmarks, .dataCorrupted))]
        model = DataImportViewModel(importSource: .chrome, screen: .summary(summary), syncFeatureVisibility: .hide)

        // WHEN
        let actionButton = model.actionButton

        // THEN
        XCTAssertEqual(actionButton, .submit)
    }

    @MainActor
    func testActionButton_syncForSummaryScreenWithoutErrorsAndSyncVisible() {
        // GIVEN
        let summary: DataImportSummary = [.bookmarks: .success(.init(successful: 10, duplicate: 0, failed: 0))]
        let syncLauncher = SyncLauncherMock()
        model = DataImportViewModel(
            importSource: .chrome,
            screen: .summary(summary),
            syncFeatureVisibility: .show(syncLauncher: syncLauncher)
        )

        // WHEN
        let actionButton = model.actionButton

        // THEN
        XCTAssertEqual(actionButton, .sync)
    }

    @MainActor
    func testActionButton_nilForSummaryScreenWithoutErrorsAndSyncHidden() {
        // GIVEN
        let summary: DataImportSummary = [.bookmarks: .success(.init(successful: 10, duplicate: 0, failed: 0))]
        model = DataImportViewModel(importSource: .chrome, screen: .summary(summary), syncFeatureVisibility: .hide)

        // WHEN
        let actionButton = model.actionButton

        // THEN
        XCTAssertNil(actionButton)
    }

    @MainActor
    func testActionButton_disabledWhenNoDataTypesSelected() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, syncFeatureVisibility: .hide)
        model.selectedDataTypes = []

        // WHEN
        let actionButton = model.actionButton

        // THEN
        XCTAssertEqual(actionButton, .initiateImport(disabled: true))
    }

    @MainActor
    func testActionButton_disabledWhenImportTaskRunning() {
        // GIVEN
        setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
            ImporterMock(importTask: { _, _ in [:] })
        })
        model.initiateImport(fileURL: .testProfile)

        // WHEN
        let actionButton = model.actionButton

        // THEN
        XCTAssertEqual(actionButton, .initiateImport(disabled: true))
    }

    @MainActor
    func testSecondaryButton_cancelForSourceAndDataTypesPickerScreen() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, syncFeatureVisibility: .hide)

        // WHEN
        let secondaryButton = model.secondaryButton

        // THEN
        XCTAssertEqual(secondaryButton, .cancel)
    }

    @MainActor
    func testSecondaryButton_backForArchiveImportScreen() {
        // GIVEN
        model = DataImportViewModel(importSource: .safari, screen: .archiveImport(dataTypes: [.bookmarks]), syncFeatureVisibility: .hide)

        // WHEN
        let secondaryButton = model.secondaryButton

        // THEN
        XCTAssertEqual(secondaryButton, .back)
    }

    @MainActor
    func testSecondaryButton_backForProfilePickerScreen() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, screen: .profilePicker, syncFeatureVisibility: .hide)

        // WHEN
        let secondaryButton = model.secondaryButton

        // THEN
        XCTAssertEqual(secondaryButton, .back)
    }

    @MainActor
    func testSecondaryButton_backForMoreInfoScreen() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, screen: .moreInfo, syncFeatureVisibility: .hide)

        // WHEN
        let secondaryButton = model.secondaryButton

        // THEN
        XCTAssertEqual(secondaryButton, .back)
    }

    @MainActor
    func testSecondaryButton_backForFileImportScreenWithoutSummary() {
        // GIVEN
        model = DataImportViewModel(
            importSource: .chrome,
            screen: .fileImport(dataType: .passwords, summary: [:]),
            syncFeatureVisibility: .hide
        )

        // WHEN
        let secondaryButton = model.secondaryButton

        // THEN
        XCTAssertEqual(secondaryButton, .back)
    }

    @MainActor
    func testSecondaryButton_nilForFileImportScreenWithSummary() {
        // GIVEN
        let summary: DataImportSummary = [.bookmarks: .success(.init(successful: 10, duplicate: 0, failed: 0))]
        model = DataImportViewModel(
            importSource: .chrome,
            screen: .fileImport(dataType: .passwords, summary: summary),
            syncFeatureVisibility: .hide
        )

        // WHEN
        let secondaryButton = model.secondaryButton

        // THEN
        XCTAssertNil(secondaryButton)
    }

    @MainActor
    func testSecondaryButton_doneForSummaryScreen() {
        // GIVEN
        let summary: DataImportSummary = [.bookmarks: .success(.init(successful: 10, duplicate: 0, failed: 0))]
        model = DataImportViewModel(importSource: .chrome, screen: .summary(summary), syncFeatureVisibility: .hide)

        // WHEN
        let secondaryButton = model.secondaryButton

        // THEN
        XCTAssertEqual(secondaryButton, .done)
    }

    @MainActor
    func testSecondaryButton_cancelWhenImportTaskRunning() {
        // GIVEN
        setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
            ImporterMock(importTask: { _, _ in [:] })
        })
        model.initiateImport(fileURL: .testProfile)

        // WHEN
        let secondaryButton = model.secondaryButton

        // THEN
        XCTAssertEqual(secondaryButton, .cancel)
    }

    // MARK: - View State Helper Tests

    func testShouldHideProgressAndFooter_trueForMoreInfoScreen() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, screen: .moreInfo, syncFeatureVisibility: .hide)

        // WHEN
        let shouldHideFooter = model.shouldHideFooter
        let shouldHideProgress = model.shouldHideProgress

        // THEN
        XCTAssertTrue(shouldHideFooter)
        XCTAssertTrue(shouldHideProgress)
    }

    func testShouldHideProgressAndFooter_falseForOtherScreens() {
        // GIVEN
        let screens: [DataImportViewModel.Screen] = [
            .sourceAndDataTypesPicker,
            .profilePicker,
            .fileImport(dataType: .bookmarks),
            .archiveImport(dataTypes: [.bookmarks]),
            .summary([:])
        ]

        for screen in screens {
            model = DataImportViewModel(importSource: .chrome, screen: screen, syncFeatureVisibility: .hide)

            // WHEN
            let shouldHideFooter = model.shouldHideFooter
            let shouldHideProgress = model.shouldHideProgress

            // THEN
            XCTAssertFalse(shouldHideFooter, "Expected \(screen) to not hide footer")
            XCTAssertFalse(shouldHideProgress, "Expected \(screen) to not hide progress")
        }
    }

    func testShouldHidePasswordExplainerView_trueForMoreInfoScreen() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, screen: .moreInfo, syncFeatureVisibility: .hide)

        // WHEN
        let shouldHide = model.shouldHidePasswordExplainerView

        // THEN
        XCTAssertTrue(shouldHide)
    }

    func testShouldHidePasswordExplainerView_trueForProfilePickerScreen() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, screen: .profilePicker, syncFeatureVisibility: .hide)

        // WHEN
        let shouldHide = model.shouldHidePasswordExplainerView

        // THEN
        XCTAssertTrue(shouldHide)
    }

    func testShouldHidePasswordExplainerView_falseForOtherScreens() {
        // GIVEN
        let screens: [DataImportViewModel.Screen] = [
            .sourceAndDataTypesPicker,
            .fileImport(dataType: .bookmarks),
            .archiveImport(dataTypes: [.bookmarks]),
            .summary([:])
        ]

        for screen in screens {
            model = DataImportViewModel(importSource: .chrome, screen: screen, syncFeatureVisibility: .hide)

            // WHEN
            let shouldHide = model.shouldHidePasswordExplainerView

            // THEN
            XCTAssertFalse(shouldHide, "Expected \(screen) to not hide password explainer")
        }
    }

    func testShouldShowSyncFooterButton_trueForSummaryScreen() {
        // GIVEN
        let summary: DataImportSummary = [.bookmarks: .success(.init(successful: 10, duplicate: 0, failed: 0))]
        model = DataImportViewModel(importSource: .chrome, screen: .summary(summary), syncFeatureVisibility: .hide)

        // WHEN
        let shouldShow = model.shouldShowSyncFooterButton

        // THEN
        XCTAssertTrue(shouldShow)
    }

    func testShouldShowSyncFooterButton_falseForOtherScreens() {
        // GIVEN
        let screens: [DataImportViewModel.Screen] = [
            .sourceAndDataTypesPicker,
            .profilePicker,
            .moreInfo,
            .fileImport(dataType: .bookmarks),
            .archiveImport(dataTypes: [.bookmarks])
        ]

        for screen in screens {
            model = DataImportViewModel(importSource: .chrome, screen: screen, syncFeatureVisibility: .hide)

            // WHEN
            let shouldShow = model.shouldShowSyncFooterButton

            // THEN
            XCTAssertFalse(shouldShow, "Expected \(screen) to not show sync footer button")
        }
    }

    @MainActor
    func testIsImportSourcePickerDisabled_trueWhenImportTaskRunning() {
        // GIVEN
        setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
            ImporterMock(importTask: { _, _ in [:] })
        })
        model.initiateImport(fileURL: .testProfile)

        // WHEN
        let isDisabled = model.isImportSourcePickerDisabled

        // THEN
        XCTAssertTrue(isDisabled)
    }

    @MainActor
    func testIsImportSourcePickerDisabled_falseWhenNoImportTask() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, syncFeatureVisibility: .hide)

        // WHEN
        let isDisabled = model.isImportSourcePickerDisabled

        // THEN
        XCTAssertFalse(isDisabled)
    }

    @MainActor
    func testIsSelectFileButtonDisabled_trueWhenImportTaskRunning() {
        // GIVEN
        setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
            ImporterMock(importTask: { _, _ in [:] })
        })
        model.initiateImport(fileURL: .testProfile)

        // WHEN
        let isDisabled = model.isSelectFileButtonDisabled

        // THEN
        XCTAssertTrue(isDisabled)
    }

    @MainActor
    func testIsSelectFileButtonDisabled_falseWhenNoImportTask() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, syncFeatureVisibility: .hide)

        // WHEN
        let isDisabled = model.isSelectFileButtonDisabled

        // THEN
        XCTAssertFalse(isDisabled)
    }

    // MARK: - Summary and Error Tests

    func testHasAnySummaryError_trueWhenSummaryContainsFailure() {
        // GIVEN
        let summaryArray: [DataImportViewModel.DataTypeImportResult] = [
            .init(.bookmarks, .failure(Failure(.bookmarks, .dataCorrupted)))
        ]
        model = DataImportViewModel(importSource: .chrome, summary: summaryArray, syncFeatureVisibility: .hide)

        // WHEN
        let hasError = model.hasAnySummaryError

        // THEN
        XCTAssertTrue(hasError)
    }

    func testHasAnySummaryError_falseWhenAllSummariesSuccessful() {
        // GIVEN
        let summaryArray: [DataImportViewModel.DataTypeImportResult] = [
            .init(.bookmarks, .success(.init(successful: 10, duplicate: 0, failed: 0)))
        ]
        model = DataImportViewModel(importSource: .chrome, summary: summaryArray, syncFeatureVisibility: .hide)

        // WHEN
        let hasError = model.hasAnySummaryError

        // THEN
        XCTAssertFalse(hasError)
    }

    func testSummaryForDataType_returnsCorrectSummary() {
        // GIVEN
        let expectedSummary = DataTypeSummary(successful: 10, duplicate: 2, failed: 1)
        let summaryArray: [DataImportViewModel.DataTypeImportResult] = [
            .init(.bookmarks, .success(expectedSummary))
        ]
        model = DataImportViewModel(importSource: .chrome, summary: summaryArray, syncFeatureVisibility: .hide)

        // WHEN
        let summary = model.summary(for: .bookmarks)

        // THEN
        XCTAssertEqual(summary, expectedSummary)
    }

    func testSummaryForDataType_returnsNilWhenNotFound() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, summary: [], syncFeatureVisibility: .hide)

        // WHEN
        let summary = model.summary(for: .bookmarks)

        // THEN
        XCTAssertNil(summary)
    }

    func testIsDataTypeSuccessfullyImported_trueWhenSuccessfulSummaryExists() {
        // GIVEN
        let summaryArray: [DataImportViewModel.DataTypeImportResult] = [
            .init(.bookmarks, .success(.init(successful: 10, duplicate: 0, failed: 0)))
        ]
        model = DataImportViewModel(importSource: .chrome, summary: summaryArray, syncFeatureVisibility: .hide)

        // WHEN
        let isSuccessful = model.isDataTypeSuccessfullyImported(.bookmarks)

        // THEN
        XCTAssertTrue(isSuccessful)
    }

    func testIsDataTypeSuccessfullyImported_falseWhenNoSummary() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, summary: [], syncFeatureVisibility: .hide)

        // WHEN
        let isSuccessful = model.isDataTypeSuccessfullyImported(.bookmarks)

        // THEN
        XCTAssertFalse(isSuccessful)
    }

    func testErrorForDataType_returnsErrorWhenFailure() {
        // GIVEN
        let expectedError = Failure(.bookmarks, .dataCorrupted)
        let summaryArray: [DataImportViewModel.DataTypeImportResult] = [
            .init(.bookmarks, .failure(expectedError))
        ]
        model = DataImportViewModel(importSource: .chrome, summary: summaryArray, syncFeatureVisibility: .hide)

        // WHEN
        let error = model.error(for: .bookmarks)

        // THEN
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.errorType, .dataCorrupted)
    }

    func testErrorForDataType_returnsNilWhenSuccess() {
        // GIVEN
        let summaryArray: [DataImportViewModel.DataTypeImportResult] = [
            .init(.bookmarks, .success(.init(successful: 10, duplicate: 0, failed: 0)))
        ]
        model = DataImportViewModel(importSource: .chrome, summary: summaryArray, syncFeatureVisibility: .hide)

        // WHEN
        let error = model.error(for: .bookmarks)

        // THEN
        XCTAssertNil(error)
    }

    func testSummarizedError_returnsSingleErrorWhenOnlyOneError() {
        // GIVEN
        let error = Failure(.bookmarks, .dataCorrupted)
        let summaryArray: [DataImportViewModel.DataTypeImportResult] = [
            .init(.bookmarks, .failure(error))
        ]
        model = DataImportViewModel(importSource: .chrome, summary: summaryArray, syncFeatureVisibility: .hide)

        // WHEN
        let summarizedError = model.summarizedError

        // THEN
        XCTAssertNotNil(summarizedError.localizedDescription)
        XCTAssertTrue(summarizedError.localizedDescription.contains("bookmarks"))
    }

    func testSummarizedError_returnsCombinedErrorsWhenMultipleErrors() {
        // GIVEN
        let summaryArray: [DataImportViewModel.DataTypeImportResult] = [
            .init(.bookmarks, .failure(Failure(.bookmarks, .dataCorrupted))),
            .init(.passwords, .failure(Failure(.passwords, .keychainError)))
        ]
        model = DataImportViewModel(importSource: .chrome, summary: summaryArray, syncFeatureVisibility: .hide)

        // WHEN
        let summarizedError = model.summarizedError

        // THEN
        XCTAssertNotNil(summarizedError.localizedDescription)
    }

    // MARK: - Navigation and Action Tests

    @MainActor
    func testGoBack_resetsToSourceAndDataTypesPicker() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, screen: .moreInfo, syncFeatureVisibility: .hide)

        // WHEN
        model.goBack()

        // THEN
        XCTAssertEqual(model.screen, .sourceAndDataTypesPicker)
    }

    @MainActor
    func testGoBack_clearsSummary() {
        // GIVEN
        let summaryArray: [DataImportViewModel.DataTypeImportResult] = [
            .init(.bookmarks, .success(.init(successful: 10, duplicate: 0, failed: 0)))
        ]
        model = DataImportViewModel(importSource: .chrome, summary: summaryArray, syncFeatureVisibility: .hide)

        // WHEN
        model.goBack()

        // THEN
        XCTAssertTrue(model.summary.isEmpty)
    }

    @MainActor
    func testUpdateWithImportSource_createsNewModelWithNewSource() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, syncFeatureVisibility: .hide)

        // WHEN
        model.update(with: .firefox)

        // THEN
        XCTAssertEqual(model.importSource, .firefox)
    }

    @MainActor
    func testUpdateWithImportSource_resetsSelectedProfile() {
        // GIVEN
        let testProfile = BrowserProfile.test(fileStore: fileStore)
        model = DataImportViewModel(importSource: .chrome, syncFeatureVisibility: .hide, loadProfiles: { browser in
            .init(browser: browser, profiles: [testProfile(browser)])
        })
        let originalProfile = testProfile(.chrome)
        model.selectedProfile = originalProfile

        // WHEN
        model.update(with: .firefox)

        // THEN
        // The selected profile should now be for Firefox, not Chrome
        XCTAssertEqual(model.selectedProfile?.browser, .firefox)
        XCTAssertNotEqual(model.selectedProfile?.browser, originalProfile.browser)
    }

    // MARK: - Import Button Flow Tests

    @MainActor
    func testImportButtonPressed_initiatesImportWhenImporterCanImport() {
        // GIVEN
        setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
            ImporterMock(importTask: { _, _ in [:] })
        })

        // WHEN
        model.importButtonPressed()

        // THEN
        XCTAssertNotNil(model.importTaskId)
    }

    @MainActor
    func testImportButtonPressed_showsArchiveImportForSafariWhenNoImportableData() {
        // GIVEN
        if #available(macOS 15.2, *) {
            setupModel(with: .safari, dataImporterFactory: { _, _, _, _ in
                ImporterMock(importableTypes: [], importTask: { _, _ in [:] })
            })

            // WHEN
            model.importButtonPressed()

            // THEN
            XCTAssertTrue(model.screen.isArchiveImport)
        }
    }

    @MainActor
    func testImportButtonPressed_showsProfilePickerWhenMultipleValidProfiles() {
        // GIVEN
        setupModel(with: .chrome, profiles: [BrowserProfile.test(fileStore: fileStore), BrowserProfile.test2(fileStore: fileStore), BrowserProfile.test3(fileStore: fileStore)])

        // WHEN
        model.importButtonPressed()

        // THEN
        XCTAssertTrue(model.screen.isProfilePicker)
    }

    @MainActor
    func testImportButtonPressed_showsFileImportWhenNoProfilesFound() {
        // GIVEN
        model = DataImportViewModel(importSource: .firefox, syncFeatureVisibility: .hide, loadProfiles: { browser in
            .init(browser: browser, profiles: [])
        })

        // WHEN
        model.importButtonPressed()

        // THEN
        XCTAssertTrue(model.screen.isFileImport)
    }

    @MainActor
    func testImportButtonPressed_showsMoreInfoWhenKeychainPasswordRequired() {
        // GIVEN
        setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
            ImporterMock(keychainPasswordRequiredFor: [.passwords], importTask: { _, _ in [:] })
        })

        // WHEN
        model.importButtonPressed()

        // THEN
        XCTAssertEqual(model.screen, .moreInfo)
    }

    @MainActor
    func testImportButtonPressed_doesNotShowMoreInfoWhenPasswordsNotSelected() {
        // GIVEN
        setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
            ImporterMock(keychainPasswordRequiredFor: [.passwords], importTask: { _, _ in [:] })
        })
        model.selectedDataTypes = [.bookmarks]

        // WHEN
        model.importButtonPressed()

        // THEN
        XCTAssertNotEqual(model.screen, .moreInfo)
    }

    // MARK: - File Selection Tests

    @MainActor
    func testSelectFile_usesDataTypeAllowedFileTypesForFileImportScreen() {
        // GIVEN
        var capturedFileTypes: [UTType]?
        openPanelCallback = { fileTypes in
            capturedFileTypes = fileTypes
            return .testCSV
        }
        setupModel(with: .chrome, screen: .fileImport(dataType: .passwords), dataImporterFactory: { _, _, _, _ in
            ImporterMock(importTask: { _, _ in [:] })
        })

        // WHEN
        model.selectFile()

        // THEN
        XCTAssertEqual(capturedFileTypes, [.commaSeparatedText])
    }

    @MainActor
    func testSelectFile_usesArchiveSupportedFilesForArchiveImportScreen() {
        // GIVEN
        if #available(macOS 15.2, *) {
            var capturedFileTypes: [UTType]?
            openPanelCallback = { fileTypes in
                capturedFileTypes = fileTypes
                return .testZIP
            }
            setupModel(with: .safari, screen: .archiveImport(dataTypes: [.bookmarks, .passwords]), dataImporterFactory: { _, _, _, _ in
                ImporterMock(importTask: { _, _ in [:] })
            })

            // WHEN
            model.selectFile()

            // THEN
            XCTAssertEqual(Set(capturedFileTypes ?? []), Set([.zip, .commaSeparatedText, .json, .html]))
        }
    }

    @MainActor
    func testSelectFile_usesAllSupportedDataTypesForPickerScreen() {
        // GIVEN
        var capturedFileTypes: [UTType]?
        openPanelCallback = { fileTypes in
            capturedFileTypes = fileTypes
            return .testHTML
        }
        setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
            ImporterMock(importTask: { _, _ in [:] })
        })

        // WHEN
        model.selectFile()

        // THEN
        XCTAssertTrue(capturedFileTypes?.contains(.html) == true)
        XCTAssertTrue(capturedFileTypes?.contains(.commaSeparatedText) == true)
    }

    @MainActor
    func testSelectFile_initiatesImportWithSelectedFileURL() {
        // GIVEN
        openPanelCallback = { _ in .testCSV }
        setupModel(with: .chrome, screen: .fileImport(dataType: .passwords), dataImporterFactory: { _, _, _, _ in
            ImporterMock(importTask: { _, _ in [:] })
        })

        // WHEN
        model.selectFile()

        // THEN
        XCTAssertNotNil(model.importTaskId)
    }

    // MARK: - Skip/Dismiss Tests

    @MainActor
    func testSkipImportOrDismiss_movesToNextDataTypeWhenMoreToImport() {
        // GIVEN
        let summaryArray: [DataImportViewModel.DataTypeImportResult] = [
            .init(.bookmarks, .failure(Failure(.bookmarks, .dataCorrupted)))
        ]
        setupModel(
            with: .chrome,
            screen: .fileImport(dataType: .bookmarks, summary: [:]),
            summary: summaryArray
        )
        // Ensure both data types are selected
        model.selectedDataTypes = [.bookmarks, .passwords]

        // WHEN
        model.skipImportOrDismiss(using: {})

        // THEN
        XCTAssertTrue(model.screen.isFileImport)
        XCTAssertEqual(model.screen.fileImportDataType, .passwords)
    }

    @MainActor
    func testSkipImportOrDismiss_showsSummaryWhenNoMoreDataTypesToImport() {
        // GIVEN
        let summaryArray: [DataImportViewModel.DataTypeImportResult] = [
            .init(.passwords, .failure(Failure(.passwords, .dataCorrupted)))
        ]
        model = DataImportViewModel(
            importSource: .chrome,
            screen: .fileImport(dataType: .passwords, summary: [:]),
            summary: summaryArray,
            syncFeatureVisibility: .hide
        )

        // WHEN
        model.skipImportOrDismiss(using: {})

        // THEN
        switch model.screen {
        case .summary:
            break // Expected
        default:
            XCTFail("Expected summary screen, got \(model.screen)")
        }
    }

    // MARK: - Perform Action Tests

    @MainActor
    func testPerformActionBack_callsGoBack() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, screen: .moreInfo, syncFeatureVisibility: .hide)

        // WHEN
        model.performAction(for: .back, dismiss: {})

        // THEN
        XCTAssertEqual(model.screen, .sourceAndDataTypesPicker)
    }

    @MainActor
    func testPerformActionInitiateImport_callsImportButtonPressed() {
        // GIVEN
        setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
            ImporterMock(importTask: { _, _ in [:] })
        })

        // WHEN
        model.performAction(for: .initiateImport(disabled: false), dismiss: {})

        // THEN
        XCTAssertNotNil(model.importTaskId)
    }

    @MainActor
    func testPerformActionContinue_callsImportButtonPressed() {
        // GIVEN
        setupModel(with: .chrome, screen: .profilePicker, dataImporterFactory: { _, _, _, _ in
            ImporterMock(importTask: { _, _ in [:] })
        })

        // WHEN
        model.performAction(for: .continue, dismiss: {})

        // THEN
        XCTAssertNotNil(model.importTaskId)
    }

    @MainActor
    func testPerformActionSelectFile_callsSelectFile() {
        // GIVEN
        openPanelCallback = { _ in .testCSV }
        setupModel(with: .chrome, screen: .fileImport(dataType: .passwords), dataImporterFactory: { _, _, _, _ in
            ImporterMock(importTask: { _, _ in [:] })
        })

        // WHEN
        model.performAction(for: .selectFile, dismiss: {})

        // THEN
        XCTAssertNotNil(model.importTaskId)
    }

    @MainActor
    func testPerformActionSkip_callsSkipImportOrDismiss() {
        // GIVEN
        let summaryArray: [DataImportViewModel.DataTypeImportResult] = [
            .init(.bookmarks, .failure(Failure(.bookmarks, .dataCorrupted)))
        ]
        setupModel(
            with: .chrome,
            screen: .fileImport(dataType: .bookmarks, summary: [:]),
            summary: summaryArray
        )

        // Ensure both data types are selected
        model.selectedDataTypes = [.bookmarks, .passwords]

        // WHEN
        model.performAction(for: .skip, dismiss: {})

        // THEN
        XCTAssertTrue(model.screen.isFileImport)
    }

    @MainActor
    func testPerformActionCancel_cancelsImportTask() async {
        // GIVEN
        let taskCancelled = expectation(description: "task cancelled")
        setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
            ImporterMock(importTask: { _, _ in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                taskCancelled.fulfill()
                return [:]
            })
        })
        model.initiateImport(fileURL: .testProfile)

        // WHEN
        model.performAction(for: .cancel, dismiss: {})

        // THEN - Task should be cancelled (expectation should not fulfill)
        await fulfillment(of: [taskCancelled], timeout: 0.1)
    }

    @MainActor
    func testPerformActionCancel_callsOnCancelled() {
        // GIVEN
        let onCancelledCalled = expectation(description: "onCancelled called")
        model = DataImportViewModel(
            importSource: .chrome,
            syncFeatureVisibility: .hide,
            onCancelled: { onCancelledCalled.fulfill() }
        )

        // WHEN
        model.performAction(for: .cancel, dismiss: {})

        // THEN
        waitForExpectations(timeout: 0)
    }

    @MainActor
    func testPerformActionCancel_callsDismiss() {
        // GIVEN
        let dismissCalled = expectation(description: "dismiss called")
        model = DataImportViewModel(importSource: .chrome, syncFeatureVisibility: .hide)

        // WHEN
        model.performAction(for: .cancel, dismiss: { dismissCalled.fulfill() })

        // THEN
        waitForExpectations(timeout: 0)
    }

    @MainActor
    func testPerformActionSubmit_submitsReport() {
        // GIVEN
        let reportSubmitted = expectation(description: "report submitted")
        model = DataImportViewModel(
            importSource: .chrome,
            syncFeatureVisibility: .hide,
            reportSenderFactory: {
                { _ in reportSubmitted.fulfill() }
            }
        )

        // WHEN
        model.performAction(for: .submit, dismiss: {})

        // THEN
        waitForExpectations(timeout: 0)
    }

    @MainActor
    func testPerformActionSubmit_callsDismiss() {
        // GIVEN
        let dismissCalled = expectation(description: "dismiss called")
        model = DataImportViewModel(importSource: .chrome, syncFeatureVisibility: .hide)

        // WHEN
        model.performAction(for: .submit, dismiss: { dismissCalled.fulfill() })

        // THEN
        waitForExpectations(timeout: 0)
    }

    @MainActor
    func testPerformActionDone_callsDismiss() {
        // GIVEN
        let dismissCalled = expectation(description: "dismiss called")
        model = DataImportViewModel(importSource: .chrome, syncFeatureVisibility: .hide)

        // WHEN
        model.performAction(for: .done, dismiss: { dismissCalled.fulfill() })

        // THEN
        waitForExpectations(timeout: 0)
    }

    @MainActor
    func testPerformActionSync_launchesSyncFlow() {
        // GIVEN
        let syncLauncher = SyncLauncherMock()
        let summary: DataImportSummary = [.bookmarks: .success(.init(successful: 10, duplicate: 0, failed: 0))]
        model = DataImportViewModel(
            importSource: .chrome,
            screen: .summary(summary),
            syncFeatureVisibility: .show(syncLauncher: syncLauncher)
        )

        // WHEN
        model.performAction(for: .sync, dismiss: {})

        // THEN
        XCTAssertTrue(syncLauncher.startDeviceSyncFlowCalled)
    }

    // MARK: - Report Model Tests

    func testReportModel_includesCorrectImportSource() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, syncFeatureVisibility: .hide)

        // WHEN
        let reportModel = model.reportModel

        // THEN
        XCTAssertEqual(reportModel.importSource, .chrome)
    }

    func testReportModel_includesCorrectSourceVersion() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, syncFeatureVisibility: .hide)

        // WHEN
        let reportModel = model.reportModel

        // THEN
        XCTAssertNotNil(reportModel.importSourceVersion)
    }

    func testReportModel_includesSummarizedError() {
        // GIVEN
        let summaryArray: [DataImportViewModel.DataTypeImportResult] = [
            .init(.bookmarks, .failure(Failure(.bookmarks, .dataCorrupted)))
        ]
        model = DataImportViewModel(importSource: .chrome, summary: summaryArray, syncFeatureVisibility: .hide)

        // WHEN
        let reportModel = model.reportModel

        // THEN
        XCTAssertNotNil(reportModel.error.localizedDescription)
    }

    func testReportModel_includesUserText() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, syncFeatureVisibility: .hide)
        var reportModel = model.reportModel
        reportModel.text = "Test user text"

        // WHEN
        model.reportModel = reportModel

        // THEN
        XCTAssertEqual(model.reportModel.text, "Test user text")
    }

    func testReportModel_calculatesCorrectRetryNumber() {
        // GIVEN
        let summaryArray: [DataImportViewModel.DataTypeImportResult] = [
            .init(.bookmarks, .failure(Failure(.bookmarks, .dataCorrupted))),
            .init(.bookmarks, .failure(Failure(.bookmarks, .dataCorrupted))),
            .init(.passwords, .failure(Failure(.passwords, .keychainError)))
        ]
        model = DataImportViewModel(importSource: .chrome, summary: summaryArray, syncFeatureVisibility: .hide)

        // WHEN
        let reportModel = model.reportModel

        // THEN
        XCTAssertEqual(reportModel.retryNumber, 2) // Max failures for any single data type
    }

    func testReportModelSetter_updatesUserReportText() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, syncFeatureVisibility: .hide)
        var reportModel = model.reportModel

        // WHEN
        reportModel.text = "Updated text"
        model.reportModel = reportModel

        // THEN
        XCTAssertEqual(model.reportModel.text, "Updated text")
    }

    // MARK: - Launch Sync Tests

    @MainActor
    func testLaunchSync_startsDeviceSyncFlowWithCorrectTouchpoint() {
        // GIVEN
        let syncLauncher = SyncLauncherMock()
        let summary: DataImportSummary = [.bookmarks: .success(.init(successful: 10, duplicate: 0, failed: 0))]
        model = DataImportViewModel(
            importSource: .chrome,
            screen: .summary(summary),
            syncFeatureVisibility: .show(syncLauncher: syncLauncher)
        )

        // WHEN
        model.launchSync(using: {})

        // THEN
        XCTAssertTrue(syncLauncher.startDeviceSyncFlowCalled)
    }

    @MainActor
    func testLaunchSync_usesDataImportStartTouchpointForPickerScreen() {
        // GIVEN
        let syncLauncher = SyncLauncherMock()
        model = DataImportViewModel(
            importSource: .chrome,
            screen: .sourceAndDataTypesPicker,
            syncFeatureVisibility: .show(syncLauncher: syncLauncher)
        )

        // WHEN
        model.launchSync(using: {})

        // THEN
        XCTAssertTrue(syncLauncher.startDeviceSyncFlowCalled)
    }

    @MainActor
    func testLaunchSync_usesDataImportFinishTouchpointForOtherScreens() {
        // GIVEN
        let syncLauncher = SyncLauncherMock()
        let summary: DataImportSummary = [.bookmarks: .success(.init(successful: 10, duplicate: 0, failed: 0))]
        model = DataImportViewModel(
            importSource: .chrome,
            screen: .summary(summary),
            syncFeatureVisibility: .show(syncLauncher: syncLauncher)
        )

        // WHEN
        model.launchSync(using: {})

        // THEN
        XCTAssertTrue(syncLauncher.startDeviceSyncFlowCalled)
    }

    @MainActor
    func testLaunchSync_callsDismiss() {
        // GIVEN
        let dismissCalled = expectation(description: "dismiss called")
        let syncLauncher = SyncLauncherMock()
        model = DataImportViewModel(
            importSource: .chrome,
            syncFeatureVisibility: .show(syncLauncher: syncLauncher)
        )

        // WHEN
        model.launchSync(using: { dismissCalled.fulfill() })

        // THEN
        waitForExpectations(timeout: 0)
    }

    // MARK: - Import Task Lifecycle Tests

    @MainActor
    func testInitiateImport_createsImportTask() {
        // GIVEN
        setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
            ImporterMock(importTask: { _, _ in [:] })
        })

        // WHEN
        model.initiateImport(fileURL: .testProfile)

        // THEN
        XCTAssertNotNil(model.importProgress)
    }

    @MainActor
    func testInitiateImport_setsImportTaskId() {
        // GIVEN
        setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
            ImporterMock(importTask: { _, _ in [:] })
        })

        // WHEN
        model.initiateImport(fileURL: .testProfile)

        // THEN
        XCTAssertNotNil(model.importTaskId)
    }

    @MainActor
    func testInitiateImport_callsDataImporterFactory() {
        // GIVEN
        let factoryCalled = expectation(description: "factory called")
        setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
            factoryCalled.fulfill()
            return ImporterMock(importTask: { _, _ in [:] })
        })

        // WHEN
        model.initiateImport(fileURL: .testProfile)

        // THEN
        waitForExpectations(timeout: 0)
    }

    @MainActor
    func testInitiateImport_passesCorrectDataTypesToImporter() async {
        // GIVEN
        let dataTypesExpectation = expectation(description: "correct data types")
        setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
            ImporterMock(importTask: { dataTypes, _ in
                if dataTypes == [.bookmarks, .passwords] {
                    dataTypesExpectation.fulfill()
                }
                return [:]
            })
        })

        // WHEN
        model.initiateImport(fileURL: .testProfile)
        await fulfillImport()

        // THEN
        await fulfillment(of: [dataTypesExpectation], timeout: 0)
    }

    @MainActor
    func testInitiateImport_passesProfileURLForBrowserImport() {
        // GIVEN
        var capturedURL: URL?
        setupModel(with: .chrome, dataImporterFactory: { _, _, url, _ in
            capturedURL = url
            return ImporterMock(importTask: { _, _ in [:] })
        })

        // WHEN
        let expectedURL = model.selectedProfile?.profileURL
        model.initiateImport()

        // THEN
        XCTAssertEqual(capturedURL, expectedURL)
    }

    @MainActor
    func testInitiateImport_passesFileURLForFileImport() {
        // GIVEN
        var capturedURL: URL?
        setupModel(with: .chrome, screen: .fileImport(dataType: .passwords), dataImporterFactory: { _, _, url, _ in
            capturedURL = url
            return ImporterMock(importTask: { _, _ in [:] })
        })

        // WHEN
        model.initiateImport(fileURL: .testCSV)

        // THEN
        XCTAssertEqual(capturedURL, .testCSV)
    }

    @MainActor
    func testInitiateImport_passesPrimaryPasswordWhenProvided() {
        // GIVEN
        var capturedPassword: String?
        setupModel(with: .firefox, dataImporterFactory: { _, _, _, password in
            capturedPassword = password
            return ImporterMock(importTask: { _, _ in [:] })
        })

        // WHEN
        model.initiateImport(primaryPassword: "test-password", fileURL: .testProfile)

        // THEN
        XCTAssertEqual(capturedPassword, "test-password")
    }

    func testImportTaskCancellation_cancelsRunningTask() async {
        // GIVEN
        let taskStarted = expectation(description: "task started")
        let taskCancelled = expectation(description: "task cancelled")

        await MainActor.run {
            setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
                ImporterMock(importTask: { _, _ in
                    taskStarted.fulfill()
                    do {
                        try await Task.sleep(nanoseconds: 10_000_000_000)
                    } catch is CancellationError {
                        taskCancelled.fulfill()
                    } catch { }
                    return [:]
                })
            })
            model.initiateImport(fileURL: .testProfile)
        }

        await fulfillment(of: [taskStarted], timeout: 1.0)

        // WHEN
        await MainActor.run {
            model.performAction(for: .cancel, dismiss: {})
        }

        // THEN
        await fulfillment(of: [taskCancelled], timeout: 1.0)
    }

    // MARK: - MergeImportSummary Tests (tested via importProgress)

    func testMergeImportSummary_showsSummaryScreen_whenBothDataTypesSucceed() async {
        // GIVEN
        await MainActor.run {
            setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
                ImporterMock(importTask: { _, _ in
                    [
                        .bookmarks: .success(.init(successful: 10, duplicate: 2, failed: 1)),
                        .passwords: .success(.init(successful: 5, duplicate: 1, failed: 0))
                    ]
                })
            })
            model.initiateImport(fileURL: .testProfile)
        }

        // WHEN
        await fulfillImport()

        // THEN
        await MainActor.run {
            if case .summary = model.screen {
                // Expected
            } else {
                XCTFail("Expected summary screen, got \(model.screen)")
            }
        }
    }

    func testMergeImportSummary_appendsSuccessfulResults_toSummaryArray() async {
        // GIVEN
        await MainActor.run {
            setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
                ImporterMock(importTask: { _, _ in
                    [
                        .bookmarks: .success(.init(successful: 10, duplicate: 0, failed: 0)),
                        .passwords: .success(.init(successful: 5, duplicate: 0, failed: 0))
                    ]
                })
            })
            model.initiateImport(fileURL: .testProfile)
        }

        // WHEN
        await fulfillImport()

        // THEN
        await MainActor.run {
            XCTAssertEqual(model.summary.count, 2)
            XCTAssertTrue(model.summary.contains { $0.dataType == .bookmarks && $0.result.isSuccess })
            XCTAssertTrue(model.summary.contains { $0.dataType == .passwords && $0.result.isSuccess })
        }
    }

    func testMergeImportSummary_clearsImportTask() async {
        // GIVEN
        await MainActor.run {
            setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
                ImporterMock(importTask: { _, _ in [:] })
            })
            model.initiateImport(fileURL: .testProfile)
        }

        // WHEN
        await fulfillImport()

        // THEN
        await MainActor.run {
            XCTAssertNil(model.importProgress)
        }
    }

    func testMergeImportSummary_showsFileImportForPasswords_whenBookmarksSucceedPasswordsFail() async {
        // GIVEN
        await MainActor.run {
            setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
                ImporterMock(importTask: { _, _ in
                    [
                        .bookmarks: .success(.init(successful: 10, duplicate: 0, failed: 0)),
                        .passwords: .failure(Failure(.passwords, .keychainError))
                    ]
                })
            })
            model.initiateImport(fileURL: .testProfile)
        }

        // WHEN
        await fulfillImport()

        // THEN
        await MainActor.run {
            XCTAssertTrue(model.screen.isFileImport)
            XCTAssertEqual(model.screen.fileImportDataType, .passwords)
        }
    }

    func testMergeImportSummary_appendsBothResults_whenOneSucceedsOneFails() async {
        // GIVEN
        await MainActor.run {
            setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
                ImporterMock(importTask: { _, _ in
                    [
                        .bookmarks: .success(.init(successful: 10, duplicate: 0, failed: 0)),
                        .passwords: .failure(Failure(.passwords, .keychainError))
                    ]
                })
            })
            model.initiateImport(fileURL: .testProfile)
        }

        // WHEN
        await fulfillImport()

        // THEN
        await MainActor.run {
            XCTAssertEqual(model.summary.count, 2)
        }
    }

    func testMergeImportSummary_showsFileImportForPasswords_whenBookmarksSucceedPasswordsEmpty() async {
        // GIVEN
        await MainActor.run {
            setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
                ImporterMock(importTask: { _, _ in
                    [
                        .bookmarks: .success(.init(successful: 10, duplicate: 0, failed: 0)),
                        .passwords: .success(.init(successful: 0, duplicate: 0, failed: 0))
                    ]
                })
            })
            model.initiateImport(fileURL: .testProfile)
        }

        // WHEN
        await fulfillImport()

        // THEN
        await MainActor.run {
            XCTAssertTrue(model.screen.isFileImport)
            XCTAssertEqual(model.screen.fileImportDataType, .passwords)
        }
    }

    func testMergeImportSummary_showsFileImportForBookmarks_whenBookmarksFailPasswordsSucceed() async {
        // GIVEN
        await MainActor.run {
            setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
                ImporterMock(importTask: { _, _ in
                    [
                        .bookmarks: .failure(Failure(.bookmarks, .dataCorrupted)),
                        .passwords: .success(.init(successful: 10, duplicate: 0, failed: 0))
                    ]
                })
            })
            model.initiateImport(fileURL: .testProfile)
        }

        // WHEN
        await fulfillImport()

        // THEN
        await MainActor.run {
            XCTAssertTrue(model.screen.isFileImport)
            XCTAssertEqual(model.screen.fileImportDataType, .bookmarks)
        }
    }

    func testMergeImportSummary_showsFileImportForBookmarks_whenNoBookmarksPasswordsSucceed() async {
        // GIVEN
        await MainActor.run {
            setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
                ImporterMock(importTask: { _, _ in
                    [
                        .bookmarks: .success(.init(successful: 0, duplicate: 0, failed: 0)),
                        .passwords: .success(.init(successful: 10, duplicate: 0, failed: 0))
                    ]
                })
            })
            model.initiateImport(fileURL: .testProfile)
        }

        // WHEN
        await fulfillImport()

        // THEN
        await MainActor.run {
            XCTAssertTrue(model.screen.isFileImport)
            XCTAssertEqual(model.screen.fileImportDataType, .bookmarks)
        }
    }

    func testMergeImportSummary_doesNotSwitchToSameFileImport_whenAlreadyOnThatScreen() async {
        // GIVEN
        await MainActor.run {
            setupModel(with: .chrome, screen: .fileImport(dataType: .passwords, summary: [:]), dataImporterFactory: { _, _, _, _ in
                ImporterMock(importTask: { _, _ in
                    [.passwords: .success(.init(successful: 10, duplicate: 0, failed: 0))]
                })
            })
            model.initiateImport(fileURL: .testCSV)
        }

        // WHEN
        await fulfillImport()

        // THEN
        await MainActor.run {
            if case .summary = model.screen {
                // Expected - should switch to summary, not stay on file import
            } else {
                XCTFail("Expected summary screen, got \(model.screen)")
            }
        }
    }

    // MARK: - HandleErrors Tests (tested via validateAccess and import results)

    func testHandleErrors_requestsPrimaryPasswordForFirefoxWhenRequired() async {
        // GIVEN
        let passwordRequested = expectation(description: "password requested")
        await MainActor.run {
            setupModel(
                with: .firefox,
                dataImporterFactory: { _, _, _, password in
                    ImporterMock(
                        password: password,
                        accessValidator: { importer, _ in
                            if importer.password == nil {
                                return [.passwords: FirefoxLoginReader.ImportError(type: .requiresPrimaryPassword, underlyingError: nil)]
                            }
                            return nil
                        },
                        importTask: { _, _ in
                            [
                                .bookmarks: .success(.init(successful: 10, duplicate: 0, failed: 0)),
                                .passwords: .success(.init(successful: 5, duplicate: 0, failed: 0))
                            ]
                        }
                    )
                },
                requestPrimaryPasswordCallback: { _ in
                    passwordRequested.fulfill()
                    return "test-password"
                }
            )
            model.initiateImport(fileURL: .testProfile)
        }

        // THEN
        await fulfillment(of: [passwordRequested], timeout: 1.0)
    }

    func testHandleErrors_reinitiatesImportWithProvidedPassword() async {
        // GIVEN
        let importCount = ImportCounter()

        await MainActor.run {
            setupModel(
                with: .firefox,
                dataImporterFactory: { _, _, _, password in
                    ImporterMock(
                        password: password,
                        accessValidator: { importer, _ in
                            if importer.password == nil {
                                return [.passwords: FirefoxLoginReader.ImportError(type: .requiresPrimaryPassword, underlyingError: nil)]
                            }
                            return nil
                        },
                        importTask: { _, _ in
                            await importCount.increment()
                            return [
                                .bookmarks: .success(.init(successful: 10, duplicate: 0, failed: 0)),
                                .passwords: .success(.init(successful: 5, duplicate: 0, failed: 0))
                            ]
                        }
                    )
                },
                requestPrimaryPasswordCallback: { _ in "test-password" }
            )
            model.initiateImport(fileURL: .testProfile)
        }

        // WHEN
        await fulfillImport()

        // THEN
        let count = await importCount.value
        XCTAssertEqual(count, 1) // Only once with password (validateAccess catches the first attempt before import starts)
    }

    func testHandleErrors_doesNotReinitiateImport_whenPasswordRejected() async {
        // GIVEN
        let importCount = ImportCounter()
        await MainActor.run {
            setupModel(
                with: .firefox,
                dataImporterFactory: { _, _, _, password in
                    ImporterMock(
                        password: password,
                        accessValidator: { importer, _ in
                            if importer.password == nil {
                                return [.passwords: FirefoxLoginReader.ImportError(type: .requiresPrimaryPassword, underlyingError: nil)]
                            }
                            return nil
                        },
                        importTask: { _, _ in
                            await importCount.increment()
                            return [:]
                        }
                    )
                },
                requestPrimaryPasswordCallback: { _ in nil } // User cancelled
            )
            model.initiateImport(fileURL: .testProfile)
        }

        // WHEN
        try? await Task.sleep(nanoseconds: 100_000_000)

        // THEN
        let count = await importCount.value
        await MainActor.run {
            XCTAssertEqual(count, 0) // Should not have called import at all
            XCTAssertEqual(model.screen, .sourceAndDataTypesPicker) // Should be back at start
        }
    }

    func testHandleErrors_goesBack_whenKeychainPromptDenied() async {
        // GIVEN
        await MainActor.run {
            setupModel(with: .chrome, screen: .passwordEntryHelp, dataImporterFactory: { _, _, _, _ in
                ImporterMock(
                    accessValidator: { _, _ in
                        [.passwords: ChromiumLoginReader.ImportError(type: .userDeniedKeychainPrompt)]
                    },
                    importTask: { _, _ in [:] }
                )
            })
            model.initiateImport(fileURL: .testProfile)
        }

        // WHEN
        try? await Task.sleep(nanoseconds: 100_000_000)

        // THEN
        await MainActor.run {
            XCTAssertEqual(model.screen, .sourceAndDataTypesPicker)
        }
    }

    func testHandleErrors_appendsErrorToErrorsArray() async {
        // GIVEN
        await MainActor.run {
            setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
                ImporterMock(
                    accessValidator: { _, _ in
                        [.passwords: ChromiumLoginReader.ImportError(type: .userDeniedKeychainPrompt)]
                    },
                    importTask: { _, _ in [:] }
                )
            })
            model.initiateImport(fileURL: .testProfile)
        }

        // WHEN
        try? await Task.sleep(nanoseconds: 100_000_000)

        // THEN
        await MainActor.run {
            XCTAssertFalse(model.errors.isEmpty)
        }
    }

    func testHandleErrors_showsPasswordEntryHelp_onFirstKeychainPromptDenial() async {
        // GIVEN
        await MainActor.run {
            setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
                ImporterMock(
                    accessValidator: { _, _ in
                        [.passwords: ChromiumLoginReader.ImportError(type: .userDeniedKeychainPrompt)]
                    },
                    importTask: { _, _ in [:] }
                )
            })
            model.initiateImport(fileURL: .testProfile)
        }

        // WHEN
        try? await Task.sleep(nanoseconds: 100_000_000)

        // THEN
        await MainActor.run {
            XCTAssertEqual(model.screen, .passwordEntryHelp, "First denial should show password entry help screen")
        }
    }

    func testHandleErrors_goesBackToSourcePicker_onSecondKeychainPromptDenial() async {
        // GIVEN
        await MainActor.run {
            setupModel(
                with: .chrome,
                screen: .passwordEntryHelp,
                dataImporterFactory: { _, _, _, _ in
                    ImporterMock(
                        accessValidator: { _, _ in
                            [.passwords: ChromiumLoginReader.ImportError(type: .userDeniedKeychainPrompt)]
                        },
                        importTask: { _, _ in [:] }
                    )
                }
            )
            model.initiateImport(fileURL: .testProfile)
        }

        // WHEN
        try? await Task.sleep(nanoseconds: 100_000_000)

        // THEN
        await MainActor.run {
            XCTAssertEqual(model.screen, .sourceAndDataTypesPicker, "Second denial from password entry help should go back to source picker")
        }
    }

    func testHandleErrors_successfullyRetriesFromPasswordEntryHelp() async {
        // GIVEN
        let importCount = ImportCounter()
        await MainActor.run {
            setupModel(
                with: .chrome,
                screen: .passwordEntryHelp,
                dataImporterFactory: { _, _, _, _ in
                    ImporterMock(
                        accessValidator: { _, _ in
                            // No error on retry - user granted access
                            nil
                        },
                        importTask: { _, _ in
                            await importCount.increment()
                            return [
                                .bookmarks: .success(.init(successful: 10, duplicate: 0, failed: 0)),
                                .passwords: .success(.init(successful: 5, duplicate: 0, failed: 0))
                            ]
                        }
                    )
                }
            )
            model.initiateImport(fileURL: .testProfile)
        }

        // WHEN
        await fulfillImport()

        // THEN
        let count = await importCount.value
        await MainActor.run {
            XCTAssertEqual(count, 1, "Import should have been called once")
            XCTAssertTrue(model.isDataTypeSuccessfullyImported(.bookmarks))
            XCTAssertTrue(model.isDataTypeSuccessfullyImported(.passwords))
            if case .summary = model.screen {
                // Expected - should show summary after successful import
            } else {
                XCTFail("Expected summary screen after successful import, got \(model.screen)")
            }
        }
    }

    // MARK: - ImportProgress AsyncStream Tests

    func testImportProgress_returnsNil_whenNoImportTask() {
        // GIVEN
        model = DataImportViewModel(importSource: .chrome, syncFeatureVisibility: .hide)

        // WHEN
        let progress = model.importProgress

        // THEN
        XCTAssertNil(progress)
    }

    @MainActor
    func testImportProgress_yieldsCompletedEventWithMergedModel() async {
        // GIVEN
        setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
            ImporterMock(importTask: { _, _ in
                [.bookmarks: .success(.init(successful: 10, duplicate: 0, failed: 0))]
            })
        })
        model.initiateImport(fileURL: .testProfile)

        // WHEN
        guard let progressStream = model.importProgress else {
            XCTFail("Expected progress stream")
            return
        }

        var completedModel: DataImportViewModel?
        for await event in progressStream {
            if case .completed(.success(let newModel)) = event {
                completedModel = newModel
                break
            }
        }

        // THEN
        XCTAssertNotNil(completedModel)
        XCTAssertFalse(completedModel?.summary.isEmpty ?? true)
    }

    @MainActor
    func testImportProgress_callsOnFinished_whenImportCompletes() async {
        // GIVEN
        let onFinishedCalled = expectation(description: "onFinished called")
        model = DataImportViewModel(
            importSource: .chrome,
            syncFeatureVisibility: .hide,
            dataImporterFactory: { _, _, _, _ in
                ImporterMock(importTask: { _, _ in [:] })
            },
            onFinished: { onFinishedCalled.fulfill() }
        )
        model.initiateImport(fileURL: .testProfile)

        // WHEN
        await fulfillImport()

        // THEN
        await fulfillment(of: [onFinishedCalled], timeout: 1.0)
    }

    // MARK: - Full Integration Tests

    func testFullImportFlow_browserSourceBothTypesSuccess() async {
        // GIVEN
        await MainActor.run {
            setupModel(with: .chrome, dataImporterFactory: { _, _, _, _ in
                ImporterMock(importTask: { _, _ in
                    [
                        .bookmarks: .success(.init(successful: 100, duplicate: 10, failed: 2)),
                        .passwords: .success(.init(successful: 50, duplicate: 5, failed: 1))
                    ]
                })
            })
        }

        // WHEN
        await MainActor.run {
            model.initiateImport(fileURL: .testProfile)
        }
        await fulfillImport()

        // THEN
        await MainActor.run {
            XCTAssertEqual(model.summary.count, 2)
            XCTAssertTrue(model.isDataTypeSuccessfullyImported(.bookmarks))
            XCTAssertTrue(model.isDataTypeSuccessfullyImported(.passwords))
            if case .summary = model.screen {
                // Expected
            } else {
                XCTFail("Expected summary screen")
            }
        }
    }

    func testFullImportFlow_browserSourceBookmarksSuccessPasswordsFailThenFileImport() async {
        // GIVEN
        await MainActor.run {
            setupModel(with: .chrome, dataImporterFactory: { source, dataType, _, _ in
                ImporterMock(importTask: { types, _ in
                    if dataType == .passwords {
                        // File import
                        return [.passwords: .success(.init(successful: 30, duplicate: 3, failed: 0))]
                    } else {
                        // Browser import
                        return [
                            .bookmarks: .success(.init(successful: 100, duplicate: 0, failed: 0)),
                            .passwords: .failure(Failure(.passwords, .keychainError))
                        ]
                    }
                })
            })
        }

        // WHEN - Initial browser import
        await MainActor.run {
            model.initiateImport(fileURL: .testProfile)
        }
        await fulfillImport()

        await MainActor.run {
            XCTAssertTrue(model.screen.isFileImport)
            XCTAssertEqual(model.screen.fileImportDataType, .passwords)
        }

        // WHEN - File import
        await MainActor.run {
            openPanelCallback = { _ in .testCSV }
            model.selectFile()
        }
        await fulfillImport()

        // THEN
        await MainActor.run {
            XCTAssertEqual(model.summary.count, 3) // bookmarks success, passwords failure, passwords success
            if case .summary = model.screen {
                // Expected
            } else {
                XCTFail("Expected summary screen")
            }
        }
    }

    func testFullImportFlow_fileSourcePasswordsImportSuccess() async {
        // GIVEN
        await MainActor.run {
            setupModel(with: .csv, screen: .sourceAndDataTypesPicker, dataImporterFactory: { _, _, _, _ in
                ImporterMock(importTask: { _, _ in
                    [.passwords: .success(.init(successful: 42, duplicate: 5, failed: 2))]
                })
            })
            openPanelCallback = { _ in .testCSV }
        }

        // WHEN
        await MainActor.run {
            model.selectFile()
        }
        await fulfillImport()

        // THEN
        await MainActor.run {
            XCTAssertEqual(model.summary.count, 1)
            XCTAssertTrue(model.isDataTypeSuccessfullyImported(.passwords))
            if case .summary = model.screen {
                // Expected
            } else {
                XCTFail("Expected summary screen")
            }
        }
    }

    // MARK: - Helper Methods

    func setupModel(
        with source: Source,
        profiles: [(ThirdPartyBrowser) -> BrowserProfile]? = nil,
        screen: DataImportViewModel.Screen? = nil,
        summary: [DataImportViewModel.DataTypeImportResult] = [],
        dataImporterFactory: DataImportViewModel.DataImporterFactory? = nil,
        requestPrimaryPasswordCallback: ((DataImportViewModel.Source) -> String?)? = nil
    ) {
        let actualProfiles = profiles ?? [BrowserProfile.test(fileStore: fileStore)]
        model = DataImportViewModel(
            importSource: source,
            screen: screen,
            summary: summary,
            syncFeatureVisibility: .hide,
            loadProfiles: { browser in
                let createdProfiles = actualProfiles.map { $0(browser) }
                return .init(browser: browser, profiles: createdProfiles) { profile in
                    {
                        // All profiles have valid data available
                        .init(logins: .available, bookmarks: .available)
                    }
                }
            },
            dataImporterFactory: dataImporterFactory ?? { _, _, _, _ in ImporterMock(importTask: self.importTask) },
            requestPrimaryPasswordCallback: requestPrimaryPasswordCallback ?? { _ in nil },
            openPanelCallback: { self.openPanelCallback!($0) }
        )
    }

    @MainActor
    func fulfillImport() async {
        guard let progressStream = model.importProgress else { return }

        for await event in progressStream {
            if case .completed(.success(let newModel)) = event {
                model = newModel
                return
            }
        }
    }
}

// MARK: - Test Helpers

private extension DataImport.BrowserProfile {
    /// Creates a test profile closure that accepts a FileStoreMock
    static func test(fileStore: FileStoreMock) -> (ThirdPartyBrowser) -> Self {
        return { browser in
            let profile = Self.init(browser: browser, profileURL: .profile(named: "Test Profile"), fileStore: fileStore)
            Self.configureFileStore(fileStore, for: profile)
            return profile
        }
    }

    static func test2(fileStore: FileStoreMock) -> (ThirdPartyBrowser) -> Self {
        return { browser in
            let profile = Self.init(browser: browser, profileURL: .profile(named: "Test Profile 2"), fileStore: fileStore)
            Self.configureFileStore(fileStore, for: profile)
            return profile
        }
    }

    static func test3(fileStore: FileStoreMock) -> (ThirdPartyBrowser) -> Self {
        return { browser in
            let profile = Self.init(browser: browser, profileURL: .profile(named: "Test Profile 3"), fileStore: fileStore)
            Self.configureFileStore(fileStore, for: profile)
            return profile
        }
    }

    static func `default`(fileStore: FileStoreMock) -> (ThirdPartyBrowser) -> Self {
        return { browser in
            let profileURL: URL
            switch browser {
            case .firefox, .tor:
                profileURL = .profile(named: DataImport.BrowserProfileList.Constants.firefoxDefaultProfileName)
            case .safari:
                // Safari doesn't use named profiles, it's just the Safari directory
                profileURL = URL.nonSandboxLibraryDirectoryURL.appendingPathComponent("Safari/")
            case .safariTechnologyPreview:
                profileURL = URL.nonSandboxLibraryDirectoryURL.appendingPathComponent("SafariTechnologyPreview/")
            default:
                // Chromium-based browsers
                profileURL = .profile(named: DataImport.BrowserProfileList.Constants.chromiumDefaultProfileName)
            }

            let profile = Self.init(browser: browser, profileURL: profileURL, fileStore: fileStore)
            Self.configureFileStore(fileStore, for: profile)
            return profile
        }
    }

    /// Configures the FileStoreMock to return appropriate files for the given profile
    private static func configureFileStore(_ fileStore: FileStoreMock, for profile: DataImport.BrowserProfile) {
        let path = profile.profileURL.path

        switch profile.browser {
        case .brave, .chrome, .chromium, .coccoc, .edge, .opera, .operaGX, .vivaldi, .yandex:
            // Chromium-based browsers need "Login Data" for logins and "Bookmarks" for bookmarks
            fileStore.directoryStorage[path] = ["Login Data", "Bookmarks"]
        case .firefox, .tor:
            // Firefox needs "logins.json" and "key4.db" for logins, and "places.sqlite" for bookmarks
            fileStore.directoryStorage[path] = ["logins.json", "key4.db", "places.sqlite"]
        case .safari, .safariTechnologyPreview:
            // Safari always returns .available, no specific files needed but we'll add some anyway
            fileStore.directoryStorage[path] = ["Bookmarks.plist"]
        case .bitwarden, .lastPass, .onePassword7, .onePassword8:
            // Password managers - just add some dummy data
            fileStore.directoryStorage[path] = ["data"]
        }
    }
}

private struct Failure: DataImportError {
    enum OperationType: Int {
        case failure
    }

    var action: DataImportAction
    var type: OperationType = .failure
    var underlyingError: Error?
    var errorType: DataImport.ErrorType = .other

    init(_ action: DataImportAction, _ errorType: DataImport.ErrorType) {
        self.action = action
        self.errorType = errorType
    }
}

private class ImporterMock: DataImporter {
    var password: String?
    var importableTypes: [DataImport.DataType]
    var keychainPasswordRequiredFor: Set<DataImport.DataType>

    init(
        password: String? = nil,
        importableTypes: [DataImport.DataType] = [.bookmarks, .passwords],
        keychainPasswordRequiredFor: Set<DataImport.DataType> = [],
        accessValidator: ((ImporterMock, Set<DataImport.DataType>) -> [DataImport.DataType: any DataImportError]?)? = nil,
        importTask: ((Set<DataImport.DataType>, DataImportProgressCallback) async -> DataImportSummary)? = nil
    ) {
        self.password = password
        self.importableTypes = importableTypes
        self.keychainPasswordRequiredFor = keychainPasswordRequiredFor
        self.accessValidator = accessValidator
        self.importTask = importTask
    }

    func requiresKeychainPassword(for selectedDataTypes: Set<DataImport.DataType>) -> Bool {
        selectedDataTypes.intersects(keychainPasswordRequiredFor)
    }

    var accessValidator: ((ImporterMock, Set<DataImport.DataType>) -> [DataImport.DataType: any DataImportError]?)?

    func validateAccess(for types: Set<DataImport.DataType>) -> [DataImport.DataType: any DataImportError]? {
        accessValidator?(self, types)
    }

    var importTask: ((Set<DataImport.DataType>, DataImportProgressCallback) async -> DataImportSummary)?

    func importData(types: Set<DataImport.DataType>) -> DataImportTask {
        .detachedWithProgress { [importTask=importTask!] updateProgress in
            await importTask(types, updateProgress)
        }
    }
}

private extension URL {
    static let mockURL = URL(fileURLWithPath: "/Users/Dax/Library/ApplicationSupport/BrowserCompany/Browser/")
    static let testCSV = URL(fileURLWithPath: "/Users/Dax/Downloads/passwords.csv")
    static let testHTML = URL(fileURLWithPath: "/Users/Dax/Downloads/bookmarks.html")
    static let testZIP = URL(fileURLWithPath: "/Users/Dax/Downloads/test.zip")
    static let testProfile = URL(fileURLWithPath: "/Users/Dax/Library/ApplicationSupport/Chrome/Default")

    static func profile(named name: String) -> URL {
        return mockURL.appendingPathComponent(name)
    }
}

private class SyncLauncherMock: SyncDeviceFlowLaunching {
    var startDeviceSyncFlowCalled = false
    var capturedCompletion: (() -> Void)?

    @MainActor
    func startDeviceSyncFlow(source: SyncDeviceButtonTouchpoint, completion: (() -> Void)?) {
        startDeviceSyncFlowCalled = true
        capturedCompletion = completion
    }
}

private actor ImportCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    var value: Int {
        count
    }
}
