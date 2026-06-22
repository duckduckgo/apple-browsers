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

import AppUpdaterShared
import Combine
import PersistenceTestingUtils
import PixelKit
import PixelKitTestingUtilities
import PrivacyConfig
import PrivacyConfigTestsUtils
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class AppStateRestorationManagerTests: XCTestCase {

    private var mockFileStore: FileStoreMock!
    private var mockService: StatePersistenceService!
    private var mockStartupPreferences: StartupPreferences!
    private var mockTabsPreferences: TabsPreferences!
    private var mockKeyValueStore: MockKeyValueFileStore!
    private var mockPromptCoordinator: SessionRestorePromptCoordinatorMock!
    private var appStateManager: AppStateRestorationManager!
    private var mockPixelKit: PixelKitMock!
    private var mockApplicationUpdateDetecting: MockApplicationUpdateDetecting!
    private var mockRestartSourceResolver: MockUncleanExitRestartSourceResolver!
    private let terminationFlagKey = "appDidTerminateAsExpected"

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        mockFileStore = FileStoreMock()
        mockService = StatePersistenceService(fileStore: mockFileStore, fileName: "test_persistent_state")
        let windowControllersManager = WindowControllersManagerMock()
        let persistor = MockStartupPreferencesPersistor()
        let appearancePreferences = AppearancePreferences(persistor: MockAppearancePreferencesPersistor(),
                                                          privacyConfigurationManager: MockPrivacyConfigurationManager(),
                                                          featureFlagger: MockFeatureFlagger(),
                                                          aiChatMenuConfig: MockAIChatConfig())
        mockStartupPreferences = StartupPreferences(pinningManager: MockPinningManager(), persistor: persistor, appearancePreferences: appearancePreferences)
        mockTabsPreferences = TabsPreferences(persistor: MockTabsPreferencesPersistor(), windowControllersManager: windowControllersManager)
        mockKeyValueStore = try MockKeyValueFileStore()
        mockPromptCoordinator = SessionRestorePromptCoordinatorMock()
        mockPixelKit = PixelKitMock()
        mockApplicationUpdateDetecting = MockApplicationUpdateDetecting()
        mockRestartSourceResolver = MockUncleanExitRestartSourceResolver()

        appStateManager = AppStateRestorationManager(
            fileStore: mockFileStore,
            service: mockService,
            startupPreferences: mockStartupPreferences,
            tabsPreferences: mockTabsPreferences,
            keyValueStore: mockKeyValueStore,
            sessionRestorePromptCoordinator: mockPromptCoordinator,
            applicationUpdateDetecting: mockApplicationUpdateDetecting,
            restartSourceResolver: mockRestartSourceResolver,
            pixelFiring: mockPixelKit
        )
    }

    override func tearDown() {
        appStateManager = nil
        mockApplicationUpdateDetecting = nil
        mockRestartSourceResolver = nil
        mockKeyValueStore = nil
        mockStartupPreferences = nil
        mockTabsPreferences = nil
        mockService = nil
        mockFileStore = nil
        mockPromptCoordinator = nil
        mockPixelKit = nil

        // Clean up UserDefaults to ensure test isolation
        UserDefaultsWrapper<Bool>.sharedDefaults.removeObject(forKey: UserDefaultsWrapper<Any>.Key.appIsRelaunchingAutomatically.rawValue)

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
    func testWhenAppDidTerminateUnexpectedly_ThenUnknownPixelIsFired() throws {
        try mockKeyValueStore.set(false, forKey: terminationFlagKey)
        mockRestartSourceResolver.resolvedSource = .unknown
        mockPixelKit.expectedFireCalls = [
            .init(pixel: SessionRestorePromptPixel.unexpectedAppTerminationDetected(reason: .unknown), frequency: .standard)
        ]

        appStateManager.applicationDidFinishLaunching()

        mockPixelKit.verifyExpectations()
    }

    @MainActor
    func testWhenAppDidTerminateUnexpectedlyAfterCrash_ThenCrashPixelIsFired() throws {
        try mockKeyValueStore.set(false, forKey: terminationFlagKey)
        mockRestartSourceResolver.resolvedSource = .crash
        mockPixelKit.expectedFireCalls = [
            .init(pixel: SessionRestorePromptPixel.unexpectedAppTerminationDetected(reason: .crash), frequency: .standard)
        ]

        appStateManager.applicationDidFinishLaunching()

        mockPixelKit.verifyExpectations()
    }

    @MainActor
    func testWhenAppDidTerminateUnexpectedlyAfterAppUpdate_ThenAppUpdatePixelIsFiredAndPromptIsShown() throws {
        try mockKeyValueStore.set(false, forKey: terminationFlagKey)
        mockRestartSourceResolver.resolvedSource = .appUpdate
        addMockSessionData()
        mockPixelKit.expectedFireCalls = [
            .init(pixel: SessionRestorePromptPixel.unexpectedAppTerminationDetected(reason: .appUpdate), frequency: .standard)
        ]

        appStateManager.applicationDidFinishLaunching()

        mockPixelKit.verifyExpectations()
        XCTAssertTrue(mockPromptCoordinator.sessionPromptShown)
    }

    @MainActor
    func testWhenAppDidTerminateUnexpectedlyAfterUnknownWithAppUpdate_ThenPixelIsFiredAndPromptIsShown() throws {
        try mockKeyValueStore.set(false, forKey: terminationFlagKey)
        mockRestartSourceResolver.resolvedSource = .unknownWithAppUpdate
        addMockSessionData()
        mockPixelKit.expectedFireCalls = [
            .init(pixel: SessionRestorePromptPixel.unexpectedAppTerminationDetected(reason: .unknownWithAppUpdate), frequency: .standard)
        ]

        appStateManager.applicationDidFinishLaunching()

        mockPixelKit.verifyExpectations()
        XCTAssertTrue(mockPromptCoordinator.sessionPromptShown)
    }

    @MainActor
    func testWhenAppDidTerminateUnexpectedly_ThenResolverReceivesUpdateStatusFromDetector() throws {
        try mockKeyValueStore.set(false, forKey: terminationFlagKey)
        mockApplicationUpdateDetecting.updateStatus = .updated
        mockRestartSourceResolver.resolvedSource = .appUpdate
        mockPixelKit.expectedFireCalls = [
            .init(pixel: SessionRestorePromptPixel.unexpectedAppTerminationDetected(reason: .appUpdate), frequency: .standard)
        ]

        appStateManager.applicationDidFinishLaunching()

        XCTAssertEqual(mockRestartSourceResolver.lastResolvedUpdateStatus, .updated)
        mockPixelKit.verifyExpectations()
    }

    @MainActor
    func testWhenTerminationFlagWriteFailsOnApplicationDidFinishLaunching_ThenDebugWritePixelIsFired() throws {
        try mockKeyValueStore.set(false, forKey: terminationFlagKey)
        mockRestartSourceResolver.resolvedSource = .unknown
        mockKeyValueStore.throwOnSet = MockError.error
        mockPixelKit.expectedFireCalls = [
            .init(pixel: DebugEvent(SessionRestorePromptPixel.appTerminationFlagWriteFailed, error: MockError.error), frequency: .standard),
            .init(pixel: SessionRestorePromptPixel.unexpectedAppTerminationDetected(reason: .unknown), frequency: .standard)
        ]

        appStateManager.applicationDidFinishLaunching()

        mockPixelKit.verifyExpectations()
    }

    @MainActor
    func testWhenAppDidNotTerminateUnexpectedly_ThenPixelIsNotFired() throws {
        try mockKeyValueStore.set(true, forKey: terminationFlagKey)

        appStateManager.applicationDidFinishLaunching()

        mockPixelKit.verifyExpectations()
    }

    @MainActor
    func testWhenTerminationFlagReadFails_ThenDebugReadPixelIsFiredAndPromptIsNotShown() throws {
        mockKeyValueStore.throwOnRead = MockError.error
        addMockSessionData()
        mockPixelKit.expectedFireCalls = [
            .init(pixel: DebugEvent(SessionRestorePromptPixel.appTerminationFlagReadFailed, error: MockError.error), frequency: .standard)
        ]

        appStateManager.applicationDidFinishLaunching()

        mockPixelKit.verifyExpectations()
        XCTAssertFalse(mockPromptCoordinator.sessionPromptShown)
    }

    @MainActor
    func testWhenTerminationFlagWriteFailsOnApplicationWillTerminate_ThenDebugWritePixelIsFired() throws {
        mockKeyValueStore.throwOnSet = MockError.error
        mockPixelKit.expectedFireCalls = [
            .init(pixel: DebugEvent(SessionRestorePromptPixel.appTerminationFlagWriteFailed, error: MockError.error), frequency: .standard)
        ]

        appStateManager.applicationWillTerminate()

        mockPixelKit.verifyExpectations()
    }

    // MARK: - Session Restored Pixel

    func testSessionRestoredPixel_HasExpectedName() {
        XCTAssertEqual(GeneralPixel.appStateRestored(trigger: .standard).name, "m_mac_session_restored")
    }

    func testSessionRestoredPixel_WhenStandardTrigger_ThenRestartToUpdateParamIsFalse() {
        XCTAssertEqual(GeneralPixel.appStateRestored(trigger: .standard).parameters, ["isRestartToUpdate": "false"])
    }

    func testSessionRestoredPixel_WhenAppUpdateTrigger_ThenRestartToUpdateParamIsTrue() {
        XCTAssertEqual(GeneralPixel.appStateRestored(trigger: .appUpdate).parameters, ["isRestartToUpdate": "true"])
    }

    // MARK: - Automatic Relaunch Tests

    @MainActor
    func testAppDidFinishLaunching_WhenRelaunchingAutomatically_ResetsRelaunchFlag() {
        // Given: Session restore preference is disabled
        mockStartupPreferences.restorePreviousSession = false

        // And: The app is relaunching automatically (e.g., after update)
        let defaults = UserDefaultsWrapper<Bool>.sharedDefaults
        defaults.set(true, forKey: UserDefaultsWrapper<Any>.Key.appIsRelaunchingAutomatically.rawValue)

        // And: There is session data to restore
        addMockSessionData()

        // When: App finishes launching
        appStateManager.applicationDidFinishLaunching()

        // Then: The automatic relaunch flag should be reset
        XCTAssertEqual(defaults.bool(forKey: UserDefaultsWrapper<Any>.Key.appIsRelaunchingAutomatically.rawValue), false)

        // Note: The actual tab restoration is verified through integration tests
        // since it requires the full WindowsManager stack to decode state properly
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

private final class MockApplicationUpdateDetecting: ApplicationUpdateDetecting {
    var updateStatus: AppUpdateStatus = .noChange

    func isApplicationUpdated(currentVersion: String?,
                              currentBuild: String?,
                              previousVersion: String?,
                              previousBuild: String?) -> AppUpdateStatus {
        updateStatus
    }
}

private final class MockUncleanExitRestartSourceResolver: UncleanExitRestartSourceResolving {
    var resolvedSource: UncleanExitRestartSource = .unknown
    private(set) var lastResolvedUpdateStatus: AppUpdateStatus?

    func captureSparklePendingUpdateSnapshot() {}

    func resolve(updateStatus: AppUpdateStatus) -> UncleanExitRestartSource {
        lastResolvedUpdateStatus = updateStatus
        return resolvedSource
    }
}

private class MockStartupPreferencesPersistor: StartupPreferencesPersistor {
    var restorePreviousSession: Bool = false
    var launchToCustomHomePage: Bool = false
    var customHomePageURL: String = ""
    var startupWindowType: StartupWindowType = .window
}
