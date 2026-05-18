//
//  PermissionCenterViewModelTests.swift
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

import Combine
import FeatureFlags
import PrivacyConfig
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// Tests for PermissionCenterViewModel filtering behavior.
final class PermissionCenterViewModelTests: XCTestCase {

    var mockPermissionManager: PermissionManagerMock!
    var mockSystemPermissionManager: MockSystemPermissionManager!
    var mockFeatureFlagger: MockFeatureFlagger!
    var autoplayPreferences: AutoplayPreferences!

    override func setUp() {
        super.setUp()
        mockPermissionManager = PermissionManagerMock()
        mockSystemPermissionManager = MockSystemPermissionManager()
        mockFeatureFlagger = MockFeatureFlagger()
        autoplayPreferences = AutoplayPreferences()
    }

    override func tearDown() {
        mockPermissionManager = nil
        mockSystemPermissionManager = nil
        mockFeatureFlagger = nil
        autoplayPreferences = nil
        super.tearDown()
    }

    /// Tests that notification permissions appear in the permission items list.
    func testNotificationPermissionsAppearInUI() {
        // Create permissions including notification
        var usedPermissions = Permissions()
        usedPermissions[.camera] = .active
        usedPermissions[.notification] = .active
        usedPermissions[.microphone] = .active

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: usedPermissions,
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        // Verify notification is in the items
        let permissionTypes = viewModel.permissionItems.map { $0.permissionType }
        XCTAssertTrue(permissionTypes.contains(.notification), "Notification should appear in UI")
        XCTAssertTrue(permissionTypes.contains(.camera), "Camera should be present")
        XCTAssertTrue(permissionTypes.contains(.microphone), "Microphone should be present")
    }

    /// Tests that notification permissions work alongside other permissions.
    func testNotificationPermissionsWorkAlongsideOtherPermissions() {
        var usedPermissions = Permissions()
        usedPermissions[.camera] = .active
        usedPermissions[.notification] = .active
        usedPermissions[.geolocation] = .active

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: usedPermissions,
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        XCTAssertEqual(viewModel.permissionItems.count, 3, "Should show all three permissions")
        let types = viewModel.permissionItems.map { $0.permissionType }
        XCTAssertTrue(types.contains(.notification))
        XCTAssertTrue(types.contains(.camera))
        XCTAssertTrue(types.contains(.geolocation))
    }

    // MARK: - requestSystemPermission Tests

    /// Verifies requestSystemPermission calls the system permission manager with correct permission type.
    func testWhenRequestSystemPermissionCalledThenSystemManagerRequestsAuthorization() {
        var usedPermissions = Permissions()
        usedPermissions[.notification] = .active

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: usedPermissions,
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        viewModel.requestSystemPermission(for: .notification)

        XCTAssertTrue(mockSystemPermissionManager.requestAuthorizationCalled)
        XCTAssertEqual(mockSystemPermissionManager.lastRequestedPermissionType, .notification)
    }

    /// Verifies permission item's systemAuthorizationState updates after authorization request completes.
    func testWhenSystemPermissionGrantedThenPermissionItemStateUpdates() async throws {
        mockSystemPermissionManager.authorizationStateToReturn = .notDetermined

        var usedPermissions = Permissions()
        usedPermissions[.notification] = .active

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: usedPermissions,
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        // Change the state that will be returned after request
        mockSystemPermissionManager.authorizationStateToReturn = .authorized

        viewModel.requestSystemPermission(for: .notification)

        // Wait for async state update
        try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)

