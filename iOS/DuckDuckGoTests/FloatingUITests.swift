//
//  FloatingUITests.swift
//  DuckDuckGoTests
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
@testable import Core
@testable import DuckDuckGo

final class FloatingUIManagerTests: XCTestCase {

    func testWhenFloatingUIAndUnifiedToggleInputAreEnabledOnIPhoneThenFloatingUIIsEnabled() {
        let manager = FloatingUIManager(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.floatingUIAugust2026]),
            isPadProvider: { false },
            isSupportedOSProvider: { true },
            unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider(isAvailable: true)
        )

        XCTAssertTrue(manager.isFloatingUIEnabled)
    }

    func testWhenFloatingUIIsEnabledButUnifiedToggleInputIsUnavailableThenFloatingUIIsDisabled() {
        let manager = FloatingUIManager(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.floatingUIAugust2026]),
            isPadProvider: { false },
            isSupportedOSProvider: { true },
            unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider(isAvailable: false)
        )

        XCTAssertFalse(manager.isFloatingUIEnabled)
    }

    func testWhenFloatingUIIsDisabledAndUnifiedToggleInputIsAvailableThenFloatingUIIsDisabled() {
        let manager = FloatingUIManager(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []),
            isPadProvider: { false },
            isSupportedOSProvider: { true },
            unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider(isAvailable: true)
        )

        XCTAssertFalse(manager.isFloatingUIEnabled)
    }

    func testWhenFloatingUIAndUnifiedToggleInputAreEnabledOnIPadThenFloatingUIIsDisabled() {
        let manager = FloatingUIManager(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.floatingUIAugust2026]),
            isPadProvider: { true },
            isSupportedOSProvider: { true },
            unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider(isAvailable: true)
        )

        XCTAssertFalse(manager.isFloatingUIEnabled)
    }

    func testWhenOSIsUnsupportedThenFloatingUIIsDisabled() {
        let manager = FloatingUIManager(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.floatingUIAugust2026]),
            isPadProvider: { false },
            isSupportedOSProvider: { false },
            unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider(isAvailable: true)
        )

        XCTAssertFalse(manager.isFloatingUIEnabled)
    }

    func testWhenAugustFlagIsEnabledOnSupportedIPhoneThenFloatingTabSwitcherIsEnabled() {
        let manager = FloatingUIManager(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.floatingUIAugust2026]),
            isPadProvider: { false },
            isSupportedOSProvider: { false },
            isTabSwitcherSupportedOSProvider: { true },
            unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider(isAvailable: false)
        )

        XCTAssertFalse(manager.isFloatingUIEnabled)
        XCTAssertTrue(manager.isFloatingTabSwitcherEnabled)
    }

    func testWhenAugustFlagIsDisabledThenFloatingTabSwitcherIsDisabled() {
        let manager = FloatingUIManager(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []),
            isPadProvider: { false },
            isTabSwitcherSupportedOSProvider: { true }
        )

        XCTAssertFalse(manager.isFloatingTabSwitcherEnabled)
    }

    func testWhenAugustFlagIsEnabledOnIPadThenFloatingTabSwitcherIsDisabled() {
        let manager = FloatingUIManager(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.floatingUIAugust2026]),
            isPadProvider: { true },
            isTabSwitcherSupportedOSProvider: { true }
        )

        XCTAssertFalse(manager.isFloatingTabSwitcherEnabled)
    }

    func testWhenTabSwitcherOSIsUnsupportedThenFloatingTabSwitcherIsDisabled() {
        let manager = FloatingUIManager(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.floatingUIAugust2026]),
            isPadProvider: { false },
            isTabSwitcherSupportedOSProvider: { false }
        )

        XCTAssertFalse(manager.isFloatingTabSwitcherEnabled)
    }

}

final class FloatingGlassAppearancePolicyTests: XCTestCase {

    func testWhenFireModeIsActiveThenInterfaceStyleIsDarkRegardlessOfDeviceAndPageAppearance() {
        let interfaceStyle = FloatingGlassAppearancePolicy.interfaceStyle(
            isFireMode: true,
            traitCollection: UITraitCollection(userInterfaceStyle: .light),
            pageBackgroundColor: .white)

        XCTAssertEqual(interfaceStyle, .dark)
    }

    func testWhenNormalModeUsesDarkDeviceAppearanceThenInterfaceStyleIsDark() {
        let interfaceStyle = FloatingGlassAppearancePolicy.interfaceStyle(
            isFireMode: false,
            traitCollection: UITraitCollection(userInterfaceStyle: .dark),
            pageBackgroundColor: .white)

        XCTAssertEqual(interfaceStyle, .dark)
    }

    func testWhenNormalModeUsesLightDeviceAppearanceThenInterfaceStyleFollowsPageAppearance() {
        let traitCollection = UITraitCollection(userInterfaceStyle: .light)

        XCTAssertEqual(FloatingGlassAppearancePolicy.interfaceStyle(isFireMode: false,
                                                                    traitCollection: traitCollection,
                                                                    pageBackgroundColor: .black),
                       .dark)
        XCTAssertEqual(FloatingGlassAppearancePolicy.interfaceStyle(isFireMode: false,
                                                                    traitCollection: traitCollection,
                                                                    pageBackgroundColor: .white),
                       .light)
    }

    func testWhenNormalModeHasNoPageColorThenInterfaceStyleIsLight() {
        let interfaceStyle = FloatingGlassAppearancePolicy.interfaceStyle(
            isFireMode: false,
            traitCollection: UITraitCollection(userInterfaceStyle: .light),
            pageBackgroundColor: nil)

        XCTAssertEqual(interfaceStyle, .light)
    }
}

final class FloatingUILayoutPolicyTests: XCTestCase {

    func testWhenBarsVisibleThenBottomObscuredHeightIsToolbarSlot() {
        let height = FloatingUILayoutPolicy.webViewBottomObscuredHeight(
            barsVisibilityPercent: 1,
            toolbarSlotHeight: 100,
            bottomCapsuleObscuredHeight: 70,
            safeAreaBottom: 34
        )

        XCTAssertEqual(height, 100, accuracy: 0.001)
    }

    func testWhenBarsHiddenAndBottomCapsuleVisibleThenBottomObscuredHeightTracksCapsule() {
        let height = FloatingUILayoutPolicy.webViewBottomObscuredHeight(
            barsVisibilityPercent: 0,
            toolbarSlotHeight: 100,
            bottomCapsuleObscuredHeight: 70,
            safeAreaBottom: 34
        )

        XCTAssertEqual(height, 70, accuracy: 0.001)
    }

    func testWhenBarsHiddenAndNoBottomCapsuleThenBottomObscuredHeightIsSafeArea() {
        let height = FloatingUILayoutPolicy.webViewBottomObscuredHeight(
            barsVisibilityPercent: 0,
            toolbarSlotHeight: 100,
            bottomCapsuleObscuredHeight: 0,
            safeAreaBottom: 34
        )

        XCTAssertEqual(height, 34, accuracy: 0.001)
    }

