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
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.floatingUI]),
            isPadProvider: { false },
            isSupportedOSProvider: { true },
            unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider(isAvailable: true)
        )

        XCTAssertTrue(manager.isFloatingUIEnabled)
    }

    func testWhenFloatingUIIsEnabledButUnifiedToggleInputIsUnavailableThenFloatingUIIsDisabled() {
        let manager = FloatingUIManager(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.floatingUI]),
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
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.floatingUI]),
            isPadProvider: { true },
            isSupportedOSProvider: { true },
            unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider(isAvailable: true)
        )

        XCTAssertFalse(manager.isFloatingUIEnabled)
    }

    func testWhenOSIsUnsupportedThenFloatingUIIsDisabled() {
        let manager = FloatingUIManager(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.floatingUI]),
            isPadProvider: { false },
            isSupportedOSProvider: { false },
            unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProvider(isAvailable: true)
        )

        XCTAssertFalse(manager.isFloatingUIEnabled)
    }
}

final class FloatingUILayoutPolicyTests: XCTestCase {

    func testWhenTopAddressBarThenAdditionalSafeAreaInsetsApplyOmniBarHeightToTopOnly() {
        let insets = FloatingUILayoutPolicy.webViewAdditionalSafeAreaInsets(
            addressBarPosition: .top,
            isUnifiedToggleInputAffectingLayout: false,
            omniBarHeight: 52
        )

        XCTAssertEqual(insets, UIEdgeInsets(top: 52, left: 0, bottom: 0, right: 0))
    }

    func testWhenBottomAddressBarThenAdditionalSafeAreaInsetsAreZero() {
        let insets = FloatingUILayoutPolicy.webViewAdditionalSafeAreaInsets(
            addressBarPosition: .bottom,
            isUnifiedToggleInputAffectingLayout: false,
            omniBarHeight: 52
        )

        XCTAssertEqual(insets, .zero)
    }

    func testWhenUnifiedToggleInputAffectsLayoutThenInsetsAreZero() {
        let topInsets = FloatingUILayoutPolicy.webViewAdditionalSafeAreaInsets(
            addressBarPosition: .top,
            isUnifiedToggleInputAffectingLayout: true,
            omniBarHeight: 52
        )
        XCTAssertEqual(topInsets, .zero)

        let bottomInsets = FloatingUILayoutPolicy.webViewAdditionalSafeAreaInsets(
            addressBarPosition: .bottom,
            isUnifiedToggleInputAffectingLayout: true,
            omniBarHeight: 52
        )
        XCTAssertEqual(bottomInsets, .zero)
    }

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
