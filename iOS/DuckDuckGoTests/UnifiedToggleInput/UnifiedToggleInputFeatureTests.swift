//
//  UnifiedToggleInputFeatureTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import UIKit
import XCTest
@testable import DuckDuckGo
@testable import Core

final class UnifiedToggleInputFeatureTests: XCTestCase {

    // MARK: - Mocks

    private final class MockDevicePlatform: DevicePlatformProviding {
        static var isIphone: Bool = false
    }

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        UnifiedToggleInputFeature.resolve(using: MockFeatureFlagger(enabledFeatureFlags: []))
        MockDevicePlatform.isIphone = false
    }

    override func tearDown() {
        UnifiedToggleInputFeature.resolve(using: MockFeatureFlagger(enabledFeatureFlags: []))
        MockDevicePlatform.isIphone = false
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeFeature(flagEnabled: Bool, isIphone: Bool) -> UnifiedToggleInputFeature {
        MockDevicePlatform.isIphone = isIphone
        let flags: [FeatureFlag] = flagEnabled ? [.unifiedToggleInput] : []
        UnifiedToggleInputFeature.resolve(using: MockFeatureFlagger(enabledFeatureFlags: flags))
        return UnifiedToggleInputFeature(devicePlatform: MockDevicePlatform.self)
    }

    // MARK: - Tests

    func test_isAvailable_whenFlagOnAndIphone() {
        XCTAssertTrue(makeFeature(flagEnabled: true, isIphone: true).isAvailable)
    }

    func test_isNotAvailable_whenFlagOnButNotIphone() {
        XCTAssertFalse(makeFeature(flagEnabled: true, isIphone: false).isAvailable)
    }

    func test_isNotAvailable_whenFlagOffButIphone() {
        XCTAssertFalse(makeFeature(flagEnabled: false, isIphone: true).isAvailable)
    }

    func test_isNotAvailable_whenFlagOffAndNotIphone() {
        XCTAssertFalse(makeFeature(flagEnabled: false, isIphone: false).isAvailable)
    }

    // MARK: - Snapshot semantics

    /// Mid-session flag flips must not change availability. Resolve writes the launch-time flag
    /// value into UserDefaults, while readers still apply the device availability gate.
    func test_isAvailable_usesLaunchResolvedFlagSnapshot() {
        MockDevicePlatform.isIphone = true
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.unifiedToggleInput])
        UnifiedToggleInputFeature.resolve(using: flagger)
        let feature = UnifiedToggleInputFeature(devicePlatform: MockDevicePlatform.self)
        XCTAssertTrue(feature.isAvailable, "Precondition: availability is ON after resolve")

        flagger.enabledFeatureFlags = []
        XCTAssertFalse(flagger.isFeatureOn(.unifiedToggleInput),
                       "Sanity: the live flagger now reports the flag as off")
        XCTAssertTrue(feature.isAvailable,
                      "Snapshot must ignore the post-resolve mutation on the same instance")
        XCTAssertTrue(UnifiedToggleInputFeature(devicePlatform: MockDevicePlatform.self).isAvailable,
                      "A fresh instance must read the same snapshot, not the mutated live flagger")

        UnifiedToggleInputFeature.resolve(using: flagger)
        XCTAssertFalse(feature.isAvailable,
                       "After re-resolving the snapshot must flip — otherwise resolve isn't doing its job")
    }
}

final class AIChatTabChatHeaderNavigationStateTests: XCTestCase {

    func test_displayedAvailability_usesLockedAvailabilityUntilLockClears() {
        var state = AIChatTabChatHeaderNavigationState()
        let preTapAvailability = AIChatTabChatHeaderNavigationAvailability(canGoBack: true, canGoForward: false)
        let webKitAvailabilityAfterBackTap = AIChatTabChatHeaderNavigationAvailability(canGoBack: false, canGoForward: true)

        state.lockAvailability(for: "tab-1", availability: preTapAvailability)

        XCTAssertEqual(
            state.displayedAvailability(for: "tab-1", currentAvailability: webKitAvailabilityAfterBackTap),
            preTapAvailability
        )

        XCTAssertTrue(state.clearLock(for: "tab-1"))
        XCTAssertEqual(
            state.displayedAvailability(for: "tab-1", currentAvailability: webKitAvailabilityAfterBackTap),
            webKitAvailabilityAfterBackTap
        )
    }