    func testWhenPartiallyHiddenThenBottomObscuredHeightIsMaxOfShrinkingToolbarAndCapsule() {
        // toolbar term = 100 * 0.5 = 50, capsule rest = 70 -> capsule wins the crossover.
        let height = FloatingUILayoutPolicy.webViewBottomObscuredHeight(
            barsVisibilityPercent: 0.5,
            toolbarSlotHeight: 100,
            bottomCapsuleObscuredHeight: 70,
            safeAreaBottom: 34
        )

        XCTAssertEqual(height, 70, accuracy: 0.001)
    }

    func testWhenVisibleToolbarIsTallerThanTheInterpolatedSlotThenBottomObscuredHeightUsesTheVisibleChrome() {
        let height = FloatingUILayoutPolicy.webViewBottomObscuredHeight(
            barsVisibilityPercent: 0.8,
            toolbarSlotHeight: 100,
            visibleToolbarHeight: 90,
            bottomCapsuleObscuredHeight: 70,
            safeAreaBottom: 34
        )

        XCTAssertEqual(height, 90, accuracy: 0.001)
    }

    func testWhenBarsVisibleThenTopObscuredHeightIsExpandedChrome() {
        let height = FloatingUILayoutPolicy.webViewTopObscuredHeight(
            barsVisibilityPercent: 1,
            expandedChromeHeight: 111,
            topCapsuleObscuredHeight: 91,
            safeAreaTop: 59
        )

        XCTAssertEqual(height, 111, accuracy: 0.001)
    }

    func testWhenBarsHiddenAndTopCapsuleVisibleThenTopObscuredHeightTracksCapsule() {
        let height = FloatingUILayoutPolicy.webViewTopObscuredHeight(
            barsVisibilityPercent: 0,
            expandedChromeHeight: 111,
            topCapsuleObscuredHeight: 91,
            safeAreaTop: 59
        )

        XCTAssertEqual(height, 91, accuracy: 0.001)
    }

    func testWhenBarsHiddenAndNoTopCapsuleThenTopObscuredHeightIsSafeArea() {
        let height = FloatingUILayoutPolicy.webViewTopObscuredHeight(
            barsVisibilityPercent: 0,
            expandedChromeHeight: 111,
            topCapsuleObscuredHeight: 0,
            safeAreaTop: 59
        )

        XCTAssertEqual(height, 59, accuracy: 0.001)
    }

    func testWhenPartiallyHiddenThenTopObscuredHeightIsMaxOfShrinkingChromeAndCapsule() {
        let height = FloatingUILayoutPolicy.webViewTopObscuredHeight(
            barsVisibilityPercent: 0.5,
            expandedChromeHeight: 111,
            topCapsuleObscuredHeight: 91,
            safeAreaTop: 59
        )

        XCTAssertEqual(height, 91, accuracy: 0.001)
    }

    func testWhenVisibleTopChromeIsTallerThanTheInterpolatedChromeThenTopObscuredHeightUsesTheVisibleChrome() {
        let height = FloatingUILayoutPolicy.webViewTopObscuredHeight(
            barsVisibilityPercent: 0.8,
            expandedChromeHeight: 111,
            visibleChromeHeight: 105,
            topCapsuleObscuredHeight: 91,
            safeAreaTop: 59
        )

        XCTAssertEqual(height, 105, accuracy: 0.001)
    }

    func testWhenBarsVisibleAboveTheHandoffThenChromeStaysFullyOnScreen() {
        for percent in [1.0, 0.9, 0.75, 0.6] as [CGFloat] {
            let fraction = FloatingUILayoutPolicy.chromeOnScreenFraction(barsVisibilityPercent: percent, handoffStart: 0.6)

            XCTAssertEqual(fraction, 1, accuracy: 0.001, "expected no slide at \(percent)")
        }
    }

    func testWhenBarsVisibleBelowTheHandoffThenChromeSlidesOutProportionally() {
        let fraction = FloatingUILayoutPolicy.chromeOnScreenFraction(barsVisibilityPercent: 0.3, handoffStart: 0.6)

        XCTAssertEqual(fraction, 0.5, accuracy: 0.001)
    }

    func testWhenBarsHiddenThenChromeIsFullyOffScreen() {
        let fraction = FloatingUILayoutPolicy.chromeOnScreenFraction(barsVisibilityPercent: 0, handoffStart: 0.6)

        XCTAssertEqual(fraction, 0, accuracy: 0.001)
    }

    func testWhenFloatingBottomAddressBarAndNotMinimalChromeThenOmnibarIsHostedInToolbar() {
        XCTAssertTrue(FloatingUILayoutPolicy.shouldHostOmnibarInFloatingToolbar(
            isFloatingUIEnabled: true,
            addressBarPosition: .bottom,
            isUnifiedToggleInputVisible: false,
            isMinimalChromeLayout: false
        ))
    }

    func testWhenMinimalChromeThenBottomOmnibarIsNotHostedInToolbar() {
        // The toolbar is hidden in minimal chrome, so hosting the omnibar in it would hide the bar.
        XCTAssertFalse(FloatingUILayoutPolicy.shouldHostOmnibarInFloatingToolbar(
            isFloatingUIEnabled: true,
            addressBarPosition: .bottom,
            isUnifiedToggleInputVisible: false,
            isMinimalChromeLayout: true
        ))
    }

    func testWhenTopAddressBarThenOmnibarIsNotHostedInToolbarRegardlessOfMinimalChrome() {
        for isMinimalChromeLayout in [false, true] {
            XCTAssertFalse(FloatingUILayoutPolicy.shouldHostOmnibarInFloatingToolbar(
                isFloatingUIEnabled: true,
                addressBarPosition: .top,
                isUnifiedToggleInputVisible: false,
                isMinimalChromeLayout: isMinimalChromeLayout
            ))
        }
    }
}

final class DefaultOmniBarViewMinimalChromeTests: XCTestCase {

    private func firstGlassView(in view: UIView) -> UIVisualEffectView? {
        if let glassView = view as? UIVisualEffectView {
            return glassView
        }
        return view.subviews.lazy.compactMap(firstGlassView(in:)).first
    }

    private func glassViewCount(in view: UIView) -> Int {
        view.subviews.filter { $0 is UIVisualEffectView }.count
            + view.subviews.reduce(0) { $0 + glassViewCount(in: $1) }
    }

    private func floatingContentHost(in view: UIView) -> DefaultOmniBarView.FloatingGlassContentHostView? {
        if let host = view as? DefaultOmniBarView.FloatingGlassContentHostView {
            return host
        }
        return view.subviews.lazy.compactMap(floatingContentHost(in:)).first
    }

    func testWhenFloatingMinimalChromeBarEnabledThenLeadingAndTrailingGlassGroupsAreAddedAndRemoved() {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.frame = CGRect(x: 0, y: 0, width: 700, height: 60)

        // The address bar field already carries its own glass; enabling adds the two button groups.
        let baseline = glassViewCount(in: barView)

        barView.setFloatingMinimalChromeBar(true)
        XCTAssertEqual(glassViewCount(in: barView), baseline + 2)

        barView.setFloatingMinimalChromeBar(false)
        XCTAssertEqual(glassViewCount(in: barView), baseline)
    }

