//
//  AutoClearTests.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
@testable import Core
import BrowserServicesKit

@MainActor
class AutoClearTests: XCTestCase {
    
    class MockFireExecutor: FireExecuting {
        
        var burnCallCount = 0
        var burnRequest: FireRequest?
        var burnApplicationState: DataStoreWarmup.ApplicationState?
        
        weak var delegate: FireExecutorDelegate?
        
        func prepare(for request: FireRequest) { }
        
        func burn(request: FireRequest,
                  applicationState: DataStoreWarmup.ApplicationState) async {
            burnCallCount += 1
            burnRequest = request
            burnApplicationState = applicationState
        }
    }
    
    private var mockFireExecutor: MockFireExecutor!
    private var appSettings: AppSettingsMock!
    private var mockDataClearingCapability: MockDataClearingCapability!

    override func setUp() {
        super.setUp()
        mockFireExecutor = MockFireExecutor()
        appSettings = AppSettingsMock()
        mockDataClearingCapability = MockDataClearingCapability()
        // Enable enhanced UI by default to prevent auto-injection of AI chats
        mockDataClearingCapability.isEnhancedDataClearingEnabled = true
    }

    override func tearDown() {
        mockFireExecutor = nil
        appSettings = nil
        mockDataClearingCapability = nil
        super.tearDown()
    }

    // Note: applicationDidLaunch based clearing has moved to "configureTabManager" function of
    //  MainViewController to ensure that tabs are removed before the data is cleared.

    func testWhenTimingIsSetToTerminationThenOnlyRestartClearsData() async {
        let logic = AutoClear(worker: mockFireExecutor, appSettings: appSettings, dataClearingCapability: mockDataClearingCapability)

        appSettings.autoClearAction = .data
        appSettings.autoClearTiming = .termination
        
        await logic.clearDataDueToTimeExpired(applicationState: .unknown)
        logic.startClearingTimer()

        XCTAssertFalse(logic.isClearingDue)
    }
    
    func testWhenDesiredTimingIsSetThenDataIsClearedOnceTimeHasElapsed() async {
        let logic = AutoClear(worker: mockFireExecutor, appSettings: appSettings, dataClearingCapability: mockDataClearingCapability)

        appSettings.autoClearAction = .data
        
        let cases: [AutoClearSettingsModel.Timing: TimeInterval] = [.delay5min: 5 * 60,
                                                                    .delay15min: 15 * 60,
                                                                    .delay30min: 30 * 60,
                                                                    .delay60min: 60 * 60]
        
        for (timing, delay) in cases {
            appSettings.autoClearTiming = timing
            
            logic.startClearingTimer(Date().timeIntervalSince1970 - delay + 1)
            XCTAssertFalse(logic.isClearingDue)
            logic.startClearingTimer(Date().timeIntervalSince1970 - delay - 1)
            XCTAssertTrue(logic.isClearingDue)
        }
    }

    // MARK: - clearDataIfEnabled Tests
    
    func testClearDataIfEnabledCallsWorkerBurn() async {
        // Given
        let logic = AutoClear(worker: mockFireExecutor, appSettings: appSettings, dataClearingCapability: mockDataClearingCapability)
        appSettings.autoClearAction = .data
        appSettings.autoClearTiming = .delay15min
        
        // When
        await logic.clearDataIfEnabled(launching: false, applicationState: .active)

        // Then
        XCTAssertEqual(mockFireExecutor.burnCallCount, 1)
        XCTAssertEqual(mockFireExecutor.burnApplicationState, .active)
        XCTAssertEqual(mockFireExecutor.burnRequest?.trigger, .autoClearOnForeground)
    }
    
    func testClearDataIfEnabledWithLaunchingUsesAutoClearOnLaunchContext() async {
        // Given
        let logic = AutoClear(worker: mockFireExecutor, appSettings: appSettings, dataClearingCapability: mockDataClearingCapability)
        appSettings.autoClearAction = .data
        appSettings.autoClearTiming = .delay15min
        
        // When
        await logic.clearDataIfEnabled(launching: true, applicationState: .active)

        // Then
        XCTAssertEqual(mockFireExecutor.burnRequest?.trigger, .autoClearOnLaunch)
    }
    
    func testClearDataIfEnabledDoesNothingWhenAutoClearDisabled() async {
        // Given
        let logic = AutoClear(worker: mockFireExecutor, appSettings: appSettings, dataClearingCapability: mockDataClearingCapability)
        appSettings.autoClearAction = [] // Disabled
        
        // When
        await logic.clearDataIfEnabled(launching: false, applicationState: .active)

        // Then
        XCTAssertEqual(mockFireExecutor.burnCallCount, 0)
    }

    // MARK: - clearDataDueToTimeExpired Tests
    
    func testClearDataDueToTimeExpiredCallsWorkerBurn() async {
        // Given
        let logic = AutoClear(worker: mockFireExecutor, appSettings: appSettings, dataClearingCapability: mockDataClearingCapability)
        appSettings.autoClearAction = .data
        appSettings.autoClearTiming = .delay15min
        
        // When
        await logic.clearDataDueToTimeExpired(applicationState: .active)

        // Then
        XCTAssertEqual(mockFireExecutor.burnCallCount, 1)
        XCTAssertEqual(mockFireExecutor.burnRequest?.trigger, .autoClearOnForeground)
    }

}
