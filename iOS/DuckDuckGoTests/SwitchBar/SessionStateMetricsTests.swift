//
//  SessionStateMetricsTests.swift
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
import PersistenceTestingUtils

final class SessionStateMetricsTests: XCTestCase {

    var mockStorage: MockKeyValueStore!
    var sut: SessionStateMetrics!
    
    override func setUpWithError() throws {
        mockStorage = MockKeyValueStore()
        sut = SessionStateMetrics(storage: mockStorage, pixelFiring: PixelFiringMock.self)
        PixelFiringMock.tearDown()
    }

    override func tearDownWithError() throws {
        mockStorage = nil
        sut = nil
        PixelFiringMock.tearDown()
    }

    // MARK: - Session Type Tests
    
    func testFinalizeSession_SearchOnly_FiresCorrectPixel() throws {
        sut.recordActivity(.searchSubmitted)
        sut.recordActivity(.searchSubmitted)
        
        sut.finalizeSession()
        
        XCTAssertEqual(PixelFiringMock.lastPixelName!, "m_aichat_experimental_omnibar_session_summary")
        
        let parameters = PixelFiringMock.lastParams
        XCTAssertEqual(parameters?["session_type"], "search_only")
        XCTAssertEqual(parameters?["searches_in_session"], "2")
        XCTAssertEqual(parameters?["prompts_in_session"], "0")
    }
    
    func testFinalizeSession_PromptOnly_FiresCorrectPixel() throws {
        sut.recordActivity(.promptSubmitted)
        sut.recordActivity(.promptSubmitted)
        sut.recordActivity(.promptSubmitted)
        
        sut.finalizeSession()
        
        XCTAssertEqual(PixelFiringMock.lastPixelName!, "m_aichat_experimental_omnibar_session_summary")
        
        let parameters = PixelFiringMock.lastParams
        XCTAssertEqual(parameters?["session_type"], "prompt_only")
        XCTAssertEqual(parameters?["searches_in_session"], "0")
        XCTAssertEqual(parameters?["prompts_in_session"], "3")
    }
    
    func testFinalizeSession_BothModes_FiresCorrectPixel() throws {
        sut.recordActivity(.searchSubmitted)
        sut.recordActivity(.promptSubmitted)
        sut.recordActivity(.searchSubmitted)
        
        sut.finalizeSession()
        
        XCTAssertEqual(PixelFiringMock.lastPixelName!, "m_aichat_experimental_omnibar_session_summary")
        
        let parameters = PixelFiringMock.lastParams
        XCTAssertEqual(parameters?["session_type"], "both_modes")
        XCTAssertEqual(parameters?["searches_in_session"], "2")
        XCTAssertEqual(parameters?["prompts_in_session"], "1")
    }
    
    func testFinalizeSession_NoActivity_DoesNotFirePixel() throws {
        sut.finalizeSession()
        
        XCTAssertNil(PixelFiringMock.lastPixelInfo)
        XCTAssertNil(PixelFiringMock.lastParams)
    }
    
    // MARK: - Session Reset Tests
    
    func testFinalizeSession_ResetsCounters() throws {
        sut.recordActivity(.searchSubmitted)
        sut.recordActivity(.promptSubmitted)
        
        sut.finalizeSession()
        
        // Record new activity after finalization
        sut.recordActivity(.searchSubmitted)
        sut.finalizeSession()
        
        let parameters = PixelFiringMock.lastParams
        XCTAssertEqual(parameters?["session_type"], "search_only")
        XCTAssertEqual(parameters?["searches_in_session"], "1")
        XCTAssertEqual(parameters?["prompts_in_session"], "0")
    }
    
    // MARK: - Activity Tests
    
    func testRecordActivity_SearchSubmitted_IncrementsSearchCount() throws {
        sut.recordActivity(.searchSubmitted)
        sut.recordActivity(.searchSubmitted)
        sut.recordActivity(.searchSubmitted)
        
        sut.finalizeSession()
        
        let parameters = PixelFiringMock.lastParams
        XCTAssertEqual(parameters?["searches_in_session"], "3")
        XCTAssertEqual(parameters?["prompts_in_session"], "0")
    }
    
    func testRecordActivity_PromptSubmitted_IncrementsPromptCount() throws {
        sut.recordActivity(.promptSubmitted)
        sut.recordActivity(.promptSubmitted)
        
        sut.finalizeSession()
        
        let parameters = PixelFiringMock.lastParams
        XCTAssertEqual(parameters?["searches_in_session"], "0")
        XCTAssertEqual(parameters?["prompts_in_session"], "2")
    }
    
    // MARK: - Multiple Session Tests
    
    func testMultipleSessions_IndependentCounting() throws {
        // First session: search only
        sut.recordActivity(.searchSubmitted)
        sut.finalizeSession()
        
        let firstSessionParams = PixelFiringMock.lastParams
        XCTAssertEqual(firstSessionParams?["session_type"], "search_only")
        
        // Second session: prompt only
        PixelFiringMock.tearDown() // Clear previous pixel
        sut.recordActivity(.promptSubmitted)
        sut.finalizeSession()
        
        let secondSessionParams = PixelFiringMock.lastParams
        XCTAssertEqual(secondSessionParams?["session_type"], "prompt_only")
        XCTAssertEqual(secondSessionParams?["searches_in_session"], "0")
        XCTAssertEqual(secondSessionParams?["prompts_in_session"], "1")
    }

}