    func testWhenFloatingUIDisabledThenMinimalChromeBarAddsNoGlassGroups() {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: false)
        barView.frame = CGRect(x: 0, y: 0, width: 700, height: 60)

        let baseline = glassViewCount(in: barView)
        barView.setFloatingMinimalChromeBar(true)

        XCTAssertEqual(glassViewCount(in: barView), baseline)
    }

    func testWhenFloatingBarResizesThenFieldGlassMatchesItsContainerBounds() {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.frame = CGRect(x: 0, y: 0, width: 390, height: 60)
        barView.layoutIfNeeded()

        guard let searchContainer = barView.searchContainer,
              let glassView = firstGlassView(in: searchContainer) else {
            XCTFail("Missing field glass")
            return
        }

        XCTAssertEqual(glassView.frame, searchContainer.bounds)

        barView.frame.size.width = 700
        barView.setNeedsLayout()
        barView.layoutIfNeeded()

        XCTAssertEqual(glassView.frame, searchContainer.bounds)
    }

    func testWhenFloatingFieldIsAtBottomThenContentIsHostedInsideUntintedGlass() throws {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.frame = CGRect(x: 0, y: 0, width: 390, height: DefaultOmniBarView.expectedHeight)
        barView.isUsingSmallTopSpacing = true
        barView.layoutIfNeeded()

        let searchContainer = try XCTUnwrap(barView.searchContainer)
        let glassView = try XCTUnwrap(firstGlassView(in: searchContainer))
        let contentHost = try XCTUnwrap(floatingContentHost(in: barView))

        XCTAssertTrue(contentHost.isDescendant(of: glassView.contentView))
        XCTAssertEqual(searchContainer.backgroundColor, .clear)
        if #available(iOS 26.0, *) {
            XCTAssertNil((glassView.effect as? UIGlassEffect)?.tintColor)
        }
    }

    func testWhenShieldAndLoupeShareTheIconSlotThenTheyShareACentre() throws {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.isUsingSmallTopSpacing = true
        barView.frame = CGRect(x: 0, y: 0, width: 390, height: barView.expectedHeight)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.addSubview(barView)
        window.makeKeyAndVisible()
        barView.layoutIfNeeded()

        let shield = try XCTUnwrap(barView.privacyInfoContainer)
        let slot = try XCTUnwrap(barView.leftIconContainerView)

        func assertCentred(_ context: String, file: StaticString = #filePath, line: UInt = #line) {
            let shieldCentre = barView.convert(shield.center, from: shield.superview)
            let slotCentre = barView.convert(slot.center, from: slot.superview)
            XCTAssertEqual(shieldCentre.x, slotCentre.x, accuracy: 0.5, context, file: file, line: line)
            XCTAssertEqual(shieldCentre.y, slotCentre.y, accuracy: 0.5, context, file: file, line: line)
        }

        // The shield and the loupe swap in and out of the same slot, so a shared centre keeps the
        // icon from shifting when the state changes.
        assertCentred("at rest")

        barView.textField.becomeFirstResponder()
        barView.layoutIfNeeded()
        assertCentred("while focused")
    }

    func testWhenEmbeddedFieldIsTallerThanItsControlsThenTheRowStaysCentred() throws {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.isUsingSmallTopSpacing = true
        barView.frame = CGRect(x: 0, y: 0, width: 390, height: barView.expectedHeight)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.addSubview(barView)
        window.makeKeyAndVisible()
        barView.layoutIfNeeded()

        let field = try XCTUnwrap(barView.searchContainer)
        let fieldMidY = barView.convert(field.bounds, from: field).midY

        // The 44pt controls are shorter than the 48pt field, so the slack has to split evenly
        // rather than settling the row against one edge.
        for item in [barView.leftIconContainerView, barView.refreshButton, barView.textField] {
            let view = try XCTUnwrap(item)
            XCTAssertEqual(barView.convert(view.bounds, from: view).midY, fieldMidY, accuracy: 0.5)
        }
    }

    func testWhenFieldIsEmbeddedAtBottomThenItFillsTheFullSlotHeight() throws {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.isUsingSmallTopSpacing = true
        barView.frame = CGRect(x: 0, y: 0, width: 390, height: barView.expectedHeight)
        barView.layoutIfNeeded()

        let searchContainer = try XCTUnwrap(barView.searchContainer)
        let glassView = try XCTUnwrap(firstGlassView(in: searchContainer))

        // The visible field is the glass, so it has to be the full 48pt rather than a 44pt pill
        // floating inside the slot.
        XCTAssertEqual(barView.expectedHeight, 48, accuracy: 0.01)
        XCTAssertEqual(searchContainer.bounds.height, barView.expectedHeight, accuracy: 0.01)
        XCTAssertEqual(glassView.frame.height, barView.expectedHeight, accuracy: 0.01)
    }

    func testWhenToolbarMaterialAppearanceRefreshesThenHostedOmnibarUsesSettledStyle() {
        let toolbar = BrowserToolbarView(frame: CGRect(x: 0, y: 0, width: 390, height: 200))
        toolbar.overrideUserInterfaceStyle = .light
        toolbar.setFloatingStyleEnabled(true)
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.isUsingSmallTopSpacing = true
        toolbar.setOmnibarView(barView, height: barView.expectedHeight)

        toolbar.refreshMaterialAppearance(interfaceStyle: .dark)

        let refreshCompleted = expectation(description: "Nested material refreshed")
        DispatchQueue.main.async {
            let glassView = self.firstGlassView(in: barView.searchContainer)
            XCTAssertEqual(glassView?.overrideUserInterfaceStyle.rawValue, UIUserInterfaceStyle.dark.rawValue)
            refreshCompleted.fulfill()
        }
        wait(for: [refreshCompleted], timeout: 1)
    }

    func testWhenFloatingFieldMovesBetweenTopAndBottomThenContentRemainsInsideCurrentGlass() throws {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.frame = CGRect(x: 0, y: 0, width: 390, height: DefaultOmniBarView.expectedHeight)
        barView.layoutIfNeeded()

        let searchContainer = try XCTUnwrap(barView.searchContainer)
        let contentHost = try XCTUnwrap(floatingContentHost(in: barView))
        let initialTopGlass = try XCTUnwrap(firstGlassView(in: searchContainer))
        XCTAssertTrue(contentHost.isDescendant(of: initialTopGlass.contentView))

        barView.isUsingSmallTopSpacing = true
        let bottomGlass = try XCTUnwrap(firstGlassView(in: searchContainer))
        XCTAssertFalse(bottomGlass === initialTopGlass)
        XCTAssertTrue(contentHost.isDescendant(of: bottomGlass.contentView))

        barView.isUsingSmallTopSpacing = false
        let secondTopGlass = try XCTUnwrap(firstGlassView(in: searchContainer))
        XCTAssertFalse(secondTopGlass === bottomGlass)
        XCTAssertTrue(contentHost.isDescendant(of: secondTopGlass.contentView))

        barView.isUsingSmallTopSpacing = true
        let secondBottomGlass = try XCTUnwrap(firstGlassView(in: searchContainer))
        XCTAssertFalse(secondBottomGlass === secondTopGlass)
        XCTAssertTrue(contentHost.isDescendant(of: secondBottomGlass.contentView))
        XCTAssertEqual(glassViewCount(in: searchContainer), 1)
    }

    func testWhenBottomFloatingFieldLeavesFireModeThenContentReturnsToGlass() throws {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.frame = CGRect(x: 0, y: 0, width: 390, height: DefaultOmniBarView.expectedHeight)
        barView.isUsingSmallTopSpacing = true

        let searchContainer = try XCTUnwrap(barView.searchContainer)
        let contentHost = try XCTUnwrap(floatingContentHost(in: barView))

        barView.refreshFireMode(fireMode: true)
        XCTAssertNil(firstGlassView(in: searchContainer))
        XCTAssertFalse(searchContainer.backgroundColor == .clear)

        barView.refreshFireMode(fireMode: false)
        let glassView = try XCTUnwrap(firstGlassView(in: searchContainer))
        XCTAssertTrue(contentHost.isDescendant(of: glassView.contentView))
        XCTAssertEqual(searchContainer.backgroundColor, .clear)
    }

    func testWhenGlassAppearanceIsUnchangedThenMakingGlassPreservesGlassView() throws {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.frame = CGRect(x: 0, y: 0, width: 390, height: DefaultOmniBarView.expectedHeight)
        barView.layoutIfNeeded()
        let glassView = try XCTUnwrap(firstGlassView(in: barView.searchContainer))

        barView.makeGlass()

        XCTAssertTrue(firstGlassView(in: barView.searchContainer) === glassView)
    }

    func testWhenMaterialAppearanceRefreshesThenGlassViewIsRebuilt() throws {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.frame = CGRect(x: 0, y: 0, width: 390, height: DefaultOmniBarView.expectedHeight)
        barView.isUsingSmallTopSpacing = true
        barView.layoutIfNeeded()
        let glassView = try XCTUnwrap(firstGlassView(in: barView.searchContainer))

        barView.refreshMaterialAppearance()

        XCTAssertFalse(firstGlassView(in: barView.searchContainer) === glassView)
    }

    func testWhenFireModeChangesThenGlassViewIsRebuilt() throws {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.frame = CGRect(x: 0, y: 0, width: 390, height: DefaultOmniBarView.expectedHeight)
        barView.layoutIfNeeded()
        let glassView = try XCTUnwrap(firstGlassView(in: barView.searchContainer))

        barView.refreshFireMode(fireMode: true)

        XCTAssertFalse(firstGlassView(in: barView.searchContainer) === glassView)
    }

    func testWhenBottomFloatingBarTemporarilyHasZeroHeightThenCornerRadiusRemainsRounded() {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.frame = CGRect(x: 0, y: 0, width: 390, height: 0)
        barView.isUsingSmallTopSpacing = true

        barView.layoutIfNeeded()

        XCTAssertGreaterThan(barView.searchContainer.layer.cornerRadius, 0)
    }

    func testWhenBottomFloatingFieldThenExpectedHeightIsTheFortyEightPointPill() {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.isUsingSmallTopSpacing = true

        XCTAssertEqual(barView.expectedHeight, 48)
    }

    func testWhenTopFloatingFieldThenExpectedHeightStaysAtTheStandardBarHeight() {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.isUsingSmallTopSpacing = false

        XCTAssertEqual(barView.expectedHeight, DefaultOmniBarView.expectedHeight)
    }

    func testWhenTopFloatingFieldThenInputIsFortyEightPointsHighWithTwoPointInternalSpacing() throws {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.frame = CGRect(x: 0, y: 0, width: 390, height: barView.expectedHeight)
        barView.isUsingSmallTopSpacing = false

        barView.layoutIfNeeded()

        let searchContainer = try XCTUnwrap(barView.searchContainer)
        let searchContainerFrame = barView.convert(searchContainer.bounds, from: searchContainer)
        let searchView = try XCTUnwrap(firstSubview(of: DefaultOmniBarSearchView.self, in: searchContainer))
        let loupe = try XCTUnwrap(barView.searchLoupe)
        let loupeFrame = searchView.convert(loupe.bounds, from: loupe)
        XCTAssertEqual(searchContainerFrame.height, 48, accuracy: 0.01)
        XCTAssertEqual(searchContainerFrame.minX, 16, accuracy: 0.5)
        XCTAssertEqual(barView.bounds.width - searchContainerFrame.maxX, 16, accuracy: 0.5)
        XCTAssertEqual(barView.restingSearchFieldSize.width, searchContainerFrame.width, accuracy: 0.01)
        XCTAssertEqual(barView.restingSearchFieldSize.height, 48, accuracy: 0.01)
        XCTAssertEqual(searchContainerFrame.midX, barView.bounds.midX, accuracy: 0.01)
        XCTAssertEqual(searchContainerFrame.midY, barView.bounds.midY, accuracy: 0.01)
        XCTAssertEqual(searchView.bounds.height, 44, accuracy: 0.01)
        XCTAssertEqual((searchContainerFrame.height - searchView.bounds.height) / 2, 2, accuracy: 0.01)
        XCTAssertEqual(loupeFrame.midY, searchView.bounds.midY, accuracy: 0.01)
    }

    func testWhenTopFloatingLandscapeChromeThenInputHeightStaysUnchanged() {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.frame = CGRect(x: 0, y: 0, width: 844, height: barView.expectedHeight)
        barView.isUsingSmallTopSpacing = false
        barView.isExpandedPhoneLayout = true
        barView.setLayoutMode(.expandedPhone, animated: false)

        barView.layoutIfNeeded()

        XCTAssertEqual(barView.expectedHeight, DefaultOmniBarView.expectedHeight)
        XCTAssertEqual(barView.searchContainer.frame.height, 44, accuracy: 0.01)
    }

    func testWhenTopFloatingLandscapeEditingThenCompactModeKeepsInputHeightUnchanged() {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.frame = CGRect(x: 0, y: 0, width: 844, height: barView.expectedHeight)
        barView.isUsingSmallTopSpacing = false
        barView.isExpandedPhoneLayout = true
        barView.setLayoutMode(.compact, animated: false)

        barView.layoutIfNeeded()

        XCTAssertEqual(barView.expectedHeight, DefaultOmniBarView.expectedHeight)
        XCTAssertEqual(barView.searchContainer.frame.height, 44, accuracy: 0.01)
    }

    func testWhenBottomFloatingLandscapeEditingThenCompactModeKeepsInputHeightUnchanged() {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.frame = CGRect(x: 0, y: 0, width: 844, height: barView.expectedHeight)
        barView.isUsingSmallTopSpacing = true
        barView.isExpandedPhoneLayout = true
        barView.setLayoutMode(.compact, animated: false)

        barView.layoutIfNeeded()

        XCTAssertEqual(barView.expectedHeight, DefaultOmniBarView.expectedHeight)
        XCTAssertEqual(barView.searchContainer.frame.height, 44, accuracy: 0.01)
    }

    func testWhenNonFloatingTopFieldThenInputHeightStaysUnchanged() {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: false)
        barView.frame = CGRect(x: 0, y: 0, width: 390, height: barView.expectedHeight)
        barView.isUsingSmallTopSpacing = false

        barView.layoutIfNeeded()

        XCTAssertEqual(barView.expectedHeight, DefaultOmniBarView.expectedHeight)
        XCTAssertEqual(barView.searchContainer.frame.height, 44, accuracy: 0.01)
    }

    func testWhenBottomFloatingLandscapeChromeThenExpectedHeightStaysAtTheStandardBarHeight() {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.isUsingSmallTopSpacing = true
        barView.setLayoutMode(.expandedPhone, animated: false)

        XCTAssertEqual(barView.expectedHeight, DefaultOmniBarView.expectedHeight)
    }

    func testWhenBottomFloatingPadChromeThenExpectedHeightStaysAtTheStandardBarHeight() {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.isUsingSmallTopSpacing = true
        barView.setLayoutMode(.expandedPad, animated: false)

        XCTAssertEqual(barView.expectedHeight, DefaultOmniBarView.expectedHeight)
    }

    private func firstSubview<View: UIView>(of type: View.Type, in view: UIView) -> View? {
        if let view = view as? View {
            return view
        }
        return view.subviews.lazy.compactMap { self.firstSubview(of: type, in: $0) }.first
    }
}

