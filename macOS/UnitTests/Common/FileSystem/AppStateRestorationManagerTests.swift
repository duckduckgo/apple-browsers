//
//  AppStateRestorationManagerTests.swift
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
import Combine
import PersistenceTestingUtils
import PixelKitTestingUtilities
@testable import DuckDuckGo_Privacy_Browser

final class AppStateRestorationManagerTests: XCTestCase {

    private var mockFileStore: FileStoreMock!
    private var mockService: StatePersistenceService!
    private var mockStartupPreferences: StartupPreferences!
    private var mockKeyValueStore: MockKeyValueFileStore!
    private var mockPromptCoordinator: SessionRestorePromptCoordinatorMock!
    private var appStateManager: AppStateRestorationManager!
    private var mockPixelKit: PixelKitMock!
    private let terminationFlagKey = "appDidTerminateAsExpected"

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        mockFileStore = FileStoreMock()
        mockService = StatePersistenceService(fileStore: mockFileStore, fileName: "test_persistent_state")
        let persistor = MockStartupPreferencesPersistor()
        let appearancePreferences = AppearancePreferences(persistor: MockAppearancePreferencesPersistor(), privacyConfigurationManager: MockPrivacyConfigurationManager(), featureFlagger: MockFeatureFlagger())
        mockStartupPreferences = StartupPreferences(persistor: persistor, appearancePreferences: appearancePreferences)
        mockKeyValueStore = try MockKeyValueFileStore()
        mockPromptCoordinator = SessionRestorePromptCoordinatorMock()
        mockPixelKit = PixelKitMock()

