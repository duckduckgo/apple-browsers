//
//  AutoClearServiceTests.swift
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

import Foundation
import Testing
@testable import DuckDuckGo
@testable import Core

final class MockAutoClear: AutoClearing {

    var isClearingEnabledValue = false
    var clearDataIfEnabledCalled = false
    var didTimeExpired = true
    var isClearingDueCalled = false
    var clearDataDueToTimeExpiredCalled = false
    var startClearingTimerCalled = false
    var lastLaunchingValue: Bool?
    var lastBaseTimeInterval: TimeInterval?

    var isClearingEnabled: Bool {
        isClearingEnabledValue
    }

    func clearDataIfEnabled(launching: Bool, applicationState: DataStoreWarmup.ApplicationState) async {
        clearDataIfEnabledCalled = true
        lastLaunchingValue = launching
    }

    var isClearingDue: Bool {
        isClearingDueCalled = true
        return didTimeExpired
    }

    func clearDataDueToTimeExpired(applicationState: DataStoreWarmup.ApplicationState) async {
        clearDataDueToTimeExpiredCalled = true
    }

    func startClearingTimer(_ time: TimeInterval) {
        startClearingTimerCalled = true
        lastBaseTimeInterval = time
    }

}

final class AutoClearServiceTests {

    var mockAutoClear: MockAutoClear!
    var mockOverlayWindowManager: MockOverlayWindowManager!

    init() {
        mockAutoClear = MockAutoClear()
        mockOverlayWindowManager = MockOverlayWindowManager()
    }

    @Test("autoClearService's init() should start clearing data")
    func clearDataOnInit() async {
        // When
        let autoClearService = AutoClearService(autoClear: mockAutoClear,
                                                overlayWindowManager: mockOverlayWindowManager)

        // Then
        await autoClearService.autoClearTask?.value
        #expect(mockAutoClear.clearDataIfEnabledCalled)
        #expect(mockAutoClear.lastLaunchingValue == true)
    }

    @Test("resume() should start clearing data")
    func resume() async {
        // Given
        let autoClearService = AutoClearService(autoClear: mockAutoClear,
                                                overlayWindowManager: mockOverlayWindowManager)

        // When
        autoClearService.resume()

        // Then
        await autoClearService.autoClearTask?.value
        #expect(mockAutoClear.isClearingDueCalled)
        #expect(mockAutoClear.clearDataDueToTimeExpiredCalled)
    }

    @Test("resume() should not start data clear but should remove overlay instead")
    func testResumeWithoutClearingWhenTimeThresholdNotMet() async {
        // Given
        mockAutoClear.didTimeExpired = false
        let autoClearService = AutoClearService(autoClear: mockAutoClear,
                                                overlayWindowManager: mockOverlayWindowManager)

        // When
        autoClearService.resume()

        // Then
        #expect(mockAutoClear.isClearingDueCalled)
        #expect(!mockAutoClear.clearDataDueToTimeExpiredCalled)
        #expect(mockOverlayWindowManager.removeNonAuthenticationOverlayCalled)
    }

    @Test("suspend() should display blank snapshot and should start clearing timer")
    func suspend() {
        // Given
        mockAutoClear.isClearingEnabledValue = true
        let autoClearService = AutoClearService(autoClear: mockAutoClear,
                                                overlayWindowManager: mockOverlayWindowManager)

        // When
        autoClearService.suspend()

        // Then
        #expect(mockOverlayWindowManager.displayBlankSnapshotWindowCalled)
        #expect(mockAutoClear.startClearingTimerCalled)
    }

    @Test("suspend() when clearing disabled should not display blank snapshot and should start clearing timer")
    func suspendWhenClearingDisabled() {
        // Given
        mockAutoClear.isClearingEnabledValue = false
        let autoClearService = AutoClearService(autoClear: mockAutoClear,
                                                overlayWindowManager: mockOverlayWindowManager)


        // When
        autoClearService.suspend()

        // Then
        #expect(!mockOverlayWindowManager.displayBlankSnapshotWindowCalled)
        #expect(mockAutoClear.startClearingTimerCalled)
    }

    @Test("waitForDataCleared() should remove non-authentication overlay")
    func waitForDataCleared() async {
        // Given
        let autoClearService = AutoClearService(autoClear: mockAutoClear,
                                                overlayWindowManager: mockOverlayWindowManager)

        // When
        await autoClearService.waitForDataCleared()

        // Then
        #expect(mockOverlayWindowManager.removeNonAuthenticationOverlayCalled)
    }

}
