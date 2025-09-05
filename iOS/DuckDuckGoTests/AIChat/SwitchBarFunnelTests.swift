//
//  SwitchBarFunnelTests.swift
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

final class SwitchBarFunnelTests: XCTestCase {
    
    var mockStorage: MockKeyValueStore!
    var switchBarFunnel: SwitchBarFunnel!

    override func setUpWithError() throws {
        mockStorage = MockKeyValueStore()
        switchBarFunnel = SwitchBarFunnel(storage: mockStorage)
    }

    override func tearDownWithError() throws {
        mockStorage = nil
        switchBarFunnel = nil
    }

    func testInitialStateAllFalse() throws {
        // Check that no steps are completed initially
        for step in SwitchBarFunnelStep.allCases {
            let stepCompleted = mockStorage.store[step.storageKey] as? Bool ?? false
            XCTAssertFalse(stepCompleted, "Step \(step) should not be completed initially")
        }
    }
    
    func testProcessStepWithoutDependencies() throws {
        // Try to process feature enabled without settings viewed dependency
        switchBarFunnel.processStep(.featureEnabled)
        
        let stepCompleted = mockStorage.store[SwitchBarFunnelStep.featureEnabled.storageKey] as? Bool ?? false
        XCTAssertFalse(stepCompleted, "Step should not complete without dependencies")
    }
    
    func testValidFunnelProgression() throws {
        // Process steps in correct order
        switchBarFunnel.processStep(.settingsViewed)
        XCTAssertTrue(mockStorage.store[SwitchBarFunnelStep.settingsViewed.storageKey] as? Bool ?? false)
        
        switchBarFunnel.processStep(.featureEnabled)
        XCTAssertTrue(mockStorage.store[SwitchBarFunnelStep.featureEnabled.storageKey] as? Bool ?? false)
        
        switchBarFunnel.processStep(.firstInteraction)
        XCTAssertTrue(mockStorage.store[SwitchBarFunnelStep.firstInteraction.storageKey] as? Bool ?? false)
        
        switchBarFunnel.processStep(.searchSubmitted)
        XCTAssertTrue(mockStorage.store[SwitchBarFunnelStep.searchSubmitted.storageKey] as? Bool ?? false)
        
        switchBarFunnel.processStep(.promptSubmitted)
        XCTAssertTrue(mockStorage.store[SwitchBarFunnelStep.promptSubmitted.storageKey] as? Bool ?? false)
        
        // Full conversion should be automatically triggered
        XCTAssertTrue(mockStorage.store[SwitchBarFunnelStep.fullConversion.storageKey] as? Bool ?? false)
    }
    
    func testResetAllFunnelState() throws {
        // Complete all steps
        switchBarFunnel.processStep(.settingsViewed)
        switchBarFunnel.processStep(.featureEnabled)
        switchBarFunnel.processStep(.firstInteraction)
        switchBarFunnel.processStep(.searchSubmitted)
        switchBarFunnel.processStep(.promptSubmitted)
        
        switchBarFunnel.resetAllFunnelState()
        
        // Check all steps are reset
        for step in SwitchBarFunnelStep.allCases {
            let stepCompleted = mockStorage.store[step.storageKey] as? Bool ?? false
            XCTAssertFalse(stepCompleted, "Step \(step) should be reset")
        }
    }
    
    func testPersistenceAcrossInstances() throws {
        switchBarFunnel.processStep(.settingsViewed)
        switchBarFunnel.processStep(.featureEnabled)
        
        let newSwitchBarFunnel = SwitchBarFunnel(storage: mockStorage)
        
        XCTAssertTrue(mockStorage.store[SwitchBarFunnelStep.settingsViewed.storageKey] as? Bool ?? false)
        XCTAssertTrue(mockStorage.store[SwitchBarFunnelStep.featureEnabled.storageKey] as? Bool ?? false)
        XCTAssertFalse(mockStorage.store[SwitchBarFunnelStep.firstInteraction.storageKey] as? Bool ?? false)
    }
    
    func testDuplicateStepProcessing() throws {
        // Process same step multiple times
        switchBarFunnel.processStep(.settingsViewed)
        switchBarFunnel.processStep(.settingsViewed)
        switchBarFunnel.processStep(.settingsViewed)
        
        // Should only be marked once
        XCTAssertEqual(mockStorage.store[SwitchBarFunnelStep.settingsViewed.storageKey] as? Bool, true)
    }

}
