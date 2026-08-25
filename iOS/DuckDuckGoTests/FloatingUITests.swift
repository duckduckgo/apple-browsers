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

    func testWhenContextualOnboardingVisibleThenTopInsetIsTheObscuredTopRegion() {
        let inset = FloatingUILayoutPolicy.contextualOnboardingTopInset(
            isFloatingUIEnabled: true,
            isContextualOnboardingVisible: true,
            topObscuredHeight: 111
        )

        XCTAssertEqual(inset, 111, accuracy: 0.001)
    }

    func testWhenNoContextualOnboardingThenTopInsetIsZero() {
        let inset = FloatingUILayoutPolicy.contextualOnboardingTopInset(
            isFloatingUIEnabled: true,
            isContextualOnboardingVisible: false,
            topObscuredHeight: 111
        )

        XCTAssertEqual(inset, 0, accuracy: 0.001)
    }

    func testWhenFloatingUIDisabledThenContextualOnboardingTopInsetIsZero() {
        // The classic layout already puts the dialog below the chrome.
        let inset = FloatingUILayoutPolicy.contextualOnboardingTopInset(
            isFloatingUIEnabled: false,
            isContextualOnboardingVisible: true,
            topObscuredHeight: 111
        )

        XCTAssertEqual(inset, 0, accuracy: 0.001)
    }

    func testWhenUnifiedInputActiveWithTopAddressBarThenNewTabPageTopObscuredHeightIsCardBottomEdge() {
        let height = FloatingUILayoutPolicy.newTabPageUnifiedInputTopObscuredHeight(
            isFloatingUIEnabled: true,
            isUnifiedToggleInputActive: true,
            addressBarPosition: .top,
            cardBottomEdge: 191
        )

        XCTAssertEqual(height, 191, accuracy: 0.001)
    }

    func testWhenUnifiedInputInactiveThenNewTabPageTopObscuredHeightIsZero() {
        let height = FloatingUILayoutPolicy.newTabPageUnifiedInputTopObscuredHeight(
            isFloatingUIEnabled: true,
            isUnifiedToggleInputActive: false,
            addressBarPosition: .top,
            cardBottomEdge: 191
        )

        XCTAssertEqual(height, 0, accuracy: 0.001)
    }

    func testWhenBottomAddressBarThenNewTabPageTopObscuredHeightIsZero() {
        // A bottom-position card obscures nothing at the top.
        let height = FloatingUILayoutPolicy.newTabPageUnifiedInputTopObscuredHeight(
            isFloatingUIEnabled: true,
            isUnifiedToggleInputActive: true,
            addressBarPosition: .bottom,
            cardBottomEdge: 191
        )

        XCTAssertEqual(height, 0, accuracy: 0.001)
    }

    func testWhenFloatingUIDisabledThenNewTabPageTopObscuredHeightIsZero() {
        // The classic layout puts the card above the page.
        let height = FloatingUILayoutPolicy.newTabPageUnifiedInputTopObscuredHeight(
            isFloatingUIEnabled: false,
            isUnifiedToggleInputActive: true,
            addressBarPosition: .top,
            cardBottomEdge: 191
        )

        XCTAssertEqual(height, 0, accuracy: 0.001)
    }

    func testWhenChromeHiddenPushesCardOffScreenThenNewTabPageTopObscuredHeightIsZero() {
        // The card's top constant goes negative as the chrome hides; don't lift the dialog off-page.
        let height = FloatingUILayoutPolicy.newTabPageUnifiedInputTopObscuredHeight(
            isFloatingUIEnabled: true,
            isUnifiedToggleInputActive: true,
            addressBarPosition: .top,
            cardBottomEdge: -40
        )

        XCTAssertEqual(height, 0, accuracy: 0.001)
    }

    func testWhenObscuredTopIsNegativeThenContextualOnboardingTopInsetIsClampedToZero() {
        let inset = FloatingUILayoutPolicy.contextualOnboardingTopInset(
            isFloatingUIEnabled: true,
            isContextualOnboardingVisible: true,
            topObscuredHeight: -20
        )

        XCTAssertEqual(inset, 0, accuracy: 0.001)
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

    func testWhenGlassAppearanceIsUnchangedThenMakingGlassPreservesGlassView() throws {
        let barView = DefaultOmniBarView.create(isFloatingUIEnabled: true)
        barView.frame = CGRect(x: 0, y: 0, width: 390, height: DefaultOmniBarView.expectedHeight)
        barView.layoutIfNeeded()
        let glassView = try XCTUnwrap(firstGlassView(in: barView.searchContainer))

        barView.makeGlass()

        XCTAssertTrue(firstGlassView(in: barView.searchContainer) === glassView)
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
    private func update(barsVisibilityPercent: CGFloat, reduceMotion: Bool = false) -> UIButton? {
        controller.update(addressBarPosition: .top,
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

    func testWhenCapturingFullBoundsThenContentInsetsDoNotCropTheViewport() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 640)
        let contentInset = UIEdgeInsets(top: 50, left: 0, bottom: 30, right: 0)

        XCTAssertEqual(WebViewPreviewSnapshotGeometry.visibleRect(webViewBounds: bounds,
                                                                  contentInset: contentInset,
                                                                  capturesFullBounds: true),
                       bounds)
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