final class FloatingDomainCapsuleControllerTests: XCTestCase {

    private var window: UIWindow!
    private var containerView: UIView!
    private var controller: FloatingDomainCapsuleController!
    private let expandedFrame = CGRect(x: 16, y: 20, width: 358, height: 52)

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        containerView = UIView(frame: window.bounds)
        window.addSubview(containerView)
        window.makeKeyAndVisible()
        controller = FloatingDomainCapsuleController(onTap: {})
        controller.install(in: containerView, addressBarPosition: .top)
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        containerView = nil
        controller = nil
        super.tearDown()
    }

    private var capsuleButton: UIButton? {
        containerView.subviews.compactMap { $0 as? UIButton }.first
    }

    @discardableResult
    private func update(barsVisibilityPercent: CGFloat,
                        addressBarPosition: AddressBarPosition = .top,
                        reduceMotion: Bool = false) -> UIButton? {
        controller.update(addressBarPosition: addressBarPosition,
                          isFloatingUIEnabled: true,
                          isUnifiedToggleInputActive: false,
                          isAITab: false,
                          isMinimalChromeLayout: false,
                          domain: "example.com",
                          barsVisibilityPercent: barsVisibilityPercent,
                          expandedFrame: expandedFrame,
                          reduceMotion: reduceMotion,
                          in: containerView)
        containerView.layoutIfNeeded()
        return capsuleButton
    }

    func testWhenBarsHiddenThenPillIsAtCapsuleSizeAndVisible() {
        let button = update(barsVisibilityPercent: 0)

        XCTAssertNotNil(button)
        XCTAssertEqual(button?.alpha ?? 0, 1, accuracy: 0.001)
        // Capsule hugs the domain label, so it is far narrower than the bar.
        XCTAssertLessThan(button?.bounds.width ?? .greatestFiniteMagnitude, expandedFrame.width / 2)
    }

    func testWhenTopBarsHiddenThenPillKeepsTheBarsTopEdge() {
        let button = update(barsVisibilityPercent: 0)

        // The pill collapses upward into the bar's top edge, so no empty band is left above it.
        XCTAssertEqual(button?.frame.minY ?? 0, expandedFrame.minY, accuracy: 0.5)
    }

    func testWhenTopCapsuleRestsThenObscuredHeightTracksThePillBottom() {
        update(barsVisibilityPercent: 0)
        let insets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)

        let obscured = controller.restObscuredHeightFromScreenEdge(for: .top,
                                                                   safeAreaInsets: insets,
                                                                   expandedFrame: expandedFrame)

        // Tracks the moved pill, so page-fixed headers don't leave a dead band beneath it.
        XCTAssertEqual(obscured, expandedFrame.minY + controller.capsuleHeight, accuracy: 0.001)
        XCTAssertLessThan(obscured, expandedFrame.maxY)
    }

    func testWhenPartiallyVisibleThenPillWidthIsBetweenCapsuleAndBarAndFullyOpaque() {
        let capsuleWidth = update(barsVisibilityPercent: 0)?.bounds.width ?? 0
        let midWidth = update(barsVisibilityPercent: 0.5)?.bounds.width ?? 0

        XCTAssertGreaterThan(midWidth, capsuleWidth)
        XCTAssertLessThan(midWidth, expandedFrame.width)
        // No mid-transition cross-fade: the pill is solid through the resize band.
        XCTAssertEqual(capsuleButton?.alpha ?? 0, 1, accuracy: 0.001)
    }

    func testWhenBarsFullyVisibleThenPillIsHidden() {
        update(barsVisibilityPercent: 1)

        XCTAssertEqual(capsuleButton?.alpha ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(capsuleButton?.isHidden, true)
    }

    func testWhenReduceMotionThenPillStaysAtCapsuleSize() {
        let capsuleWidth = update(barsVisibilityPercent: 0, reduceMotion: true)?.bounds.width ?? 0
        let midWidth = update(barsVisibilityPercent: 0.5, reduceMotion: true)?.bounds.width ?? 0

        XCTAssertEqual(midWidth, capsuleWidth, accuracy: 0.5)
    }

    func testWhenBottomBarsHiddenThenPillRestsAtTheLowerCollapsedCenter() {
        let button = update(barsVisibilityPercent: 0, addressBarPosition: .bottom)
        let expectedCenterY = FloatingDomainCapsuleController.restCenterY(
            addressBarPosition: .bottom,
            expandedFrame: expandedFrame,
            boundsMaxY: containerView.bounds.maxY,
            safeAreaInsets: containerView.safeAreaInsets,
            capsuleHeight: controller.capsuleHeight)

        XCTAssertEqual(button?.center.y ?? 0, expectedCenterY, accuracy: 0.5)
    }

    func testWhenBottomCapsuleRestsThenObscuredHeightTracksThePillNotExtraTopPadding() {
        update(barsVisibilityPercent: 0, addressBarPosition: .bottom)
        let insets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let padding = FloatingDomainCapsuleController.restPaddingFromPhysicalBottom(safeAreaBottom: insets.bottom)
        let obscured = controller.restObscuredHeightFromScreenEdge(for: .bottom, safeAreaInsets: insets)

        XCTAssertEqual(obscured, padding + controller.capsuleHeight, accuracy: 0.001)
        XCTAssertLessThan(obscured, insets.bottom + FloatingDomainCapsuleController.restEdgePadding + controller.capsuleHeight)
    }
}

