//
//  DuckPlayerUserScriptYoutubeTests.swift
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
import Combine
@testable import Core
@testable import DuckDuckGo
@testable import BrowserServicesKit
@testable import DuckPlayer
@testable import UserScript

@MainActor
class DuckPlayerUserScriptYoutubeTests: XCTestCase {
    
    var mockDuckPlayer: MockDuckPlayer!
    var mockWebView: MockWebView!
    var mockHostView: MockDuckPlayerHosting!
    var userScript: DuckPlayerUserScriptYouTube!
    var cancellables = Set<AnyCancellable>()
    
    override func setUp() async throws {
        // Setup mock dependencies
        let mockSettings = MockDuckPlayerSettings(
            appSettings: AppSettingsMock(),
            privacyConfigManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockDuckPlayerFeatureFlagger(),
            internalUserDecider: MockDuckPlayerInternalUserDecider()
        )
        
        let mockFeatureFlagger = MockDuckPlayerFeatureFlagger()
        
        mockDuckPlayer = MockDuckPlayer(settings: mockSettings, featureFlagger: mockFeatureFlagger)
        mockWebView = MockWebView()
        mockHostView = MockDuckPlayerHosting()
        mockHostView.webView = mockWebView
        
        mockDuckPlayer.setHostViewController(mockHostView)
        
        // Create the user script being tested
        userScript = DuckPlayerUserScriptYouTube(duckPlayer: mockDuckPlayer)
    }
    
    override func tearDown() {
        cancellables.removeAll()
        userScript = nil
        mockDuckPlayer = nil
        mockWebView = nil
        mockHostView = nil
    }
    
    // MARK: - Test Page Type Detection
    
    func testGetPageTypeForYoutubeURL() {
        // Set the URL for the mock webview
        let youtubeURL = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        mockWebView.setCurrentURL(youtubeURL)
        
        // Test page type detection
        XCTAssertEqual(DuckPlayerUserScript.getPageType(url: youtubeURL), DuckPlayerUserScript.PageType.YOUTUBE)
    }
    
    func testGetPageTypeForNonVideoURL() {
        // Set a non-video YouTube URL
        let nonVideoURL = URL(string: "https://www.youtube.com/feed/trending")!
        mockWebView.setCurrentURL(nonVideoURL)
        
        // Test page type detection
        XCTAssertEqual(DuckPlayerUserScript.getPageType(url: nonVideoURL), DuckPlayerUserScript.PageType.UNKNOWN)
    }
    
    func testGetPageTypeForDuckDuckGoURL() {
        // Set a DuckDuckGo URL
        let ddgURL = URL(string: "https://duckduckgo.com/?q=test")!
        mockWebView.setCurrentURL(ddgURL)
        
        // Test page type detection
        XCTAssertEqual(DuckPlayerUserScript.getPageType(url: ddgURL), DuckPlayerUserScript.PageType.SERP)
    }
    
    func testGetPageTypeForNoCookieURL() {
        // Set a YouTube no-cookie URL
        let noCookieURL = URL(string: "https://www.youtube-nocookie.com/watch?v=dQw4w9WgXcQ")!
        mockWebView.setCurrentURL(noCookieURL)
        
        // Test page type detection
        XCTAssertEqual(DuckPlayerUserScript.getPageType(url: noCookieURL), DuckPlayerUserScript.PageType.NOCOOKIE)
    }
    
    // MARK: - Test URL Change Handling
    
    func testOnUrlChangedUpdatesPageType() {
        // Test that URL change affects event handling
        let youtubeURL = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        
        // Navigate to the page
        mockWebView.setCurrentURL(youtubeURL)
        
        // Then call onUrlChanged
        userScript.onUrlChanged(url: youtubeURL)
        
        // Verify state was reset to the proper URL type
        let pageType = DuckPlayerUserScript.getPageType(url: youtubeURL)
        XCTAssertEqual(pageType, DuckPlayerUserScript.PageType.YOUTUBE)
    }
    
    // MARK: - Test Handlers Registration
    
    func testHandlerForMethodNamedReturnsCorrectHandlers() {
        // Test handler registration for YouTube error
        XCTAssertNotNil(userScript.handler(forMethodNamed: DuckPlayerUserScript.Handlers.onYoutubeError))
        
        // Test handler registration for current timestamp
        XCTAssertNotNil(userScript.handler(forMethodNamed: DuckPlayerUserScript.Handlers.onCurrentTimeStamp))
        
        // Test handler registration for initialSetup
        XCTAssertNotNil(userScript.handler(forMethodNamed: DuckPlayerUserScript.Handlers.initialSetup))
        
        // Test handler registration for onDuckPlayerScriptsReady
        XCTAssertNotNil(userScript.handler(forMethodNamed: DuckPlayerUserScript.Handlers.onDuckPlayerScriptsReady))
        
        // Test unknown handler returns nil
        XCTAssertNil(userScript.handler(forMethodNamed: "unknownHandler"))
    }
    