    func test_displayedAvailability_clearsLockWhenTabChanges() {
        var state = AIChatTabChatHeaderNavigationState()
        let lockedAvailability = AIChatTabChatHeaderNavigationAvailability(canGoBack: true, canGoForward: false)
        let currentAvailability = AIChatTabChatHeaderNavigationAvailability(canGoBack: false, canGoForward: true)

        state.lockAvailability(for: "tab-1", availability: lockedAvailability)

        XCTAssertEqual(
            state.displayedAvailability(for: "tab-2", currentAvailability: currentAvailability),
            currentAvailability
        )
    }

    func test_displayedAvailability_clearsLockWhenThereIsNoTab() {
        var state = AIChatTabChatHeaderNavigationState()
        let lockedAvailability = AIChatTabChatHeaderNavigationAvailability(canGoBack: true, canGoForward: false)

        state.lockAvailability(for: "tab-1", availability: lockedAvailability)

        XCTAssertEqual(
            state.displayedAvailability(for: nil, currentAvailability: lockedAvailability),
            .unavailable
        )
    }

    func test_lockAvailability_keepsEarliestSnapshotDuringRapidTaps() {
        var state = AIChatTabChatHeaderNavigationState()
        let firstTapAvailability = AIChatTabChatHeaderNavigationAvailability(canGoBack: true, canGoForward: false)
        let secondTapAvailability = AIChatTabChatHeaderNavigationAvailability(canGoBack: false, canGoForward: true)

        state.lockAvailability(for: "tab-1", availability: firstTapAvailability)
        state.lockAvailability(for: "tab-1", availability: secondTapAvailability)

        XCTAssertEqual(
            state.displayedAvailability(for: "tab-1", currentAvailability: secondTapAvailability),
            firstTapAvailability
        )
    }

    func test_lockAvailability_canRelockSameTabAfterClear() {
        var state = AIChatTabChatHeaderNavigationState()
        let firstTapAvailability = AIChatTabChatHeaderNavigationAvailability(canGoBack: true, canGoForward: false)
        let secondTapAvailability = AIChatTabChatHeaderNavigationAvailability(canGoBack: false, canGoForward: true)

        state.lockAvailability(for: "tab-1", availability: firstTapAvailability)
        XCTAssertTrue(state.clearLock(for: "tab-1"))
        state.lockAvailability(for: "tab-1", availability: secondTapAvailability)

        XCTAssertEqual(
            state.displayedAvailability(for: "tab-1", currentAvailability: firstTapAvailability),
            secondTapAvailability
        )
    }

    func test_displayedAvailability_doesNotClearReservationWhenThereIsNoTab() {
        var state = AIChatTabChatHeaderNavigationState()
        let liveAvailability = AIChatTabChatHeaderNavigationAvailability(canGoBack: true, canGoForward: false)

        state.reserveNavigationControls(for: "tab-1")

        XCTAssertEqual(
            state.displayedAvailability(for: nil, currentAvailability: .unavailable),
            .unavailable
        )
        XCTAssertFalse(state.reservesNavigationControls(for: nil))
        XCTAssertTrue(state.reservesNavigationControls(for: "tab-1"))
        XCTAssertEqual(
            state.displayedAvailability(for: "tab-1", currentAvailability: liveAvailability),
            liveAvailability
        )
    }

    func test_displayedAvailability_doesNotClearReservationForSameTabRead() {
        var state = AIChatTabChatHeaderNavigationState()

        state.reserveNavigationControls(for: "tab-1")

        XCTAssertEqual(
            state.displayedAvailability(for: "tab-1", currentAvailability: .unavailable),
            .unavailable
        )
        XCTAssertTrue(state.reservesNavigationControls(for: "tab-1"))
    }

    func test_reservesNavigationControls_clearsReservationWhenTabChanges() {
        var state = AIChatTabChatHeaderNavigationState()

        state.reserveNavigationControls(for: "tab-1")

        XCTAssertTrue(state.reservesNavigationControls(for: "tab-1"))
        XCTAssertFalse(state.reservesNavigationControls(for: "tab-2"))
        XCTAssertFalse(state.reservesNavigationControls(for: "tab-1"))
    }
}

