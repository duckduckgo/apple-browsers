//
//  ScopedFireConfirmationViewModelTests.swift
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

import XCTest
@testable import DuckDuckGo

@MainActor
final class ScopedFireConfirmationViewModelTests: XCTestCase {
    
    // MARK: - burnAllTabs Tests
    
    func testWhenBurnAllTabsCalledThenOnConfirmIsCalledWithCorrectRequest() {
        // Given
        var capturedRequest: FireRequest?
        let sut = ScopedFireConfirmationViewModel(
            tabViewModel: nil,
            onConfirm: { request in
                capturedRequest = request
            },
            onCancel: { }
        )
        
        // When
        sut.burnAllTabs()
        
        // Then
        XCTAssertNotNil(capturedRequest)
        XCTAssertEqual(capturedRequest?.options, .all)
        XCTAssertEqual(capturedRequest?.trigger, .manualFire)
        if case .all = capturedRequest?.scope {
            // Expected scope
        } else {
            XCTFail("Expected scope to be .all")
        }
    }
    
    // MARK: - cancel Tests
    
    func testWhenCancelCalledThenOnCancelIsCalled() {
        // Given
        var cancelCalled = false
        let sut = ScopedFireConfirmationViewModel(
            tabViewModel: nil,
            onConfirm: { _ in },
            onCancel: {
                cancelCalled = true
            }
        )
        
        // When
        sut.cancel()
        
        // Then
        XCTAssertTrue(cancelCalled)
    }
    
    // MARK: - canBurnSingleTab Tests
    
    func testWhenTabViewModelIsNilThenCanBurnSingleTabReturnsFalse() {
        // Given
        let sut = ScopedFireConfirmationViewModel(
            tabViewModel: nil,
            onConfirm: { _ in },
            onCancel: { }
        )
        
        // Then
        XCTAssertFalse(sut.canBurnSingleTab)
    }
    
    func testWhenTabViewModelIsNotNilThenCanBurnSingleTabReturnsTrue() {
        // Given
        let sut = ScopedFireConfirmationViewModel(
            tabViewModel: createTabViewModel(),
            onConfirm: { _ in },
            onCancel: { }
        )
        
        // Then
        XCTAssertTrue(sut.canBurnSingleTab)
    }
    
    // MARK: - Helpers
    
    private func createTabViewModel() -> TabViewModel {
        let mockHistoryManager = MockHistoryManager()
        let tab = Tab()
        return TabViewModel(tab: tab, historyManager: mockHistoryManager)
    }
}