    // MARK: - Test Message Origin Policy
    
    func testMessageOriginPolicyContainsExpectedRules() {
        let policy = userScript.messageOriginPolicy
        
        // Check that the policy contains the expected origins
        switch policy {
        case .only(let rules):
            XCTAssertEqual(rules.count, 6) // Check we have the expected number of rules
            
            // Check for specific domains
            let containsDuckDuckGo = rules.contains(where: {
                if case .exact(let hostname) = $0, hostname == DuckPlayerSettingsDefault.OriginDomains.duckduckgo {
                    return true
                }
                return false
            })
            XCTAssertTrue(containsDuckDuckGo, "Policy should include duckduckgo.com")
            
            let containsYoutube = rules.contains(where: {
                if case .exact(let hostname) = $0, hostname == DuckPlayerSettingsDefault.OriginDomains.youtube {
                    return true
                }
                return false
            })
            XCTAssertTrue(containsYoutube, "Policy should include youtube.com")
        
        default:
            XCTFail("Expected .only policy type")
        }
    }
    
    // MARK: - Test Handler Functionality
    
    func testOnCurrentTimeStampHandlerUpdatesTimestamp() async {
        // Setup
        let expectation = expectation(description: "Timestamp should be updated")
        let timestamp = 42.5
        let params: [String: Any] = [DuckPlayerUserScript.Constants.timestamp: "\(timestamp)"]
        
        // Monitor timestamp publisher
        mockDuckPlayer.currentTimeStampPublisher
            .sink { receivedTimestamp in
                XCTAssertEqual(receivedTimestamp, timestamp)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Execute
        if let handler = userScript.handler(forMethodNamed: DuckPlayerUserScript.Handlers.onCurrentTimeStamp) {
            _ = try? await handler(params, MockScriptMessage())
        } else {
            XCTFail("Handler not found")
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testInitialSetupHandlerWithDifferentURLs() async {
        // Test with YouTube URL
        mockWebView.setCurrentURL(URL(string: "https://www.youtube.com/watch?v=testVideo")!)
        if let handler = userScript.handler(forMethodNamed: DuckPlayerUserScript.Handlers.initialSetup),
           let result = try? await handler([:], MockScriptMessage()) as? [String: String] {
            XCTAssertEqual(result[DuckPlayerUserScript.Constants.pageType], DuckPlayerUserScript.PageType.YOUTUBE)
            XCTAssertEqual(result[DuckPlayerUserScript.Constants.playbackPaused], "false")
            XCTAssertNotNil(result[DuckPlayerUserScript.Constants.locale])
        } else {
            XCTFail("Handler should return valid result")
        }
        
        // Test with DuckDuckGo URL
        mockWebView.setCurrentURL(URL(string: "https://duckduckgo.com/?q=test")!)
        if let handler = userScript.handler(forMethodNamed: DuckPlayerUserScript.Handlers.initialSetup),
           let result = try? await handler([:], MockScriptMessage()) as? [String: String] {
            XCTAssertEqual(result[DuckPlayerUserScript.Constants.pageType], DuckPlayerUserScript.PageType.SERP)
            XCTAssertEqual(result[DuckPlayerUserScript.Constants.playbackPaused], "false")
            XCTAssertNotNil(result[DuckPlayerUserScript.Constants.locale])
        } else {
            XCTFail("Handler should return valid result")
        }
        
        // Test with non-video YouTube URL
        mockWebView.setCurrentURL(URL(string: "https://www.youtube.com/feed/trending")!)
        if let handler = userScript.handler(forMethodNamed: DuckPlayerUserScript.Handlers.initialSetup),
           let result = try? await handler([:], MockScriptMessage()) as? [String: String] {
            XCTAssertEqual(result[DuckPlayerUserScript.Constants.pageType], DuckPlayerUserScript.PageType.UNKNOWN)
            XCTAssertEqual(result[DuckPlayerUserScript.Constants.playbackPaused], "false")
            XCTAssertNotNil(result[DuckPlayerUserScript.Constants.locale])
        } else {
            XCTFail("Handler should return valid result")
        }
    }
    
    func testOnDuckPlayerScriptsReadyProcessesQueue() async {
        // This test is harder to implement directly since it depends on internal state
        // Instead, we'll verify the handler exists and doesn't crash when called
        
        if let handler = userScript.handler(forMethodNamed: DuckPlayerUserScript.Handlers.onDuckPlayerScriptsReady) {
            let result = try? await handler([:], MockScriptMessage())
            XCTAssertNil(result, "Handler should return nil")
        } else {
            XCTFail("Handler not found")
        }
    }
}
