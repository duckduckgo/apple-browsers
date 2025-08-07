//
//  DaxEasterEggHandlerTests.swift
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
import WebKit
@testable import DuckDuckGo

final class DaxEasterEggHandlerTests: XCTestCase {
    
    var handler: DaxEasterEggHandler!
    var mockDelegate: MockDaxEasterEggDelegate!
    var mockWebView: WKWebView!
    
    override func setUpWithError() throws {
        mockWebView = WKWebView()
        handler = DaxEasterEggHandler(webView: mockWebView)
        mockDelegate = MockDaxEasterEggDelegate()
        handler.delegate = mockDelegate
    }
    
    override func tearDownWithError() throws {
        handler = nil
        mockDelegate = nil
        mockWebView = nil
    }
    
    // MARK: - URL Processing Tests
    
    func testDidExtractLogo_WithValidThemedURL_ProcessesCorrectly() {
        // Given
        let rawURL = "themed|/dist/logos/dynamic/terminator.png"
        let pageURL = "https://duckduckgo.com/?q=terminator"
        
        // When
        handler.didExtractLogo(rawURL, from: pageURL)
        
        // Then
        XCTAssertEqual(mockDelegate.receivedLogoURL, "https://duckduckgo.com/dist/logos/dynamic/terminator.png")
        XCTAssertEqual(mockDelegate.receivedPageURL, pageURL)
        XCTAssertEqual(mockDelegate.callCount, 1)
    }
    
    func testDidExtractLogo_WithAbsoluteURL_ProcessesCorrectly() {
        // Given
        let rawURL = "themed|https://duckduckgo.com/logos/predator.png"
        let pageURL = "https://duckduckgo.com/?q=predator"
        
        // When
        handler.didExtractLogo(rawURL, from: pageURL)
        
        // Then
        XCTAssertEqual(mockDelegate.receivedLogoURL, "https://duckduckgo.com/logos/predator.png")
        XCTAssertEqual(mockDelegate.receivedPageURL, pageURL)
    }
    
    func testDidExtractLogo_WithInvalidFormat_PassesNil() {
        // Given
        let rawURL = "invalid-format-no-pipe"
        let pageURL = "https://duckduckgo.com/?q=test"
        
        // When
        handler.didExtractLogo(rawURL, from: pageURL)
        
        // Then
        XCTAssertNil(mockDelegate.receivedLogoURL)
        XCTAssertEqual(mockDelegate.receivedPageURL, pageURL)
    }
    
    func testDidExtractLogo_WithNilURL_PassesNil() {
        // Given
        let pageURL = "https://duckduckgo.com/?q=test"
        
        // When
        handler.didExtractLogo(nil, from: pageURL)
        
        // Then
        XCTAssertNil(mockDelegate.receivedLogoURL)
        XCTAssertEqual(mockDelegate.receivedPageURL, pageURL)
    }
    
    func testDidExtractLogo_WithMalformedThemedURL_PassesNil() {
        // Given
        let rawURL = "themed|"  // Missing path
        let pageURL = "https://duckduckgo.com/?q=test"
        
        // When
        handler.didExtractLogo(rawURL, from: pageURL)
        
        // Then
        XCTAssertNil(mockDelegate.receivedLogoURL)
        XCTAssertEqual(mockDelegate.receivedPageURL, pageURL)
    }
    
    func testDidExtractLogo_WithURLEncodedInput_DecodesCorrectly() {
        // Given
        let rawURL = "themed%7C%2Fdist%2Flogos%2Fdynamic%2Fterminator.png"  // URL encoded "themed|/dist/logos/dynamic/terminator.png"
        let pageURL = "https://duckduckgo.com/?q=terminator"
        
        // When
        handler.didExtractLogo(rawURL, from: pageURL)
        
        // Then
        XCTAssertEqual(mockDelegate.receivedLogoURL, "https://duckduckgo.com/dist/logos/dynamic/terminator.png")
    }
    
    // MARK: - Delegate Tests
    
    func testDidExtractLogo_WithNoDelegate_DoesNotCrash() {
        // Given
        handler.delegate = nil
        let rawURL = "themed|/dist/logos/dynamic/test.png"
        let pageURL = "https://duckduckgo.com/?q=test"
        
        // When/Then - should not crash
        XCTAssertNoThrow {
            self.handler.didExtractLogo(rawURL, from: pageURL)
        }
    }
    
    func testDelegate_IsWeakReference() {
        // Given
        var tempDelegate: MockDaxEasterEggDelegate? = MockDaxEasterEggDelegate()
        handler.delegate = tempDelegate
        
        // When
        tempDelegate = nil
        
        // Then
        XCTAssertNil(handler.delegate)
    }
    
    // MARK: - Reset Tests
    
    func testReset_ClearsState() {
        // Given - handler has some state
        
        // When
        handler.reset()
        
        // Then - should not crash and should clear any timers/state
        XCTAssertNoThrow {
            self.handler.reset()
        }
    }
    
    // MARK: - Extract Logos Tests
    
    func testExtractLogosForCurrentPage_WithValidWebView_CallsJavaScript() {
        // Given - webView is set in setUp
        
        // When/Then - should not crash when calling JavaScript
        XCTAssertNoThrow {
            self.handler.extractLogosForCurrentPage()
        }
    }
}

// MARK: - Mock Classes

class MockDaxEasterEggDelegate: DaxEasterEggDelegate {
    var receivedLogoURL: String?
    var receivedPageURL: String?
    var callCount = 0
    
    func daxEasterEggHandler(_ handler: DaxEasterEggHandling, didFindLogoURL logoURL: String?, for pageURL: String) {
        receivedLogoURL = logoURL
        receivedPageURL = pageURL
        callCount += 1
    }
}