final class FloatingDomainCapsuleGeometryTests: XCTestCase {

    func testWhenHomeIndicatorIsPresentThenBottomRestPaddingIsReducedByTwelvePoints() {
        let safeAreaBottom: CGFloat = 34
        let padding = FloatingDomainCapsuleController.restPaddingFromPhysicalBottom(safeAreaBottom: safeAreaBottom)

        XCTAssertEqual(
            padding,
            safeAreaBottom + FloatingDomainCapsuleController.restEdgePadding - FloatingDomainCapsuleController.restBottomInsetReduction,
            accuracy: 0.001)
    }

    func testWhenSafeAreaCannotAbsorbTheReductionThenBottomRestPaddingClampsToZero() {
        XCTAssertEqual(FloatingDomainCapsuleController.restPaddingFromPhysicalBottom(safeAreaBottom: 0), 0, accuracy: 0.001)
    }

    func testWhenBottomAddressBarThenCollapsedRestCenterIsLowerByTheInsetReduction() {
        let insets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let capsuleHeight: CGFloat = 28
        let boundsMaxY: CGFloat = 844
        let previousRestCenterY = boundsMaxY - insets.bottom - FloatingDomainCapsuleController.restEdgePadding - capsuleHeight / 2
        let restCenterY = FloatingDomainCapsuleController.restCenterY(
            addressBarPosition: .bottom,
            expandedFrame: .zero,
            boundsMaxY: boundsMaxY,
            safeAreaInsets: insets,
            capsuleHeight: capsuleHeight)

        XCTAssertEqual(restCenterY, previousRestCenterY + FloatingDomainCapsuleController.restBottomInsetReduction, accuracy: 0.001)
    }

