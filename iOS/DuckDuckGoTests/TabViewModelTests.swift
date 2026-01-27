//
//  TabViewModelTests.swift
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

import Foundation
import XCTest
@testable import DuckDuckGo
@testable import Core

@MainActor
final class TabViewModelTests: XCTestCase {

    private var mockHistoryManager: MockHistoryManager!
    private var tab: Tab!
    private var sut: TabViewModel!

    override func setUp() {
        super.setUp()
        mockHistoryManager = MockHistoryManager()
        tab = Tab()
        sut = TabViewModel(tab: tab, historyManager: mockHistoryManager)
    }

    override func tearDown() {
        mockHistoryManager = nil
        tab = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests
    
    func testWhenInitialized_ThenTabIsStoredCorrectly() {
        XCTAssertEqual(sut.tab.uid, tab.uid)
    }

    // MARK: - History Capture Delegation Tests
    
    func testWhenCaptureWebviewDidCommit_ThenDelegatesToHistoryManager() async throws {
        let testURL = URL(string: "https://example.com")!
        
        sut.captureWebviewDidCommit(testURL)
        
        XCTAssertEqual(mockHistoryManager.addVisitCalls.count, 1)
        XCTAssertEqual(mockHistoryManager.addVisitCalls.first, testURL)
    }

    func testWhenCaptureTitleDidChange_ThenDelegatesToHistoryManager() async throws {
        let testURL = URL(string: "https://example.com")!
        let testTitle = "Example Title"
        
        // First commit the URL so the history capture tracks it
        sut.captureWebviewDidCommit(testURL)
        
        sut.captureTitleDidChange(testTitle, for: testURL)
        
        XCTAssertEqual(mockHistoryManager.updateTitleIfNeededCalls.count, 1)
        XCTAssertEqual(mockHistoryManager.updateTitleIfNeededCalls.first?.title, testTitle)
        XCTAssertEqual(mockHistoryManager.updateTitleIfNeededCalls.first?.url, testURL)
    }

    // MARK: - Tab History Tests
    
    func testWhenTabHistoryCalled_ThenReturnsURLsFromHistoryManager() async {
        let expectedURLs = [
            URL(string: "https://example.com")!,
            URL(string: "https://duckduckgo.com")!
        ]
        mockHistoryManager.tabHistoryResult = expectedURLs
        
        let result = await sut.tabHistory()
        
        XCTAssertEqual(mockHistoryManager.tabHistoryCalls, [tab.uid])
        XCTAssertEqual(result, expectedURLs)
    }
}
