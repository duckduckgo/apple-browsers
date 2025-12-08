//
//  FireConfirmationViewModelTests.swift
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

final class FireConfirmationViewModelTests: XCTestCase {
    
    private struct MockTabsModel: TabsModeling {
        let count: Int
    }
    
    private func makeViewModel(tabsModel: TabsModeling?) -> FireConfirmationViewModel {
        return FireConfirmationViewModel(
            tabsModel: tabsModel,
            onConfirm: {},
            onCancel: {}
        )
    }
    
    func testWhenTabsModelIsNilThenClearTabsSubtitleReturnsZeroCount() {
        // Given
        let viewModel = makeViewModel(tabsModel: nil)
        
        // When
        let subtitle = viewModel.clearTabsSubtitle()
        
        // Then
        XCTAssertEqual(subtitle, "None")
    }
    
    func testWhenTabsModelHasZeroTabsThenClearTabsSubtitleShowsNone() {
        // Given
        let tabsModel = MockTabsModel(count: 0)
        let viewModel = makeViewModel(tabsModel: tabsModel)
        
        // When
        let subtitle = viewModel.clearTabsSubtitle()
        
        // Then
        XCTAssertEqual(subtitle, "None")
    }
    
    func testWhenTabsModelHasOneTabThenClearTabsSubtitleShowsSingular() {
        // Given
        let tabsModel = MockTabsModel(count: 1)
        let viewModel = makeViewModel(tabsModel: tabsModel)
        
        // When
        let subtitle = viewModel.clearTabsSubtitle()
        
        // Then
        XCTAssertEqual(subtitle, "Close 1 tab")
    }
    
    func testWhenTabsModelHasMultipleTabsThenClearTabsSubtitleShowsPlural() {
        // Given
        let tabsModel = MockTabsModel(count: 5)
        let viewModel = makeViewModel(tabsModel: tabsModel)
        
        // When
        let subtitle = viewModel.clearTabsSubtitle()
        
        // Then
        XCTAssertEqual(subtitle, "Close all 5 tabs")
    }
}