    func testWhenTopAddressBarThenCollapsedRestCenterAlignsWithTheBarsTopEdge() {
        let insets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let capsuleHeight: CGFloat = 28
        let expandedFrame = CGRect(x: 16, y: insets.top, width: 358, height: 60)
        let restCenterY = FloatingDomainCapsuleController.restCenterY(
            addressBarPosition: .top,
            expandedFrame: expandedFrame,
            boundsMaxY: 844,
            safeAreaInsets: insets,
            capsuleHeight: capsuleHeight)

        XCTAssertEqual(restCenterY - capsuleHeight / 2, expandedFrame.minY, accuracy: 0.001)
    }
}

final class WebViewPreviewSnapshotGeometryTests: XCTestCase {

    func testWhenWebViewBoundsAreValidThenVisibleRectUsesTheFullViewport() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 640)

        XCTAssertEqual(WebViewPreviewSnapshotGeometry.visibleRect(webViewBounds: bounds), bounds)
    }

    func testWhenViewportIsEmptyThenVisibleRectIsNil() {
        XCTAssertNil(WebViewPreviewSnapshotGeometry.visibleRect(webViewBounds: .zero))
    }

    func testWhenContentInsetIsGivenThenVisibleRectExcludesTopAndBottomInsets() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 640)
        let contentInset = UIEdgeInsets(top: 50, left: 0, bottom: 30, right: 0)

        XCTAssertEqual(WebViewPreviewSnapshotGeometry.visibleRect(webViewBounds: bounds, contentInset: contentInset),
                       CGRect(x: 0, y: 50, width: 320, height: 560))
    }

    func testWhenContentInsetHasHorizontalValuesThenVisibleRectKeepsFullWidth() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 640)
        let contentInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)

        XCTAssertEqual(WebViewPreviewSnapshotGeometry.visibleRect(webViewBounds: bounds, contentInset: contentInset),
                       bounds)
    }

    func testWhenContentInsetsExceedHeightThenVisibleRectIsNil() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 100)
        let contentInset = UIEdgeInsets(top: 60, left: 0, bottom: 60, right: 0)

        XCTAssertNil(WebViewPreviewSnapshotGeometry.visibleRect(webViewBounds: bounds, contentInset: contentInset))
    }

    func testWhenCapturingFullBoundsThenOnlyTheTopInsetIsCropped() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 640)
        let contentInset = UIEdgeInsets(top: 50, left: 0, bottom: 30, right: 0)

        XCTAssertEqual(WebViewPreviewSnapshotGeometry.visibleRect(webViewBounds: bounds,
                                                                  contentInset: contentInset,
                                                                  capturesFullBounds: true),
                       CGRect(x: 0, y: 50, width: 320, height: 590))
    }

    func testWhenNotCapturingFullBoundsThenTopAndBottomInsetsAreCropped() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 640)
        let contentInset = UIEdgeInsets(top: 50, left: 0, bottom: 30, right: 0)

        XCTAssertEqual(WebViewPreviewSnapshotGeometry.visibleRect(webViewBounds: bounds,
                                                                  contentInset: contentInset,
                                                                  capturesFullBounds: false),
                       CGRect(x: 0, y: 50, width: 320, height: 560))
    }
}

final class WebViewPreviewSnapshotPolicyTests: XCTestCase {

    func testWhenPageIsLoadingThenSnapshotIsSkipped() {
        XCTAssertFalse(WebViewPreviewSnapshotPolicy.shouldCapture(isLoading: true))
    }

    func testWhenPageIsNotLoadingThenSnapshotIsCaptured() {
        XCTAssertTrue(WebViewPreviewSnapshotPolicy.shouldCapture(isLoading: false))
    }
}

final class WebViewScrollViewInsetUpdaterTests: XCTestCase {

    func testWhenManagingInsetsThenAutomaticAdjustmentIsDisabledAndCanBeRestored() {
        let scrollView = UIScrollView()
        scrollView.contentInsetAdjustmentBehavior = .automatic
        scrollView.automaticallyAdjustsScrollIndicatorInsets = true

        let behavior = WebViewScrollViewInsetUpdater.beginManaging(scrollView)

        XCTAssertEqual(scrollView.contentInsetAdjustmentBehavior, .never)
        XCTAssertFalse(scrollView.automaticallyAdjustsScrollIndicatorInsets)

        WebViewScrollViewInsetUpdater.endManaging(scrollView, restoring: behavior)

        XCTAssertEqual(scrollView.contentInsetAdjustmentBehavior, .automatic)
        XCTAssertTrue(scrollView.automaticallyAdjustsScrollIndicatorInsets)
    }

    func testWhenContentInsetsAreUnchangedThenContentOffsetIsUnchanged() {
        let scrollView = UIScrollView()
        let insets = UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0)
        scrollView.contentInset = insets
        scrollView.contentOffset = CGPoint(x: 0, y: 40)

        WebViewScrollViewInsetUpdater.update(scrollView, insets: insets)

