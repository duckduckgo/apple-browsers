//
//  ZipContentSelectionViewModelTests.swift
//  DuckDuckGo
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
import BrowserServicesKit
import Core

class ZipContentSelectionViewModelTests: XCTestCase {
    var viewModel: ZipContentSelectionViewModel!
    fileprivate var mockDelegate: MockZipContentSelectionViewModelDelegate!

    override func setUp() {
        super.setUp()
        let preview = [
            DataImportPreview(type: .bookmarks, count: 1),
            DataImportPreview(type: .passwords, count: 1)
        ]
        mockDelegate = MockZipContentSelectionViewModelDelegate()
        viewModel = ZipContentSelectionViewModel(importPreview: preview)
        viewModel.delegate = mockDelegate
    }
    
    func testInitialState_SelectsAllTypesByDefault() {
        XCTAssertEqual(viewModel.selectedTypes, Set([.bookmarks, .passwords]))
    }
    
    func testToggleSelection_RemovesTypeWhenSelected() {
        viewModel.toggleSelection(.bookmarks)
        XCTAssertEqual(viewModel.selectedTypes, Set([.passwords]))
    }
    
    func testToggleSelection_AddsTypeWhenNotSelected() {
        viewModel.selectedTypes = Set([.passwords])
        viewModel.toggleSelection(.bookmarks)
        XCTAssertEqual(viewModel.selectedTypes, Set([.bookmarks, .passwords]))
    }
    
    func testContentHeight_NotifiesDelegateWhenChanged() {
        viewModel.contentHeight = 400
        XCTAssertEqual(mockDelegate.lastContentHeight, 400)
    }
    
    func testContentHeight_EnforcesMinimumHeight() {
        viewModel.contentHeight = 300
        XCTAssertEqual(mockDelegate.lastContentHeight, AutofillViews.zipImportPromptMinHeight)
    }
    
    func testOptionsSelected_NotifiesDelegateWithSelectedTypes() {
        viewModel.selectedTypes = Set([.bookmarks])
        viewModel.optionsSelected()
        XCTAssertEqual(mockDelegate.lastSelectedTypes, [.bookmarks])
    }
    
    func testCloseButtonPressed_NotifiesDelegate() {
        viewModel.closeButtonPressed()
        XCTAssertTrue(mockDelegate.cancelCalled)
    }
}

private class MockZipContentSelectionViewModelDelegate: ZipContentSelectionViewModelDelegate {

    private(set) var lastSelectedTypes: [DataImport.DataType]?
    private(set) var lastContentHeight: CGFloat?
    private(set) var cancelCalled = false

    private(set) var selectOptionsCallCount = 0
    private(set) var resizeContentCallCount = 0
    private(set) var cancelCallCount = 0

    func zipContentSelectionViewModelDidSelectOptions(_ viewModel: ZipContentSelectionViewModel, selectedTypes: [DataImport.DataType]) {
        lastSelectedTypes = selectedTypes
        selectOptionsCallCount += 1
    }

    func zipContentSelectionViewModelDidSelectCancel(_ viewModel: ZipContentSelectionViewModel) {
        cancelCalled = true
        cancelCallCount += 1
    }

    func zipContentSelectionViewModelDidResizeContent(_ viewModel: ZipContentSelectionViewModel, contentHeight: CGFloat) {
        lastContentHeight = contentHeight
        resizeContentCallCount += 1
    }

    func reset() {
        lastSelectedTypes = nil
        lastContentHeight = nil
        cancelCalled = false
        selectOptionsCallCount = 0
        resizeContentCallCount = 0
        cancelCallCount = 0
    }

    func verifyNoInteractions() -> Bool {
        return selectOptionsCallCount == 0 &&
               resizeContentCallCount == 0 &&
               cancelCallCount == 0
    }

    func verifySelectOptionsCalledOnce() -> Bool {
        return selectOptionsCallCount == 1
    }

    func verifyResizeContentCalledOnce() -> Bool {
        return resizeContentCallCount == 1
    }

    func verifyCancelCalledOnce() -> Bool {
        return cancelCallCount == 1
    }
}
