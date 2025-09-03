//
//  AIChatFunnelStateTests.swift
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
import Persistence
import PersistenceTestingUtils

final class AIChatFunnelStateTests: XCTestCase {
    
    var mockStorage: MockKeyValueStore!
    var funnelState: AIChatFunnelState!

    override func setUpWithError() throws {
        mockStorage = MockKeyValueStore()
        funnelState = AIChatFunnelState(storage: mockStorage)
    }

    override func tearDownWithError() throws {
        mockStorage = nil
        funnelState = nil
    }

    func testInitialStateAllFalse() throws {
        XCTAssertFalse(funnelState.hasEverViewedSettings)
        XCTAssertFalse(funnelState.hasEverEnabledFeature)
        XCTAssertFalse(funnelState.hasEverInteractedAfterEnable)
        XCTAssertFalse(funnelState.hasEverSubmittedSearch)
        XCTAssertFalse(funnelState.hasEverSubmittedPrompt)
        XCTAssertFalse(funnelState.hasAchievedFullConversion)
    }
    
    func testMarkFirstSettingsView() throws {
        funnelState.markFirstSettingsView()
        
        XCTAssertTrue(funnelState.hasEverViewedSettings)
        XCTAssertEqual(mockStorage.store["FunnelState.hasEverViewedSettings"] as? Bool, true)
    }
    
    func testMarkFirstFeatureEnable() throws {
        funnelState.markFirstFeatureEnable()
        
        XCTAssertTrue(funnelState.hasEverEnabledFeature)
        XCTAssertEqual(mockStorage.store["FunnelState.hasEverEnabledFeature"] as? Bool, true)
    }
    
    func testMarkFirstInteraction() throws {
        funnelState.markFirstInteraction()
        
        XCTAssertTrue(funnelState.hasEverInteractedAfterEnable)
        XCTAssertEqual(mockStorage.store["FunnelState.hasEverInteractedAfterEnable"] as? Bool, true)
    }
    
    func testMarkFirstSearchSubmission() throws {
        funnelState.markFirstSearchSubmission()
        
        XCTAssertTrue(funnelState.hasEverSubmittedSearch)
        XCTAssertEqual(mockStorage.store["FunnelState.hasEverSubmittedSearch"] as? Bool, true)
    }
    
    func testMarkFirstPromptSubmission() throws {
        funnelState.markFirstPromptSubmission()
        
        XCTAssertTrue(funnelState.hasEverSubmittedPrompt)
        XCTAssertEqual(mockStorage.store["FunnelState.hasEverSubmittedPrompt"] as? Bool, true)
    }
    
    func testMarkFullConversion() throws {
        funnelState.markFullConversion()
        
        XCTAssertTrue(funnelState.hasAchievedFullConversion)
        XCTAssertEqual(mockStorage.store["FunnelState.hasAchievedFullConversion"] as? Bool, true)
    }
    
    func testResetAllFunnelState() throws {
        funnelState.markFirstSettingsView()
        funnelState.markFirstFeatureEnable()
        funnelState.markFirstInteraction()
        funnelState.markFirstSearchSubmission()
        funnelState.markFirstPromptSubmission()
        funnelState.markFullConversion()
        
        funnelState.resetAllFunnelState()
        
        XCTAssertFalse(funnelState.hasEverViewedSettings)
        XCTAssertFalse(funnelState.hasEverEnabledFeature)
        XCTAssertFalse(funnelState.hasEverInteractedAfterEnable)
        XCTAssertFalse(funnelState.hasEverSubmittedSearch)
        XCTAssertFalse(funnelState.hasEverSubmittedPrompt)
        XCTAssertFalse(funnelState.hasAchievedFullConversion)
    }
    
    func testPersistenceAcrossInstances() throws {
        funnelState.markFirstSettingsView()
        funnelState.markFirstFeatureEnable()
        
        let newFunnelState = AIChatFunnelState(storage: mockStorage)
        
        XCTAssertTrue(newFunnelState.hasEverViewedSettings)
        XCTAssertTrue(newFunnelState.hasEverEnabledFeature)
        XCTAssertFalse(newFunnelState.hasEverInteractedAfterEnable)
    }

}