        XCTAssertEqual(scrollView.contentOffset, CGPoint(x: 0, y: 40))
    }

    func testWhenPinnedToTopThenUpdatingInsetsPreservesPinnedPosition() {
        let scrollView = UIScrollView()
        scrollView.contentInset = UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
        scrollView.contentOffset = CGPoint(x: 0, y: -20)

        WebViewScrollViewInsetUpdater.update(scrollView,
                                             insets: UIEdgeInsets(top: 50, left: 0, bottom: 30, right: 0))

        XCTAssertEqual(scrollView.contentOffset.y, -50)
    }

    func testWhenNotPinnedToTopThenUpdatingInsetsPreservesContentOffset() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        scrollView.contentSize = CGSize(width: 320, height: 2_000)
        scrollView.contentInset = UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
        scrollView.contentOffset = CGPoint(x: 0, y: 40)

        WebViewScrollViewInsetUpdater.update(scrollView,
                                             insets: UIEdgeInsets(top: 50, left: 0, bottom: 30, right: 0))

        XCTAssertEqual(scrollView.contentOffset.y, 40)
    }

    func testWhenUpdatingInsetsThenBothScrollIndicatorInsetsAreUpdated() {
        let scrollView = UIScrollView()
        let insets = UIEdgeInsets(top: 50, left: 2, bottom: 30, right: 4)

        WebViewScrollViewInsetUpdater.update(scrollView, insets: insets)

        XCTAssertEqual(scrollView.verticalScrollIndicatorInsets, insets)
        XCTAssertEqual(scrollView.horizontalScrollIndicatorInsets, insets)
    }

    func testWhenClearingInsetsThenContentAndIndicatorInsetsAreZero() {
        let scrollView = UIScrollView()
        let insets = UIEdgeInsets(top: 50, left: 2, bottom: 30, right: 4)
        scrollView.contentInset = insets
        scrollView.verticalScrollIndicatorInsets = insets
        scrollView.horizontalScrollIndicatorInsets = insets
        scrollView.contentOffset = CGPoint(x: 0, y: 40)

        WebViewScrollViewInsetUpdater.update(scrollView, insets: .zero)

        XCTAssertEqual(scrollView.contentInset, .zero)
        XCTAssertEqual(scrollView.verticalScrollIndicatorInsets, .zero)
        XCTAssertEqual(scrollView.horizontalScrollIndicatorInsets, .zero)
    }

    func testWhenChromeTransitionIsInProgressThenPreviouslyAppliedInsetsAreKept() {
        XCTAssertFalse(
            WebViewScrollViewInsetUpdater.shouldUpdateDuringChromeTransition(
                barsVisibilityPercent: 0.5,
                hasAppliedInsets: true
            )
        )
    }

    func testWhenChromeTransitionReachesEndpointsThenInsetsAreUpdated() {
        XCTAssertTrue(
            WebViewScrollViewInsetUpdater.shouldUpdateDuringChromeTransition(
                barsVisibilityPercent: 0,
                hasAppliedInsets: true
            )
        )
        XCTAssertTrue(
            WebViewScrollViewInsetUpdater.shouldUpdateDuringChromeTransition(
                barsVisibilityPercent: 1,
                hasAppliedInsets: true
            )
        )
    }

    func testWhenInsetsHaveNotBeenAppliedThenTheyAreUpdatedDuringChromeTransition() {
        XCTAssertTrue(
            WebViewScrollViewInsetUpdater.shouldUpdateDuringChromeTransition(
                barsVisibilityPercent: 0.5,
                hasAppliedInsets: false
            )
        )
    }
}

final class FloatingSwipePreviewGeometryTests: XCTestCase {

    private let superviewBounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    private let safeAreaInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)

    func testWhenDestinationIsAITabThenFrameFitsBetweenAIChrome() {
        let frame = FloatingSwipePreviewGeometry.destinationFrame(
            isAITab: true,
            superviewBounds: superviewBounds,
            contentContainerFrame: CGRect(x: 0, y: 50, width: 390, height: 760),
            safeAreaInsets: safeAreaInsets,
            aiHeaderHeight: 84,
            aiInputHeight: 120
        )

        XCTAssertEqual(frame, CGRect(x: 0, y: 93, width: 390, height: 547))
    }

    func testWhenDestinationIsRegularTabThenFrameUsesFullFloatingViewport() {
        let frame = FloatingSwipePreviewGeometry.destinationFrame(
            isAITab: false,
            superviewBounds: superviewBounds,
            contentContainerFrame: CGRect(x: 0, y: 143, width: 390, height: 547),
            safeAreaInsets: safeAreaInsets,
            aiHeaderHeight: 84,
            aiInputHeight: 120
        )

        XCTAssertEqual(frame, CGRect(x: 0, y: -143, width: 390, height: 844))
    }
}

final class SwipeTabBoundaryPolicyTests: XCTestCase {

    func testWhenOnlyOneTabIsAITabThenBoundaryIsCrossed() {
        XCTAssertTrue(SwipeTabBoundaryPolicy.crossesAITabBoundary(currentIsAITab: true, destinationIsAITab: false))
        XCTAssertTrue(SwipeTabBoundaryPolicy.crossesAITabBoundary(currentIsAITab: false, destinationIsAITab: true))
    }

    func testWhenTabsHaveSameTypeThenBoundaryIsNotCrossed() {
        XCTAssertFalse(SwipeTabBoundaryPolicy.crossesAITabBoundary(currentIsAITab: true, destinationIsAITab: true))
        XCTAssertFalse(SwipeTabBoundaryPolicy.crossesAITabBoundary(currentIsAITab: false, destinationIsAITab: false))
    }
}

final class LiveTabSwipePolicyTests: XCTestCase {

    func testWhenFloatingUIHasWebDestinationThenLiveDestinationIsUsed() {
        XCTAssertTrue(
            LiveTabSwipePolicy.shouldUseLiveDestination(
                isFloatingUIEnabled: true,
                hasWebDestination: true
            )
        )
    }

    func testWhenFloatingUIIsDisabledThenLiveDestinationIsNotUsed() {
        XCTAssertFalse(
            LiveTabSwipePolicy.shouldUseLiveDestination(
                isFloatingUIEnabled: false,
                hasWebDestination: true
            )
        )
    }

    func testWhenDestinationHasNoWebContentThenLiveDestinationIsNotUsed() {
        XCTAssertFalse(
            LiveTabSwipePolicy.shouldUseLiveDestination(
                isFloatingUIEnabled: true,
                hasWebDestination: false
            )
        )
    }

    func testWhenCommittingDifferentExistingTabThenDestinationViewIsKeptForTransition() {
        XCTAssertTrue(
            LiveTabSwipePolicy.shouldKeepDestinationView(
                targetIndex: 2,
                currentIndex: 1,
                tabCount: 3
            )
        )
    }

    func testWhenCancellingOrOpeningNewTabThenDestinationViewIsNotKept() {
        XCTAssertFalse(
            LiveTabSwipePolicy.shouldKeepDestinationView(
                targetIndex: 1,
                currentIndex: 1,
                tabCount: 3
            )
        )
        XCTAssertFalse(
            LiveTabSwipePolicy.shouldKeepDestinationView(
                targetIndex: 3,
                currentIndex: 2,
                tabCount: 3
            )
        )
    }
}

final class FloatingOmnibarSwipeGeometryTests: XCTestCase {

    private let bounds = CGRect(x: 0, y: 0, width: 300, height: 60)