        appStateManager = AppStateRestorationManager(
            fileStore: mockFileStore,
            service: mockService,
            startupPreferences: mockStartupPreferences,
            keyValueStore: mockKeyValueStore,
            sessionRestorePromptCoordinator: mockPromptCoordinator,
            pixelFiring: mockPixelKit
        )
    }

    override func tearDown() {
        appStateManager = nil
        mockKeyValueStore = nil
        mockStartupPreferences = nil
        mockService = nil
        mockFileStore = nil
        mockPromptCoordinator = nil
        mockPixelKit = nil
        super.tearDown()
    }

    // MARK: - Session Restore Prompt Tests

    @MainActor
    func testAppDidFinishLaunching_WhenAppTerminatedAsExpected_DoesNotShowPrompt() throws {
        try mockKeyValueStore.set(true, forKey: terminationFlagKey)
        addMockSessionData()

        appStateManager.applicationDidFinishLaunching()

        XCTAssertFalse(mockPromptCoordinator.sessionPromptShown)
    }

    @MainActor
    func testAppDidFinishLaunching_WhenAppCrashedAndAllConditionsMet_ShowsPrompt() throws {
        try mockKeyValueStore.set(false, forKey: terminationFlagKey)
        addMockSessionData()

        appStateManager.applicationDidFinishLaunching()

        XCTAssertTrue(mockPromptCoordinator.sessionPromptShown)
    }

    @MainActor
    func testAppDidFinishLaunching_WhenAppCrashedButRestoreSessionEnabled_DoesNotShowPrompt() throws {
        try mockKeyValueStore.set(false, forKey: terminationFlagKey)
        mockStartupPreferences.restorePreviousSession = true
        addMockSessionData()

        appStateManager.applicationDidFinishLaunching()

        XCTAssertFalse(mockPromptCoordinator.sessionPromptShown)
    }

    @MainActor
    func testAppDidFinishLaunching_WhenAppCrashedButCannotRestoreSession_DoesNotShowPrompt() throws {
        try mockKeyValueStore.set(false, forKey: terminationFlagKey)

        appStateManager.applicationDidFinishLaunching()

        XCTAssertFalse(mockPromptCoordinator.sessionPromptShown)
    }

    @MainActor
    func testAppDidFinishLaunching_WhenAppCrashedButStateIsStale_DoesNotShowPrompt() throws {
        try mockKeyValueStore.set(false, forKey: terminationFlagKey)
        addStaleMockSessionData()

        appStateManager.applicationDidFinishLaunching()

        XCTAssertFalse(mockPromptCoordinator.sessionPromptShown)
    }

    @MainActor
    func testAppDidFinishLaunching_WhenKeyValueStoreIsEmpty_DoesNotShowPrompt() throws {
        try mockKeyValueStore.removeObject(forKey: terminationFlagKey)
        addMockSessionData()

        appStateManager.applicationDidFinishLaunching()

        XCTAssertFalse(mockPromptCoordinator.sessionPromptShown)
    }

    @MainActor
    func testAppDidFinishLaunching_SetsTerminationFlagToFalse() throws {
        try mockKeyValueStore.set(true, forKey: terminationFlagKey)

        appStateManager.applicationDidFinishLaunching()

        XCTAssertEqual(try mockKeyValueStore.object(forKey: terminationFlagKey) as? Bool, false)
    }

    @MainActor
    func testAppWillTerminate_SetsTerminationFlagToTrue() throws {
        try mockKeyValueStore.set(false, forKey: terminationFlagKey)

        appStateManager.applicationWillTerminate()

        XCTAssertEqual(try mockKeyValueStore.object(forKey: terminationFlagKey) as? Bool, true)
    }

    @MainActor
    func testAppWillTerminate_NotifiesPromptCoordinator() throws {
        appStateManager.applicationWillTerminate()

        XCTAssertTrue(mockPromptCoordinator.applicationWillTerminateCalled)
    }

    // MARK: - Error Handling Tests

    @MainActor
    func testKeyValueStoreReadError_DoesNotCrash() throws {
        // Given: Key value store throws an error on read
        mockKeyValueStore.throwOnRead = MockError.error

        // When: App finishes launching (which reads the flag)
        // Then: No crash occurs
        XCTAssertNoThrow {
            self.appStateManager.applicationDidFinishLaunching()
        }
    }

    @MainActor
    func testKeyValueStoreWriteError_DoesNotCrash() throws {
        // Given: Key value store throws an error on write
        mockKeyValueStore.throwOnSet = MockError.error

        // When: App will terminate (which writes the flag)
        // Then: No crash occurs
        XCTAssertNoThrow {
            self.appStateManager.applicationWillTerminate()
        }
    }

    // MARK: - Pixels

    @MainActor
    func testWhenAppDidTerminateUnexpectedly_ThenPixelIsFired() throws {
        try mockKeyValueStore.set(false, forKey: terminationFlagKey)
        mockPixelKit.expectedFireCalls = [.init(pixel: SessionRestorePromptPixel.unexpectedAppTerminationDetected, frequency: .standard)]

        appStateManager.applicationDidFinishLaunching()

        mockPixelKit.verifyExpectations()
    }

    @MainActor
    func testWhenAppDidNotTerminateUnexpectedly_ThenPixelIsNotFired() throws {
        try mockKeyValueStore.set(true, forKey: terminationFlagKey)

        appStateManager.applicationDidFinishLaunching()

        mockPixelKit.verifyExpectations()
    }

    private func addMockSessionData() {
        // Add some mock data to make canRestoreLastSessionState return true
        let mockData = Data("mock session data".utf8)
        mockFileStore.storage["test_persistent_state"] = mockData
        mockService.loadLastSessionState()
    }

    private func addStaleMockSessionData() {
        addMockSessionData()
        mockService.didLoadState()
        mockService.loadLastSessionState()
        mockService.didLoadState()
    }
}

// MARK: - Mock Helpers

private enum MockError: Error {
    case error
}

private class MockStartupPreferencesPersistor: StartupPreferencesPersistor {
    var restorePreviousSession: Bool = false
    var launchToCustomHomePage: Bool = false
    var customHomePageURL: String = ""
    var startupWindowType: StartupWindowType = .window
}
