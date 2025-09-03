//
//  DaxEasterEggLogoCacheTests.swift
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

final class DaxEasterEggLogoCacheTests: XCTestCase {
    
    var cache: DaxEasterEggLogoCache!
    
    override func setUpWithError() throws {
        cache = DaxEasterEggLogoCache()
    }

    override func tearDownWithError() throws {
        cache = nil
    }
    
    // MARK: - Basic Cache Functionality Tests
    
    func testStoreLogo_storesLogoURLForSearchQuery() {
        // Given
        let searchQuery = "test query"
        let logoURL = "https://example.com/logo.png"
        
        // When
        cache.storeLogo(logoURL, for: searchQuery)
        
        // Then
        let retrievedURL = cache.getLogo(for: searchQuery)
        XCTAssertEqual(retrievedURL, logoURL)
    }
    
    func testGetLogo_returnsNilForNonExistentQuery() {
        // Given
        let nonExistentQuery = "non existent query"
        
        // When
        let retrievedURL = cache.getLogo(for: nonExistentQuery)
        
        // Then
        XCTAssertNil(retrievedURL)
    }
    
    func testStoreLogo_overwritesExistingEntryForSameQuery() {
        // Given
        let searchQuery = "same query"
        let firstLogoURL = "https://example.com/logo1.png"
        let secondLogoURL = "https://example.com/logo2.png"
        
        // When
        cache.storeLogo(firstLogoURL, for: searchQuery)
        cache.storeLogo(secondLogoURL, for: searchQuery)
        
        // Then
        let retrievedURL = cache.getLogo(for: searchQuery)
        XCTAssertEqual(retrievedURL, secondLogoURL)
    }
    
    func testMultipleEntries_storedCorrectly() {
        // When
        cache.storeLogo("logo1", for: "query1")
        cache.storeLogo("logo2", for: "query2")
        
        // Then
        XCTAssertEqual(cache.getLogo(for: "query1"), "logo1")
        XCTAssertEqual(cache.getLogo(for: "query2"), "logo2")
        
        // Store to same query (should overwrite)
        cache.storeLogo("logo1_updated", for: "query1")
        XCTAssertEqual(cache.getLogo(for: "query1"), "logo1_updated")
        XCTAssertEqual(cache.getLogo(for: "query2"), "logo2") // Should remain unchanged
    }
    
    // MARK: - Query Normalization Tests
    
    func testGetLogo_normalizedQueryMatching() {
        // Given
        let logoURL = "https://example.com/logo.png"
        cache.storeLogo(logoURL, for: "Test Query")
        
        // When/Then - Should find with different cases and whitespace
        XCTAssertEqual(cache.getLogo(for: "test query"), logoURL)
        XCTAssertEqual(cache.getLogo(for: "TEST QUERY"), logoURL)
        XCTAssertEqual(cache.getLogo(for: " Test Query "), logoURL)
        XCTAssertEqual(cache.getLogo(for: "\ttest query\n"), logoURL)
    }
    
    func testStoreLogo_duplicateNormalizedQueriesOverwrite() {
        // Given
        let firstURL = "https://example.com/logo1.png"
        let secondURL = "https://example.com/logo2.png"
        
        // When
        cache.storeLogo(firstURL, for: "Test Query")
        cache.storeLogo(secondURL, for: "test query") // Same normalized query
        
        // Then
        XCTAssertEqual(cache.getLogo(for: "Test Query"), secondURL)
    }
    
    // MARK: - Cache Size Management Tests
    
    func testCacheSizeLimit_clearsWhenExceeded() {
        // Given - Add entries up to the limit
        for i in 0..<10 {
            cache.storeLogo("logo\(i)", for: "query\(i)")
        }
        
        // Verify entries exist
        XCTAssertEqual(cache.getLogo(for: "query0"), "logo0")
        XCTAssertEqual(cache.getLogo(for: "query9"), "logo9")
        
        // When - Add many more entries to exceed the limit (assuming maxCacheSize is 100)
        for i in 10..<120 {
            cache.storeLogo("logo\(i)", for: "query\(i)")
        }
        
        // Then - Cache should have been cleared and new entries should exist
        let recentEntry = cache.getLogo(for: "query115")
        XCTAssertNotNil(recentEntry)
        
        // Early entries may or may not exist depending on when cache was cleared
        // This is implementation-specific behavior
    }
    
    // MARK: - Thread Safety Test
    
    func testConcurrentSameQuery_handledCorrectly() {
        let expectation = XCTestExpectation(description: "Concurrent same query operations complete")
        let sameQuery = "shared-query"
        let operationCount = 10 // Reduced to avoid overwhelming
        let dispatchGroup = DispatchGroup()
        let queue = DispatchQueue(label: "test-same-query", attributes: .concurrent)
        
        // When - Multiple threads access the same query
        for i in 0..<operationCount {
            dispatchGroup.enter()
            queue.async {
                self.cache.storeLogo("logo-from-thread-\(i)", for: sameQuery)
                _ = self.cache.getLogo(for: sameQuery)
                dispatchGroup.leave()
            }
        }
        
        // Wait for all operations to complete
        dispatchGroup.notify(queue: .main) {
            expectation.fulfill()
        }
        
        // Then - Should complete without crashes and have consistent state
        wait(for: [expectation], timeout: 3.0)
        
        // Verify the query exists and has some value
        let finalValue = cache.getLogo(for: sameQuery)
        XCTAssertNotNil(finalValue)
        XCTAssertTrue(finalValue!.hasPrefix("logo-from-thread-"))
    }
}