@MainActor
final class AIChatTabChatHeaderViewNavigationSlotTests: XCTestCase {

    func test_navigationButtonsAreHiddenWhenNavigationIsUnavailableAndNotReserved() {
        let sut = AIChatTabChatHeaderView(frame: CGRect(x: 0, y: 0, width: 390, height: 60))

        sut.setNavAvailable(canGoBack: false, canGoForward: false)
        sut.layoutIfNeeded()

        XCTAssertTrue(visibleButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserBack).isEmpty)
        XCTAssertTrue(visibleButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserForward).isEmpty)
        XCTAssertEqual(visibleButtons(in: sut, accessibilityLabel: UserText.aiChatHeaderNewChatAccessibilityLabel).count, 1)
        XCTAssertEqual(visibleButtons(in: sut, accessibilityLabel: UserText.aiChatHeaderRecentChatsAccessibilityLabel).count, 1)
    }

    func test_navigationButtonsReserveBackSlotWithoutShowingForwardWhenNavigationIsReserved() {
        let sut = AIChatTabChatHeaderView(frame: CGRect(x: 0, y: 0, width: 390, height: 60))

        sut.setReservesNavigationControls(true)
        sut.setNavAvailable(canGoBack: false, canGoForward: false)
        sut.layoutIfNeeded()

        XCTAssertEqual(layoutSlotButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserBack).count, 1)
        XCTAssertTrue(visibleButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserBack).isEmpty)
        XCTAssertTrue(visibleButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserForward).isEmpty)
        XCTAssertTrue(visibleButtons(in: sut, accessibilityLabel: UserText.aiChatHeaderNewChatAccessibilityLabel).isEmpty)
        XCTAssertEqual(visibleButtons(in: sut, accessibilityLabel: UserText.aiChatHeaderRecentChatsAccessibilityLabel).count, 1)
    }

    func test_navigationButtonsReserveBackSlotWithoutShowingForwardWhenForwardNavigationIsAvailable() {
        let sut = AIChatTabChatHeaderView(frame: CGRect(x: 0, y: 0, width: 390, height: 60))

        sut.setReservesNavigationControls(true)
        sut.setNavAvailable(canGoBack: false, canGoForward: true)
        sut.layoutIfNeeded()

        XCTAssertEqual(layoutSlotButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserBack).count, 1)
        XCTAssertTrue(visibleButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserBack).isEmpty)
        XCTAssertTrue(layoutSlotButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserForward).isEmpty)
        XCTAssertTrue(visibleButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserForward).isEmpty)
        XCTAssertTrue(visibleButtons(in: sut, accessibilityLabel: UserText.aiChatHeaderNewChatAccessibilityLabel).isEmpty)
        XCTAssertEqual(visibleButtons(in: sut, accessibilityLabel: UserText.aiChatHeaderRecentChatsAccessibilityLabel).count, 1)
    }

    func test_navigationButtonsReserveBackSlotWithoutShowingNavPairWhenBackAndForwardNavigationAreAvailable() {
        let sut = AIChatTabChatHeaderView(frame: CGRect(x: 0, y: 0, width: 390, height: 60))

        sut.setReservesNavigationControls(true)
        sut.setNavAvailable(canGoBack: true, canGoForward: true)
        sut.layoutIfNeeded()

        XCTAssertEqual(layoutSlotButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserBack).count, 1)
        XCTAssertEqual(visibleButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserBack).count, 1)
        XCTAssertTrue(layoutSlotButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserForward).isEmpty)
        XCTAssertTrue(visibleButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserForward).isEmpty)
    }

    func test_navigationButtonsShowNavPairWhenBackAndForwardNavigationAreAvailableAndNotReserved() {
        let sut = AIChatTabChatHeaderView(frame: CGRect(x: 0, y: 0, width: 390, height: 60))

        sut.setNavAvailable(canGoBack: true, canGoForward: true)
        sut.layoutIfNeeded()

        XCTAssertEqual(layoutSlotButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserBack).count, 1)
        XCTAssertEqual(layoutSlotButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserForward).count, 1)
        XCTAssertEqual(visibleButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserBack).count, 1)
        XCTAssertEqual(visibleButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserForward).count, 1)
        XCTAssertTrue(visibleButtons(in: sut, accessibilityLabel: UserText.aiChatHeaderNewChatAccessibilityLabel).isEmpty)
    }

    func test_reservedBackSlotBecomesVisibleWhenBackNavigationBecomesAvailable() throws {
        let sut = AIChatTabChatHeaderView(frame: CGRect(x: 0, y: 0, width: 390, height: 60))

        sut.setReservesNavigationControls(true)
        sut.setNavAvailable(canGoBack: false, canGoForward: false)
        sut.layoutIfNeeded()

        let reservedBackButton = try XCTUnwrap(layoutSlotButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserBack).first)

        sut.setNavAvailable(canGoBack: true, canGoForward: false)
        sut.layoutIfNeeded()

        let enabledBackButton = try XCTUnwrap(visibleButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserBack).first)

        XCTAssertTrue(reservedBackButton === enabledBackButton)
        XCTAssertTrue(enabledBackButton.isEnabled)
        XCTAssertTrue(visibleButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserForward).isEmpty)
    }

    func test_reservedBackSlotRemainsStableWhenReservationClearsAfterBackNavigationBecomesAvailable() throws {
        let sut = AIChatTabChatHeaderView(frame: CGRect(x: 0, y: 0, width: 390, height: 60))

        sut.setReservesNavigationControls(true)
        sut.setNavAvailable(canGoBack: false, canGoForward: false)
        sut.layoutIfNeeded()

        let reservedBackButton = try XCTUnwrap(layoutSlotButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserBack).first)

        sut.setNavAvailable(canGoBack: true, canGoForward: false)
        sut.setReservesNavigationControls(false)
        sut.layoutIfNeeded()

        let visibleBackButton = try XCTUnwrap(visibleButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserBack).first)

        XCTAssertTrue(reservedBackButton === visibleBackButton)
        XCTAssertTrue(visibleBackButton.isEnabled)
        XCTAssertTrue(visibleButtons(in: sut, accessibilityLabel: UserText.keyCommandBrowserForward).isEmpty)
    }

    private func visibleButtons(in view: UIView, accessibilityLabel: String) -> [UIButton] {
        var result: [UIButton] = []
        collectVisibleButtons(in: view, accessibilityLabel: accessibilityLabel, result: &result)
        return result
    }

    private func collectVisibleButtons(in view: UIView, accessibilityLabel: String, result: inout [UIButton]) {
        if let button = view as? UIButton,
           button.accessibilityLabel == accessibilityLabel,
           isEffectivelyVisible(button) {
            result.append(button)
        }

        view.subviews.forEach {
            collectVisibleButtons(in: $0, accessibilityLabel: accessibilityLabel, result: &result)
        }
    }

    private func layoutSlotButtons(in view: UIView, accessibilityLabel: String) -> [UIButton] {
        var result: [UIButton] = []
        collectLayoutSlotButtons(in: view, accessibilityLabel: accessibilityLabel, result: &result)
        return result
    }

    private func collectLayoutSlotButtons(in view: UIView, accessibilityLabel: String, result: inout [UIButton]) {
        if let button = view as? UIButton,
           button.accessibilityLabel == accessibilityLabel,
           isInVisibleLayout(button) {
            result.append(button)
        }

        view.subviews.forEach {
            collectLayoutSlotButtons(in: $0, accessibilityLabel: accessibilityLabel, result: &result)
        }
    }

    private func isEffectivelyVisible(_ view: UIView) -> Bool {
        var currentView: UIView? = view
        while let view = currentView {
            if view.isHidden || view.alpha <= 0.01 {
                return false
            }
            currentView = view.superview
        }
        return true
    }

    private func isInVisibleLayout(_ view: UIView) -> Bool {
        var currentView: UIView? = view
        while let view = currentView {
            if view.isHidden {
                return false
            }
            currentView = view.superview
        }
        return true
    }
}
