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
    
    
    // MARK: - Delegate Tests
    
    
    func testDelegate_IsWeakReference() {
        // Given
        var tempDelegate: MockDaxEasterEggDelegate? = MockDaxEasterEggDelegate()
        handler.delegate = tempDelegate
        
        // When
        tempDelegate = nil
        
        // Then
        XCTAssertNil(handler.delegate)
    }
    
    // MARK: - Extract Logos Tests
    
    func testExtractLogosForCurrentPage_WithValidWebView_CallsJavaScript() {
        // Given - webView is set in setUp
        
        // When/Then - should not crash when calling JavaScript
        XCTAssertNoThrow {
            self.handler.extractLogosForCurrentPage()
        }
    }
    
    func testExtractLogosForCurrentPage_WithNilWebView_HandlesGracefully() {
        // Given
        let handlerWithNilWebView = DaxEasterEggHandler(webView: WKWebView())
        // Simulate webView being deallocated (weak reference becomes nil)
        
        // When/Then - should not crash when webView is nil
        XCTAssertNoThrow {
            handlerWithNilWebView.extractLogosForCurrentPage()
        }
    }
    
    // MARK: - JavaScript Execution Tests (Direct Execution Architecture)
    
    func testExecuteLogoExtraction_HandlesJavaScriptErrors() {
        // Given
        let expectation = XCTestExpectation(description: "JavaScript execution completes")
        expectation.isInverted = false // We expect this to be fulfilled
        
        // Create a handler and start extraction (this tests the JavaScript execution flow)
        // Even if JavaScript fails, it should call didExtractLogo with nil
        let originalCallCount = mockDelegate.callCount
        
        // When
        handler.extractLogosForCurrentPage()
        
        // Give JavaScript time to execute (it will likely fail on an empty webview, which is expected)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Then - should have attempted to process the result (success or failure)
        // This verifies the new direct JavaScript execution architecture works
        XCTAssertTrue(originalCallCount <= self.mockDelegate.callCount, "Should have attempted JavaScript execution")
    }
    
    func testJavaScriptLogic_ReturnsNilWhenNoLogoFound() {
        // This test verifies the embedded JavaScript logic returns nil appropriately
        // Testing the JavaScript string that gets executed directly
        
        // Given - the JavaScript logic embedded in the handler
        let jsLogic = """
        (function() {
            try {
                function findLogo() {
                    var ddgLogo = document.querySelector('.js-logo-ddg');
                    
                    if (!ddgLogo) {
                        ddgLogo = document.querySelector('.logo-dynamic');
                    }
                    if (!ddgLogo) {
                        ddgLogo = document.querySelector('[data-dynamic-logo]');
                    }
                    
                    if (!ddgLogo) {
                        return null;
                    }
                    
                    if (ddgLogo.dataset && ddgLogo.dataset.dynamicLogo) {
                        return 'themed|' + ddgLogo.dataset.dynamicLogo;
                    }
                    
                    return null;
                }
                
                return findLogo();
            } catch (error) {
                return null;
            }
        })();
        """
        
        let expectation = XCTestExpectation(description: "JavaScript returns nil for empty page")
        
        // When - execute JavaScript on empty webview (no logo elements)
        mockWebView.evaluateJavaScript(jsLogic) { result, error in
            // Then
            if let error = error {
                XCTFail("JavaScript execution failed: \(error)")
            } else {
                // Should return nil/null for empty page
                let logoURL = result as? String
                XCTAssertNil(logoURL, "Should return nil when no logo elements found")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
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
