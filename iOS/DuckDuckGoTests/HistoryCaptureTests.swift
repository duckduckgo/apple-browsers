//
//  HistoryCaptureTests.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import Persistence
import History
@testable import Core

final class HistoryCaptureTests: XCTestCase {

    private var mockHistoryManager: MockHistoryManager!
    private var sut: HistoryCapture!
    
    override func setUp() {
        mockHistoryManager = MockHistoryManager()
        sut = HistoryCapture(historyManager: mockHistoryManager, tabID: "1")
    }

    @MainActor
    func test_whenURLIsCommitted_ThenVisitIsStored() async {
        sut.webViewDidCommit(url: URL.example)
        XCTAssertEqual(1, mockHistoryManager.addVisitCalls.count)
        XCTAssertEqual([URL.example], mockHistoryManager.addVisitCalls)
    }

    @MainActor
    func test_whenTitleIsUpdatedForMatchingURL_ThenTitleIsSaved() async {
        sut.webViewDidCommit(url: URL.example)
        sut.titleDidChange("test", forURL: URL.example)
        XCTAssertEqual(1, mockHistoryManager.updateTitleIfNeededCalls.count)
        XCTAssertEqual(mockHistoryManager.updateTitleIfNeededCalls[0].title, "test")
        XCTAssertEqual(mockHistoryManager.updateTitleIfNeededCalls[0].url, URL.example)
    }

    @MainActor
    func test_whenTitleIsUpdatedForDifferentURL_ThenTitleIsIgnored() async {
        sut.webViewDidCommit(url: URL.example)
        sut.titleDidChange("test", forURL: URL.example.appendingPathComponent("path"))
        XCTAssertEqual(0, mockHistoryManager.updateTitleIfNeededCalls.count)
    }

    @MainActor
    func test_whenComittedURLIsASearch_thenCleanURLIsUsed() async {
        sut.webViewDidCommit(url: URL(string: "https://duckduckgo.com/?q=search+terms&t=osx&ia=web")!)
        
        func assertUrlIsExpected(_ url: URL?) {
            XCTAssertEqual(true, url?.isDuckDuckGoSearch)
            XCTAssertEqual(url?.getQueryItems()?.count, 1)
            XCTAssertEqual("search terms", url?.searchQuery)
        }

        assertUrlIsExpected(sut.url)
        XCTAssertEqual(1, mockHistoryManager.addVisitCalls.count)
        assertUrlIsExpected(mockHistoryManager.addVisitCalls[0])
    }

    @MainActor
    func test_whenTitleUpdatedForSearchURL_thenCleanURLIsUsed() async {
        sut.webViewDidCommit(url: URL(string: "https://duckduckgo.com/?q=search+terms&t=osx&ia=web")!)

        // Note parameter order has changed
        sut.titleDidChange("title", forURL: URL(string: "https://duckduckgo.com/?q=search+terms&ia=web&t=osx")!)

        XCTAssertEqual(true, sut.url?.isDuckDuckGoSearch)
        XCTAssertEqual(sut.url?.getQueryItems()?.count, 1)
        XCTAssertEqual(1, mockHistoryManager.updateTitleIfNeededCalls.count)
    }

}

private extension URL {
    static let example = URL(string: "https://example.com")!
}
