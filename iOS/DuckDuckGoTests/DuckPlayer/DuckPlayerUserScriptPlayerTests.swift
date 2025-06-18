//
//  DuckPlayerUserScriptPlayerTests.swift
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
import BrowserServicesKit
import UserScript

@testable import DuckDuckGo
@testable import Core

final class DuckPlayerUserScriptPlayerTests: XCTestCase {
    
    private var mockWebView: MockWebView!
    private var viewModel: DuckPlayerViewModel!
    private var userScriptPlayer: DuckPlayerUserScriptPlayer!
    private var mockScriptMessage: MockScriptMessage!
    
    @MainActor
    override func setUp() {
        super.setUp()
        mockWebView = MockWebView()
        viewModel = DuckPlayerViewModel(videoID: "testVideo")
        userScriptPlayer = DuckPlayerUserScriptPlayer(viewModel: viewModel)
        userScriptPlayer.webView = mockWebView
        mockScriptMessage = MockScriptMessage()
    }
    
    override func tearDown() {
        mockWebView = nil
        viewModel = nil
        userScriptPlayer = nil
        mockScriptMessage = nil
        super.tearDown()
    }
    
    @MainActor
    func testInitialization() {
        XCTAssertEqual(userScriptPlayer.featureName, DuckPlayerUserScript.Constants.featureName)
        XCTAssertNotNil(userScriptPlayer.messageOriginPolicy)
    }
    
    @MainActor
    func testHandlerForMethodNamed() {
        // Test that the correct handlers are returned for supported method names
        XCTAssertNotNil(userScriptPlayer.handler(forMethodNamed: DuckPlayerUserScript.Handlers.onCurrentTimeStamp))
        XCTAssertNotNil(userScriptPlayer.handler(forMethodNamed: DuckPlayerUserScript.Handlers.onYoutubeError))
        XCTAssertNotNil(userScriptPlayer.handler(forMethodNamed: DuckPlayerUserScript.Handlers.initialSetup))
        
        // Test that nil is returned for an unsupported method name
        XCTAssertNil(userScriptPlayer.handler(forMethodNamed: "unsupportedMethod"))
    }
    
    @MainActor
    func testInitialSetupHandler() async {
        // Setup
        let youtubeURL = URL(string: "https://www.youtube.com/watch?v=testVideo")!
        mockWebView.setCurrentURL(youtubeURL)
        
        // Execute
        let result = try? await userScriptPlayer.handler(forMethodNamed: DuckPlayerUserScript.Handlers.initialSetup)?("", mockScriptMessage) as? [String: String]
        
        // Verify
        XCTAssertNotNil(result)
        XCTAssertEqual(result?[DuckPlayerUserScript.Constants.pageType], "YOUTUBE")
        XCTAssertNotNil(result?[DuckPlayerUserScript.Constants.locale])
    }
    
    @MainActor
    func testInitialSetupHandlerForNonYoutube() async {
        // Setup
        let youtubeURL = URL(string: "https://www.google.com")!
        mockWebView.setCurrentURL(youtubeURL)
        
        // Execute
        let result = try? await userScriptPlayer.handler(forMethodNamed: DuckPlayerUserScript.Handlers.initialSetup)?("", mockScriptMessage) as? [String: String]
        
        // Verify
        XCTAssertNotNil(result)
        XCTAssertEqual(result?[DuckPlayerUserScript.Constants.pageType], "UNKNOWN")
        XCTAssertNotNil(result?[DuckPlayerUserScript.Constants.locale])
    }
    
    @MainActor
    func testInitialSetupHandlerWithNoURL() async {
        // Execute - webView URL is nil by default
        let result = try? await userScriptPlayer.handler(forMethodNamed: DuckPlayerUserScript.Handlers.initialSetup)?("", mockScriptMessage) as? [String: String]
        
        // Verify
        XCTAssertNil(result)
    }
    
    @MainActor
    func testOnCurrentTimeStampHandler() async {
        // Setup
        let timestamp = 42.5
        let params: [String: Any] = [DuckPlayerUserScript.Constants.timestamp: "\(timestamp)"]
        
        // Capture initial timestamp
        let initialTimestamp = viewModel.currentTimeStamp
        
        // Execute
        _ = try? await userScriptPlayer.handler(forMethodNamed: DuckPlayerUserScript.Handlers.onCurrentTimeStamp)?(params, mockScriptMessage)
        
        // Verify timestamp was updated
        XCTAssertEqual(viewModel.currentTimeStamp, timestamp)
        XCTAssertNotEqual(viewModel.currentTimeStamp, initialTimestamp)
    }
    
    @MainActor
    func testOnCurrentTimeStampHandlerWithInvalidParams() async {
        // Setup - invalid params (missing timestamp)
        let params: [String: Any] = ["invalidKey": "value"]
        
        // Capture initial timestamp
        let initialTimestamp = viewModel.currentTimeStamp
        
        // Execute
        let result = try? await userScriptPlayer.handler(forMethodNamed: DuckPlayerUserScript.Handlers.onCurrentTimeStamp)?(params, mockScriptMessage) as? [String: String]
        
        // Verify
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.isEmpty ?? false)
        
        // Verify timestamp was not updated
        XCTAssertEqual(viewModel.currentTimeStamp, initialTimestamp)
    }
    
    @MainActor
    func testOnYoutubeErrorHandler() async {
        // Execute
        let result = try? await userScriptPlayer.handler(forMethodNamed: DuckPlayerUserScript.Handlers.onYoutubeError)?("", mockScriptMessage) as? [String: String]
        
        // Verify
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.isEmpty ?? false)
    }
}
