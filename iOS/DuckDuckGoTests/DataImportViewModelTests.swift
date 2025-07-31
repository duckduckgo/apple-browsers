//
//  DataImportViewModelTests.swift
//  DuckDuckGoTests
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
@testable import DuckDuckGo
import Core
import BrowserServicesKit
import Common

class DataImportViewModelTests: XCTestCase {

    var viewModel: DataImportViewModel!
    fileprivate var mockImportManager: MockDataImportManager!
    fileprivate var mockDelegate: MockDataImportViewModelDelegate!

    override func setUp() {
        super.setUp()
        mockImportManager = MockDataImportManager()
        mockDelegate = MockDataImportViewModelDelegate()
    }

    override func tearDown() {
        viewModel = nil
        mockImportManager = nil
        mockDelegate = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization_WithPasswordsScreen() {
        viewModel = DataImportViewModel(importScreen: .passwords, importManager: mockImportManager)
        viewModel.delegate = mockDelegate

        XCTAssertEqual(viewModel.state.importScreen, .passwords)
        XCTAssertEqual(viewModel.state.browser, .safari)
        XCTAssertFalse(viewModel.isLoading)
    }

    // MARK: - File Selection Tests

    func testSelectFile_DelegateNotified() {
        viewModel = DataImportViewModel(importScreen: .passwords, importManager: mockImportManager)
        viewModel.delegate = mockDelegate

        viewModel.selectFile()

        XCTAssertTrue(mockDelegate.didRequestImportFile)
    }

    // MARK: - ZIP Import Tests

    func testHandleFileSelection_WithValidZipContainingOnlyPasswords() async {
        viewModel = DataImportViewModel(importScreen: .passwords, importManager: mockImportManager)
        viewModel.delegate = mockDelegate

        let url = Bundle(for: DataImportViewModelTests.self)
            .url(forResource: "MockFiles/zip/safari_passwords_only", withExtension: "zip")!

        let summary = DataImport.DataTypeSummary(successful: 11, duplicate: 0, failed: 0)
        mockImportManager.mockImportFileSummary = [.passwords: .success(summary)]

        viewModel.handleFileSelection(url, type: .zip)

        await fulfillment(of: [mockDelegate.summaryExpectation], timeout: 10.0)
        let lastSummary = try? mockDelegate.lastSummary?[.passwords]?.get()

        XCTAssertEqual(lastSummary, summary)
    }

    func testHandleFileSelection_WithValidZipContainingBothTypes() {
        viewModel = DataImportViewModel(importScreen: .passwords, importManager: mockImportManager)
        viewModel.delegate = mockDelegate

        let url = Bundle(for: DataImportViewModelTests.self)
            .url(forResource: "MockFiles/zip/safari_passwords_bookmarks", withExtension: "zip")!

        viewModel.handleFileSelection(url, type: .zip)

        XCTAssertTrue(mockDelegate.didRequestPresentDataPicker)
    }

    func testHandleFileSelection_WithInvalidZip() {
        viewModel = DataImportViewModel(importScreen: .passwords, importManager: mockImportManager)
        viewModel.delegate = mockDelegate

        let url = Bundle(for: DataImportViewModelTests.self)
            .url(forResource: "MockFiles/zip/empty", withExtension: "zip")!

        viewModel.handleFileSelection(url, type: .zip)

        XCTAssertFalse(mockDelegate.didRequestPresentDataPicker)
    }

    // MARK: - File Type Import Tests

    func testHandleFileSelection_WithCSVFile() async {
        viewModel = DataImportViewModel(importScreen: .passwords, importManager: mockImportManager)
        viewModel.delegate = mockDelegate

        let url = Bundle(for: DataImportViewModelTests.self)
            .url(forResource: "MockFiles/passwords/passwords", withExtension: "csv")!

        let summary = DataImport.DataTypeSummary(successful: 5, duplicate: 0, failed: 0)
        mockImportManager.mockImportFileSummary = [.passwords: .success(summary)]

        viewModel.handleFileSelection(url, type: .csv)

        await fulfillment(of: [mockDelegate.summaryExpectation], timeout: 1.0)
        let lastSummary = try? mockDelegate.lastSummary?[.passwords]?.get()
        XCTAssertEqual(lastSummary, summary)
    }

    func testHandleFileSelection_WithHTMLFile() async {
        viewModel = DataImportViewModel(importScreen: .bookmarks, importManager: mockImportManager)
        viewModel.delegate = mockDelegate

        let url = Bundle(for: DataImportViewModelTests.self)
            .url(forResource: "MockFiles/bookmarks/bookmarks_safari", withExtension: "html")!

        let summary = DataImport.DataTypeSummary(successful: 3, duplicate: 0, failed: 0)
        mockImportManager.mockImportFileSummary = [.bookmarks: .success(summary)]

        viewModel.handleFileSelection(url, type: .html)

        await fulfillment(of: [mockDelegate.summaryExpectation], timeout: 1.0)
        let lastSummary = try? mockDelegate.lastSummary?[.bookmarks]?.get()
        XCTAssertEqual(lastSummary, summary)
    }

    func testHandleFileSelection_WithCSVFileError() async {
        viewModel = DataImportViewModel(importScreen: .passwords, importManager: mockImportManager)
        viewModel.delegate = mockDelegate

        let url = URL(fileURLWithPath: "non-existent-file.csv")

        mockImportManager.mockImportFileSummary = nil

        viewModel.handleFileSelection(url, type: .csv)
        XCTAssertFalse(mockDelegate.didRequestPresentSummary)
    }

    func testInitialization_WithBookmarksScreen() {
        viewModel = DataImportViewModel(importScreen: .bookmarks, importManager: mockImportManager)
        viewModel.delegate = mockDelegate

        XCTAssertEqual(viewModel.state.importScreen, .bookmarks)
        XCTAssertEqual(viewModel.state.browser, .safari)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testBrowserImportState_WithPasswordScreen() {
        let state = DataImportViewModel.BrowserImportState(browser: .safari, importScreen: .passwords)

        XCTAssertEqual(state.title, UserText.dataImportPasswordsTitle)
        XCTAssertEqual(state.subtitle, UserText.dataImportPasswordsSubtitle)
        XCTAssertEqual(state.buttonTitle, UserText.dataImportPasswordsSelectFileButton)
        XCTAssertEqual(state.displayName, UserText.dataImportPasswordsInstructionSafari)
    }

    func testBrowserImportState_WithBookmarksScreen() {
        let state = DataImportViewModel.BrowserImportState(browser: .safari, importScreen: .bookmarks)

        XCTAssertEqual(state.title, UserText.dataImportBookmarksTitle)
        XCTAssertEqual(state.subtitle, UserText.dataImportBookmarksSubtitle)
        XCTAssertEqual(state.buttonTitle, UserText.dataImportBookmarksFileButton)
        XCTAssertEqual(state.displayName, UserText.dataImportPasswordsInstructionSafari)
    }

    // MARK: - Instruction Step Tests

    func testInstructionSteps_ForSafariPasswords() {
        viewModel = DataImportViewModel(importScreen: .passwords, importManager: mockImportManager)
        let state = viewModel.state

        for step in state.instructionSteps {
            let instructions = step.attributedInstructions(for: state)
            XCTAssertFalse(instructions.characters.isEmpty)
        }
    }

    func testInstructionSteps_ForChromePasswords() {
        viewModel = DataImportViewModel(importScreen: .passwords, importManager: mockImportManager)
        viewModel.state.browser = .chrome
        let state = viewModel.state

        for step in state.instructionSteps {
            let instructions = step.attributedInstructions(for: state)
            XCTAssertFalse(instructions.characters.isEmpty)
        }
    }

    // MARK: - Loading State Tests

    func testLoadingState_DuringZipImport() async throws {
        throw XCTSkip("Flaky test")

        viewModel = DataImportViewModel(importScreen: .passwords, importManager: mockImportManager)
        viewModel.delegate = mockDelegate

        let url = Bundle(for: DataImportViewModelTests.self)
            .url(forResource: "MockFiles/zip/safari_passwords_only", withExtension: "zip")!

        let summary = DataImport.DataTypeSummary(successful: 1, duplicate: 0, failed: 0)
        mockImportManager.mockImportFileSummary = [.passwords: .success(summary)]

        await MainActor.run {
            XCTAssertFalse(viewModel.isLoading)
            viewModel.handleFileSelection(url, type: .zip)
            XCTAssertTrue(viewModel.isLoading)
        }

        await fulfillment(of: [mockDelegate.summaryExpectation], timeout: 1.0)

        await MainActor.run {
            XCTAssertFalse(viewModel.isLoading)
        }
    }

    func testLoadingState_DuringCSVImport() async throws {
        throw XCTSkip("Flaky test")

        viewModel = DataImportViewModel(importScreen: .passwords, importManager: mockImportManager)
        viewModel.delegate = mockDelegate

        let url = Bundle(for: DataImportViewModelTests.self)
            .url(forResource: "MockFiles/passwords/passwords", withExtension: "csv")!

        let summary = DataImport.DataTypeSummary(successful: 5, duplicate: 0, failed: 0)
        mockImportManager.mockImportFileSummary = [.passwords: .success(summary)]

        await MainActor.run {
            XCTAssertFalse(viewModel.isLoading)
            viewModel.handleFileSelection(url, type: .csv)
            XCTAssertTrue(viewModel.isLoading)
        }

        await fulfillment(of: [mockDelegate.summaryExpectation], timeout: 1.0)

        await MainActor.run {
            XCTAssertFalse(viewModel.isLoading)
        }
    }

    // MARK: - Error Handling Tests

    func testHandleFileSelection_WithZipReadError() {
        viewModel = DataImportViewModel(importScreen: .passwords, importManager: mockImportManager)
        viewModel.delegate = mockDelegate

        let url = Bundle(for: DataImportViewModelTests.self)
            .url(forResource: "MockFiles/zip/empty", withExtension: "zip")!

        viewModel.handleFileSelection(url, type: .zip)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testHandleFileSelection_WithHTMLFileError() async {
        viewModel = DataImportViewModel(importScreen: .bookmarks, importManager: mockImportManager)
        viewModel.delegate = mockDelegate

        let url = URL(fileURLWithPath: "non-existent-file.html")

        mockImportManager.mockImportFileSummary = nil

        viewModel.handleFileSelection(url, type: .html)
        XCTAssertFalse(mockDelegate.didRequestPresentSummary)
    }
}

// MARK: - Mock Classes

private class MockDataImportManager: DataImportManaging {
    var mockContents: ImportArchiveContents?
    var mockImportFileSummary: DataImportSummary?
    var mockImportData: DataImportSummary = [:]

    func importFile(at url: URL, for fileType: DataImportFileType) async throws -> DataImportSummary? {
        return mockImportFileSummary
    }

    func importZipArchive(from contents: ImportArchiveContents, for dataTypes: [DataImport.DataType]) async -> DataImportSummary {
        return mockImportFileSummary ?? [:]
    }

    static func preview(contents: ImportArchiveContents, tld: TLD) -> [DataImportPreview] {
        return [DataImportPreview(type: .passwords, count: 1)]
    }

    var importableTypes: [DataImport.DataType] {
        return [.passwords, .bookmarks]
    }

    func importData(types: Set<DataImport.DataType>) -> DataImportTask {
        return .detachedWithProgress { [weak self] updateProgress in
            guard let self = self else { return [:] }
            try? updateProgress(.done)
            return self.mockImportData
        }
    }
}

private class MockDataImportViewModelDelegate: DataImportViewModelDelegate {
    var didRequestImportFile = false
    var didRequestPresentDataPicker = false
    var didRequestPresentSummary = false
    var lastSummary: DataImportSummary?
    let summaryExpectation = XCTestExpectation(description: "Summary presented")

    weak var viewModel: DataImportViewModel?

    func dataImportViewModelDidRequestImportFile(_ viewModel: DataImportViewModel) {
        self.viewModel = viewModel
        didRequestImportFile = true
        self.viewModel?.isLoading = true
    }

    func dataImportViewModelDidRequestPresentDataPicker(_ viewModel: DataImportViewModel, contents: ImportArchiveContents) {
        self.viewModel = viewModel
        didRequestPresentDataPicker = true
    }

    func dataImportViewModelDidRequestPresentSummary(_ viewModel: DataImportViewModel, summary: DataImportSummary) {
        self.viewModel = viewModel
        didRequestPresentSummary = true
        lastSummary = summary
        self.viewModel?.isLoading = false
        summaryExpectation.fulfill()
    }
}
