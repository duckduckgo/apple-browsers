//
//  FaviconsHelperTests.swift
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
@testable import Core
@testable import DuckDuckGo

class FaviconsHelperTests: XCTestCase {
    
    override func setUp() {
        super.setUp()

        let expectation = expectation(description: "FaviconHelperTests setup")
        expectation.expectedFulfillmentCount = 2

        Favicons.Constants.tabsCache.clearMemoryCache()
        Favicons.Constants.fireproofCache.clearMemoryCache()

        Favicons.Constants.tabsCache.clearDiskCache { expectation.fulfill() }
        Favicons.Constants.fireproofCache.clearDiskCache { expectation.fulfill() }

        waitForExpectations(timeout: 5, handler: nil)
    }
    
    func testLoadFaviconSync_WhenPlayerDomain_ReturnsDuckPlayer() {
        let result = FaviconsHelper.loadFaviconSync(forDomain: "player",
                                                   usingCache: .fireproof,
                                                   useFakeFavicon: true)
        
        XCTAssertNotNil(result.image)
        XCTAssertEqual(result.image?.accessibilityIdentifier, "DuckPlayerURLIcon")
        XCTAssertFalse(result.isFake)
    }
    
    func testLoadFaviconSync_WhenDuckDuckGo_ReturnsLogo() {
        let result = FaviconsHelper.loadFaviconSync(forDomain: "duckduckgo.com",
                                                   usingCache: .fireproof,
                                                   useFakeFavicon: true)
        
        XCTAssertNotNil(result.image)
        XCTAssertEqual(result.image?.accessibilityIdentifier, "Logo")
        XCTAssertFalse(result.isFake)
    }
    
    func testLoadFaviconSync_WhenMissingFavicon_ReturnsFakeFavicon() {
        let result = FaviconsHelper.loadFaviconSync(forDomain: "missingfavicon.com",
                                                   usingCache: .fireproof,
                                                   useFakeFavicon: true)
        
        XCTAssertNotNil(result.image)
        XCTAssertTrue(result.isFake)
    }
    
    func testLoadFaviconSync_WhenCachedFavicon_ReturnsFromCache() {
        // Setup
        let domain = "example.com"
        let cache = Favicons.Constants.caches[.fireproof]!
        let resource = Favicons.shared.defaultResource(forDomain: domain)!
        let testImage = UIImage(resource: .logo)
        
        cache.store(testImage, forKey: resource.cacheKey)
        
        // Test
        let result = FaviconsHelper.loadFaviconSync(forDomain: domain,
                                                   usingCache: .fireproof,
                                                   useFakeFavicon: true)
        
        XCTAssertNotNil(result.image)
        XCTAssertFalse(result.isFake)
    }
}
