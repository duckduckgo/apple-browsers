//
//  DaxEasterEggImageManagerTests.swift
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
import Kingfisher
@testable import DuckDuckGo

final class DaxEasterEggImageManagerTests: XCTestCase {

    var imageManager: DaxEasterEggImageManager!
    var testURL: URL!
    
    override func setUpWithError() throws {
        imageManager = DaxEasterEggImageManager()
        testURL = URL(string: "https://duckduckgo.com/test-logo.png")!
    }

    override func tearDownWithError() throws {
        imageManager.clearExpiredImages()
        imageManager = nil
        testURL = nil
    }

    func testGetHighResImageFromMemoryCache_WithNoCachedImage_ReturnsNil() {
        let cachedImage = imageManager.getHighResImageFromMemoryCache(for: testURL)
        XCTAssertNil(cachedImage)
    }
    
    func testGetBestImageForFullScreen_CallsCompletion() {
        let expectation = expectation(description: "Calls completion")
        
        imageManager.getBestImageForFullScreen(url: testURL, fallbackImage: nil) { _ in
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0)
    }
    
    func testPreloadDoesNotCrash() {
        XCTAssertNoThrow {
            self.imageManager.preloadFullResolutionImage(for: self.testURL)
        }
    }
    
    func testClearExpiredImagesDoesNotCrash() {
        XCTAssertNoThrow {
            self.imageManager.clearExpiredImages()
        }
    }
}
