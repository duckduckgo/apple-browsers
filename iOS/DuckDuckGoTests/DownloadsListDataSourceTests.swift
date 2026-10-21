//
//  DownloadsListDataSourceTests.swift
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

class DownloadsListDataSourceTests: XCTestCase {
    var sut: DownloadsListDataSource!
    var spyDownloadManager: SpyDownloadManager!
    
    override func setUp() {
        super.setUp()
        spyDownloadManager = SpyDownloadManager()
    }
    
    override func tearDown() {
        sut = nil
        spyDownloadManager = nil
        super.tearDown()
    }
    
    private func waitForProcessing() {
        let processExpectation = XCTestExpectation(description: "Processing")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            processExpectation.fulfill()
        }
        wait(for: [processExpectation], timeout: 1.0)
    }
}