    func testWhenSwipingLeftThenOutgoingCollapsesFromRightAndIncomingExpandsFromRight() {
        let rects = FloatingOmnibarSwipeGeometry.visibleRects(bounds: bounds, progress: 0.25, direction: .left)

        XCTAssertEqual(rects.outgoing, CGRect(x: 0, y: 0, width: 217, height: 60))
        XCTAssertEqual(rects.incoming, CGRect(x: 233, y: 0, width: 67, height: 60))
        XCTAssertEqual(rects.incoming.minX - rects.outgoing.maxX, 16)
    }

    func testWhenSwipingRightThenOutgoingCollapsesFromLeftAndIncomingExpandsFromLeft() {
        let rects = FloatingOmnibarSwipeGeometry.visibleRects(bounds: bounds, progress: 0.25, direction: .right)

        XCTAssertEqual(rects.outgoing, CGRect(x: 83, y: 0, width: 217, height: 60))
        XCTAssertEqual(rects.incoming, CGRect(x: 0, y: 0, width: 67, height: 60))
        XCTAssertEqual(rects.outgoing.minX - rects.incoming.maxX, 16)
    }

    func testWhenProgressExceedsBoundsThenGeometryIsClamped() {
        let beforeStart = FloatingOmnibarSwipeGeometry.visibleRects(bounds: bounds, progress: -1, direction: .left)
        let afterEnd = FloatingOmnibarSwipeGeometry.visibleRects(bounds: bounds, progress: 2, direction: .left)

        XCTAssertEqual(beforeStart.outgoing.width, bounds.width)
        XCTAssertEqual(beforeStart.incoming.width, 0)
        XCTAssertEqual(afterEnd.outgoing.width, 0)
        XCTAssertEqual(afterEnd.incoming.width, bounds.width)
    }

    func testWhenSwipeIsBeforeHandoffThenIncomingBarAndTextRemainHidden() {
        let morph = FloatingOmnibarSwipeMorph.values(progress: 0.19)

        XCTAssertEqual(morph.incomingBarAlpha, 0)
        XCTAssertEqual(morph.outgoingTextAlpha, 1)
        XCTAssertEqual(morph.incomingTextAlpha, 0)
    }

    func testWhenSwipeCrossesMidpointThenTextHandoffIsUnderway() {
        let morph = FloatingOmnibarSwipeMorph.values(progress: 0.5)

        XCTAssertEqual(morph.incomingBarAlpha, 1)
        XCTAssertEqual(morph.outgoingTextAlpha, 0)
        XCTAssertEqual(morph.incomingTextAlpha, 0.75, accuracy: 0.001)
    }

    func testWhenSwipingThenTextTracksMovingFieldEdges() {
        let left = FloatingOmnibarSwipeGeometry.visibleRects(bounds: bounds, progress: 0.25, direction: .left)
        let right = FloatingOmnibarSwipeGeometry.visibleRects(bounds: bounds, progress: 0.25, direction: .right)

        XCTAssertEqual(FloatingOmnibarSwipeGeometry.trailingTranslationX(bounds: bounds, visibleRect: left.outgoing), -83)
        XCTAssertEqual(FloatingOmnibarSwipeGeometry.leadingTranslationX(bounds: bounds, visibleRect: left.incoming), 233)
        XCTAssertEqual(FloatingOmnibarSwipeGeometry.leadingTranslationX(bounds: bounds, visibleRect: right.outgoing), 83)
        XCTAssertEqual(FloatingOmnibarSwipeGeometry.trailingTranslationX(bounds: bounds, visibleRect: right.incoming), -233)
    }

    func testWhenSwipeEndsThenToolbarRemovesMasksAndIncomingView() {
        let toolbar = BrowserToolbarView(frame: CGRect(x: 0, y: 0, width: 320, height: 140))
        let outgoingView = UIView()
        let incomingView = UIView()
        toolbar.setFloatingStyleEnabled(true)
        toolbar.setOmnibarView(outgoingView, height: 60)
        toolbar.layoutIfNeeded()

        toolbar.beginOmnibarSwipe(with: incomingView)
        toolbar.updateOmnibarSwipe(progress: 0.5, direction: .left)
        XCTAssertNotNil(outgoingView.layer.mask)
        XCTAssertNotNil(incomingView.layer.mask)

        toolbar.endOmnibarSwipe()
        XCTAssertNil(outgoingView.layer.mask)
        XCTAssertNil(incomingView.layer.mask)
        XCTAssertNil(incomingView.superview)
    }
}

final class ChromeMorphAnimatorCurveTests: XCTestCase {

    private let expandCurve = MainViewController.ChromeAnimationConstants.morphExpandCurve
    private let collapseCurve = MainViewController.ChromeAnimationConstants.morphCollapseCurve

    func testWhenCurveIsSmoothstepThenItEasesInAndOutSymmetrically() {
        let curve = ChromeMorphAnimator.Curve.smoothstep

        XCTAssertEqual(curve.value(at: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(curve.value(at: 0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(curve.value(at: 1), 1, accuracy: 0.0001)
    }

    func testWhenCurveIsEaseOutCubicThenItStartsFastAndDecelerates() {
        let curve = ChromeMorphAnimator.Curve.easeOutCubic

        XCTAssertEqual(curve.value(at: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(curve.value(at: 0.5), 0.875, accuracy: 0.0001)
        XCTAssertEqual(curve.value(at: 1), 1, accuracy: 0.0001)
        XCTAssertGreaterThan(curve.value(at: 0.25), 0.5)
    }

    func testWhenCollapsingThenTheCurveNeverOvershoots() {
        for step in 0...100 {
            let value = collapseCurve.value(at: CGFloat(step) / 100)
            XCTAssertLessThanOrEqual(value, 1.0, "Collapse must not overshoot at t = \(CGFloat(step) / 100)")
        }
    }

    func testWhenExpandingThenTheSpringSettlesByTheEndOfItsDuration() {
        XCTAssertEqual(expandCurve.value(at: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(expandCurve.value(at: 1),
                       1,
                       accuracy: 0.001,
                       "Residual at the cutoff becomes a snap. Raise naturalFrequency or the damping ratio.")
    }

    func testWhenExpandingThenOvershootStaysBelowOnePointFivePercent() {
        var peak: CGFloat = 0
        for step in 0...200 {
            peak = max(peak, expandCurve.value(at: CGFloat(step) / 200))
        }

        XCTAssertGreaterThan(peak, 1.0, "A lightly damped spring is expected to overshoot slightly")
        XCTAssertLessThan(peak, 1.015, "Overshoot on a bar that clips the screen edge reads as a glitch")
    }

    func testWhenSpringIsCriticallyDampedThenItNeverOvershoots() {
        let curve = ChromeMorphAnimator.Curve.spring(dampingRatio: 1, naturalFrequency: 8.84)

        for step in 0...100 {
            XCTAssertLessThanOrEqual(curve.value(at: CGFloat(step) / 100), 1.0)
        }
        XCTAssertEqual(curve.value(at: 1), 1, accuracy: 0.01)
    }
}