        // Find the notification item and verify its system state was updated
        let notificationItem = viewModel.permissionItems.first { $0.permissionType == .notification }
        XCTAssertEqual(notificationItem?.systemAuthorizationState, .authorized)
    }
    // MARK: - Autoplay Row Visibility Tests

    func testWhenDisplayAutoplayPolicyIsEnabledThenAutoplayRowAppearsInPermissionItems() {
        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            displaysAutoplayPolicy: true,
            systemPermissionManager: mockSystemPermissionManager
        )

        let types = viewModel.permissionItems.map { $0.permissionType }
        XCTAssertTrue(types.contains(.autoplayPolicy), "Autoplay row should appear when feature flag is on")
    }

    func testWhenDisplaysAutoplayPolicyIsDisabledThenAutoplayRowDoesNotAppear() {
        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            displaysAutoplayPolicy: false,
            systemPermissionManager: mockSystemPermissionManager
        )

        let types = viewModel.permissionItems.map { $0.permissionType }
        XCTAssertFalse(types.contains(.autoplayPolicy), "Autoplay row should not appear when feature flag is off")
    }

    // MARK: - currentAutoplayDecision Tests

    func testWhenNoOverrideAndGlobalBlockAudioThenCurrentDecisionIsAudioMuted() {
        let persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: AutoplayBlockingMode.blockAudio.rawValue)
        let autoplayPreferences = AutoplayPreferences(persistor: persistor)

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        XCTAssertEqual(viewModel.currentAutoplayDecision(), .audioMuted)
    }

    func testWhenNoOverrideThenCurrentDecisionMatchesGlobalPreference() {
        let cases: [(AutoplayBlockingMode, AutoplayDecision)] = [
            (.blockAudio, .audioMuted),
            (.allowAll, .allowAll),
            (.blockAll, .blockAll),
        ]

        for (blockingMode, expectedDecision) in cases {
            let persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: blockingMode.rawValue)
            let autoplayPreferences = AutoplayPreferences(persistor: persistor)

            let viewModel = PermissionCenterViewModel(
                domain: "example.com",
                usedPermissions: Permissions(),
                permissionManager: mockPermissionManager,
                autoplayPreferences: autoplayPreferences,
                featureFlagger: mockFeatureFlagger,
                removePermission: { _ in },
                dismissPopover: { },
                systemPermissionManager: mockSystemPermissionManager
            )

            XCTAssertEqual(viewModel.currentAutoplayDecision(), expectedDecision, "Global \(blockingMode) should map to \(expectedDecision)")
        }
    }

    func testWhenAutoplayAllowPersistedThenCurrentDecisionIsAllowAll() {
        mockPermissionManager.setPermission(.allow, forDomain: "example.com", permissionType: .autoplayPolicy)

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        XCTAssertEqual(viewModel.currentAutoplayDecision(), .allowAll)
    }

    func testWhenAutoplayDenyPersistedThenCurrentDecisionIsBlockAll() {
        mockPermissionManager.setPermission(.deny, forDomain: "example.com", permissionType: .autoplayPolicy)

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        XCTAssertEqual(viewModel.currentAutoplayDecision(), .blockAll)
    }

    func testWhenAutoplayAskPersistedThenCurrentDecisionIsAudioMuted() {
        mockPermissionManager.setPermission(.ask, forDomain: "example.com", permissionType: .autoplayPolicy)

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        XCTAssertEqual(viewModel.currentAutoplayDecision(), .audioMuted)
    }

    // MARK: - setAutoplayDecision Tests

    func testWhenSetAutoplayDecisionThenCorrectPermissionIsStored() {
        let cases: [(AutoplayDecision, PersistedPermissionDecision)] = [
            (.allowAll, .allow),
            (.audioMuted, .ask),
            (.blockAll, .deny),
        ]

        for (decision, expectedPermission) in cases {
            mockPermissionManager = PermissionManagerMock()

            let viewModel = PermissionCenterViewModel(
                domain: "example.com",
                usedPermissions: Permissions(),
                permissionManager: mockPermissionManager,
                autoplayPreferences: autoplayPreferences,
                featureFlagger: mockFeatureFlagger,
                removePermission: { _ in },
                dismissPopover: { },
                systemPermissionManager: mockSystemPermissionManager
            )

            viewModel.setAutoplayDecision(decision)

            XCTAssertEqual(mockPermissionManager.permission(forDomain: "example.com", permissionType: .autoplayPolicy), expectedPermission, "Setting \(decision) should store \(expectedPermission)")
        }
    }

    func testWhenSetAutoplayDecisionWithSameValueAlreadyPersistedThenNoOp() {
        mockPermissionManager.setPermission(.deny, forDomain: "example.com", permissionType: .autoplayPolicy)
        mockPermissionManager.setPermissionCalls.removeAll()

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        viewModel.setAutoplayDecision(.blockAll)

        XCTAssertTrue(mockPermissionManager.setPermissionCalls.isEmpty, "Should not re-persist when value and persisted state are unchanged")
        XCTAssertFalse(viewModel.showReloadBanner, "Reload banner should not show when nothing changed")
    }

    func testWhenSetAutoplayDecisionWithSameValueButNotPersistedThenPersists() {
        // mockPermissionManager has no persisted autoplay permission.
        // Its default return from permission(forDomain:permissionType:) is .ask,
        // which matches .audioMuted's permissionDecision.
        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        viewModel.setAutoplayDecision(.audioMuted)

        XCTAssertEqual(mockPermissionManager.permission(forDomain: "example.com", permissionType: .autoplayPolicy), .ask,
                       "Should persist the decision even when it matches the default value")
        XCTAssertTrue(viewModel.showReloadBanner, "Reload banner should show for a newly persisted override")
    }

    func testWhenSetAutoplayDecisionThenReloadBannerIsShown() {
        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        viewModel.setAutoplayDecision(.blockAll)

        XCTAssertTrue(viewModel.showReloadBanner, "Reload banner should be shown after changing autoplay decision")
    }

    // MARK: - aiChatNativeVoicePermissionFlow flag

    /// On duck.ai with the flag on, mic rows are stripped from the Permission Center entirely
    /// (the override masks any edits, and the OS-denied remediation surface lives in
    /// `SystemDisabledPermissionInfoView` anchored to the shield, not in this list).
    func testWhenFlagOn_andMicrophoneOnDuckAi_andOSDenied_thenNoMicRowAppears() {
        mockFeatureFlagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true
        mockSystemPermissionManager.authorizationStateToReturn = .denied

        let viewModel = PermissionCenterViewModel(
            domain: "duck.ai",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        XCTAssertFalse(viewModel.permissionItems.contains(where: { $0.permissionType == .microphone }))
    }

    /// With the flag off, mic items behave like any other site: regular row, no special
    /// system-disabled surfacing for duck.ai.
    func testWhenFlagOff_thenMicrophoneSystemAuthorizationStateStaysNil() {
        mockFeatureFlagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = false
        mockSystemPermissionManager.authorizationStateToReturn = .denied
        var usedPermissions = Permissions()
        usedPermissions[.microphone] = .active

        let viewModel = PermissionCenterViewModel(
            domain: "duck.ai",
            usedPermissions: usedPermissions,
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        let micItem = viewModel.permissionItems.first { $0.permissionType == .microphone }
        XCTAssertNil(micItem?.systemAuthorizationState,
                     "Flag off → no special duck.ai handling, no async probe → state stays nil")
    }

    // MARK: - Row visibility on duck.ai

    /// On duck.ai with the flag on, mic is removed from the row pipeline regardless of OS
    /// state. The Permission Center is not the surface for OS-denied remediation any more
    /// (that lives in `SystemDisabledPermissionInfoView`), so no mic row appears here.
    func testWhenFlagOn_duckAiMic_osAuthorized_rowIsHidden() {
        mockFeatureFlagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true
        mockSystemPermissionManager.authorizationStateToReturn = .authorized
        var usedPermissions = Permissions()
        usedPermissions[.microphone] = .active

        let viewModel = PermissionCenterViewModel(
            domain: "duck.ai",
            usedPermissions: usedPermissions,
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        XCTAssertFalse(viewModel.permissionItems.contains(where: { $0.permissionType == .microphone }))
    }

    /// `.systemDisabled` is unreachable for microphone today (AVCaptureDevice never returns
    /// it for audio), but the switch is exhaustive so we cover the case. Treated like
    /// `.authorized` — nothing actionable in the row, so it's hidden.
    func testWhenFlagOn_duckAiMic_osSystemDisabled_rowIsHidden() {
        mockFeatureFlagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true
        mockSystemPermissionManager.authorizationStateToReturn = .systemDisabled
        var usedPermissions = Permissions()
        usedPermissions[.microphone] = .active

        let viewModel = PermissionCenterViewModel(
            domain: "duck.ai",
            usedPermissions: usedPermissions,
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        XCTAssertFalse(viewModel.permissionItems.contains(where: { $0.permissionType == .microphone }))
    }

    /// `.notDetermined` means the OS hasn't been asked yet — the OS prompt will fire
    /// naturally on first mic use, so we shouldn't pre-emptively show a "System Settings"
    /// row that wouldn't help.
    func testWhenFlagOn_duckAiMic_osNotDetermined_rowIsHidden() {
        mockFeatureFlagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true
        mockSystemPermissionManager.authorizationStateToReturn = .notDetermined
        var usedPermissions = Permissions()
        usedPermissions[.microphone] = .active

        let viewModel = PermissionCenterViewModel(
            domain: "duck.ai",
            usedPermissions: usedPermissions,
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        XCTAssertFalse(viewModel.permissionItems.contains(where: { $0.permissionType == .microphone }))
    }

    func testWhenFlagOn_duckAiMic_osRestricted_rowIsHidden() {
        mockFeatureFlagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true
        mockSystemPermissionManager.authorizationStateToReturn = .restricted
        var usedPermissions = Permissions()
        usedPermissions[.microphone] = .active

        let viewModel = PermissionCenterViewModel(
            domain: "duck.ai",
            usedPermissions: usedPermissions,
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        XCTAssertFalse(viewModel.permissionItems.contains(where: { $0.permissionType == .microphone }))
    }

    // MARK: - Duck.ai-only scoping (non-duck.ai sites unaffected)

    /// The voice-chat flag's mic-row stripping is scoped to duck.ai. Other sites with
    /// persisted or in-use mic permission must keep their regular editable row — otherwise
    /// we'd silently hide controls on unrelated sites like zoom.us.
    func testWhenFlagOn_otherDomainMic_osDenied_micRowStaysVisibleAsRegular() {
        mockFeatureFlagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true
        mockSystemPermissionManager.authorizationStateToReturn = .denied
        var usedPermissions = Permissions()
        usedPermissions[.microphone] = .active

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: usedPermissions,
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        let micItem = viewModel.permissionItems.first { $0.permissionType == .microphone }
        XCTAssertNotNil(micItem)
        XCTAssertNil(micItem?.systemAuthorizationState,
                     "Non-duck.ai sites must not have systemAuthorizationState populated for mic")
    }

    // MARK: - Legacy persisted entries do not leak an editable row

    /// Pre-existing duck.ai/mic decisions (from before the override existed) are masked at
    /// the read layer. The view model must additionally filter them out of the persisted
    /// path so the user never sees an editable row whose changes are silently ignored.
    func testWhenFlagOn_duckAiMic_legacyDenyPersisted_andOSAuthorized_thenNoMicRowAppears() {
        mockFeatureFlagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true
        mockSystemPermissionManager.authorizationStateToReturn = .authorized
        // Legacy entry that the override now shadows.
        mockPermissionManager.savedPermissions["duck.ai"] = [.microphone: .deny]

        let viewModel = PermissionCenterViewModel(
            domain: "duck.ai",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        XCTAssertFalse(viewModel.permissionItems.contains(where: { $0.permissionType == .microphone }),
                       "Legacy persisted entries must not produce a row that lets the user toggle a masked decision")
    }

    /// With the flag *off*, legacy persisted entries still surface as regular rows so users
    /// retain control. The filter only kicks in when the override is actually in effect.
    func testWhenFlagOff_duckAiMic_legacyDenyPersisted_thenRegularRowAppears() {
        mockFeatureFlagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = false
        mockPermissionManager.savedPermissions["duck.ai"] = [.microphone: .deny]

        let viewModel = PermissionCenterViewModel(
            domain: "duck.ai",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        let micItem = viewModel.permissionItems.first { $0.permissionType == .microphone }
        XCTAssertNotNil(micItem,
                        "Flag off → no override, the legacy decision surfaces as a regular row")
    }

    /// Non-duck.ai sites with mic permission keep their existing UX regardless of OS state.
    func testWhenFlagOn_otherDomainMic_osAuthorized_rowIsVisibleNormally() {
        mockFeatureFlagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true
        mockSystemPermissionManager.authorizationStateToReturn = .authorized
        var usedPermissions = Permissions()
        usedPermissions[.microphone] = .active

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: usedPermissions,
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        XCTAssertTrue(viewModel.permissionItems.contains(where: { $0.permissionType == .microphone }))
    }
}

// MARK: - Mock System Permission Manager

final class MockSystemPermissionManager: SystemPermissionManagerProtocol {

    var authorizationStateToReturn: SystemPermissionAuthorizationState = .authorized
    private(set) var requestAuthorizationCalled = false
    private(set) var lastRequestedPermissionType: PermissionType?

    func authorizationState(for permissionType: PermissionType) async -> SystemPermissionAuthorizationState {
        return authorizationStateToReturn
    }

    func cachedAuthorizationState(for permissionType: PermissionType) -> SystemPermissionAuthorizationState {
        return authorizationStateToReturn
    }

    func isAuthorizationRequired(for permissionType: PermissionType) -> Bool {
        return false
    }

    func requestAuthorization(for permissionType: PermissionType, completion: @escaping (SystemPermissionAuthorizationState) -> Void) -> AnyCancellable? {
        requestAuthorizationCalled = true
        lastRequestedPermissionType = permissionType
        completion(authorizationStateToReturn)
        return nil
    }
}
