//
//  BrowserToolbarViewTests.swift
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

import DesignResourcesKitIcons
import SitePermissions
import XCTest
@testable import DuckDuckGo

final class BrowserToolbarViewTests: XCTestCase {

    private let omnibarHeight: CGFloat = 60

    private func makeSUT(floating: Bool = true, embeddedOmnibar: Bool = true) -> BrowserToolbarView {
        let toolbar = BrowserToolbarView(frame: CGRect(x: 0, y: 0, width: 390, height: 200))
        toolbar.setFloatingStyleEnabled(floating)
        if embeddedOmnibar {
            toolbar.setOmnibarView(UIView(), height: omnibarHeight)
        }
        toolbar.layoutIfNeeded()
        return toolbar
    }

    func testWhenProgressIsZeroThenButtonRowIsFullyShownAtFullHeight() {
        let sut = makeSUT()
        let fullHeight = BrowserToolbarView.totalHeight(withOmnibarHeight: omnibarHeight, isFloating: true)

        let height = sut.setButtonRowCollapseProgress(0, reduceMotion: false)

        XCTAssertEqual(height, fullHeight, accuracy: 0.01)
    }

    func testWhenProgressIsOneThenButtonRowIsGoneAtSingleRowHeight() {
        let sut = makeSUT()
        let singleRowHeight = BrowserToolbarView.singleRowHeight(withOmnibarHeight: omnibarHeight)

        let height = sut.setButtonRowCollapseProgress(1, reduceMotion: false)

        XCTAssertEqual(height, singleRowHeight, accuracy: 0.01)
    }

    func testWhenProgressIsHalfThenHeightIsBetweenFullAndSingleRow() {
        let sut = makeSUT()
        let fullHeight = BrowserToolbarView.totalHeight(withOmnibarHeight: omnibarHeight, isFloating: true)
        let singleRowHeight = BrowserToolbarView.singleRowHeight(withOmnibarHeight: omnibarHeight)

        let height = sut.setButtonRowCollapseProgress(0.5, reduceMotion: false)

        XCTAssertEqual(height, (fullHeight + singleRowHeight) / 2, accuracy: 0.01)
    }

    func testWhenReduceMotionThenProgressIsIgnoredAndButtonRowStaysFullyShown() {
        let sut = makeSUT()
        let fullHeight = BrowserToolbarView.totalHeight(withOmnibarHeight: omnibarHeight, isFloating: true)

        let height = sut.setButtonRowCollapseProgress(1, reduceMotion: true)

        XCTAssertEqual(height, fullHeight, accuracy: 0.01)
    }

    func testWhenNoEmbeddedOmnibarThenProgressIsANoOp() {
        let sut = makeSUT(embeddedOmnibar: false)
        let buttonsOnlyHeight = BrowserToolbarView.totalHeight(withOmnibarHeight: 0, isFloating: true)

        let height = sut.setButtonRowCollapseProgress(1, reduceMotion: false)

        XCTAssertEqual(height, buttonsOnlyHeight, accuracy: 0.01)
    }

    func testWhenStandaloneCollapseProgressIsAppliedThenGlassScaleStaysIdentity() {
        let sut = makeSUT(embeddedOmnibar: false)

        sut.setStandaloneCollapseProgress(1, reduceMotion: false)

        func visualEffectView(in view: UIView) -> UIVisualEffectView? {
            if let view = view as? UIVisualEffectView { return view }
            return view.subviews.lazy.compactMap { visualEffectView(in: $0) }.first
        }

        guard let glass = visualEffectView(in: sut) else {
            XCTFail("Missing glass effect view")
            return
        }
        XCTAssertEqual(glass.transform.a, 1, accuracy: 0.001)
        XCTAssertEqual(glass.transform.d, 1, accuracy: 0.001)
        XCTAssertEqual(glass.transform.ty, 0, accuracy: 0.001)
    }

    func testWhenStandaloneCollapseProgressIsAppliedThenIconsAreNotInsideGlassContentView() {
        let sut = makeSUT(embeddedOmnibar: false)
        let fire = makeToolbarButton(identifier: "Browser.Toolbar.Button.Fire", width: 44)
        sut.setToolbarButtons([fire])
        sut.layoutIfNeeded()

        var ancestor: UIView? = fire.superview
        var isInsideGlassContentView = false
        while let view = ancestor {
            if view.superview is UIVisualEffectView {
                isInsideGlassContentView = true
                break
            }
            ancestor = view.superview
        }

        XCTAssertFalse(isInsideGlassContentView)
    }

    func testWhenStandaloneGlassUsesDarkAppearanceThenItHasAContrastTint() throws {
        guard #available(iOS 26.0, *) else { return }
        let sut = makeSUT(embeddedOmnibar: false)

        sut.refreshMaterialAppearance(interfaceStyle: .dark)

        let glassView = try XCTUnwrap(firstVisualEffectView(in: sut))
        XCTAssertNotNil((glassView.effect as? UIGlassEffect)?.tintColor)

        sut.refreshMaterialAppearance(interfaceStyle: .light)

        XCTAssertNil((glassView.effect as? UIGlassEffect)?.tintColor)
    }

    func testWhenNotFloatingThenProgressIsANoOp() {
        let sut = makeSUT(floating: false)
        let legacyFullHeight = BrowserToolbarView.totalHeight(withOmnibarHeight: omnibarHeight, isFloating: false)

        let height = sut.setButtonRowCollapseProgress(1, reduceMotion: false)

        XCTAssertEqual(height, legacyFullHeight, accuracy: 0.01)
    }

    private func firstVisualEffectView(in view: UIView) -> UIVisualEffectView? {
        if let view = view as? UIVisualEffectView { return view }
        return view.subviews.lazy.compactMap { self.firstVisualEffectView(in: $0) }.first
    }

    func testWhenButtonRowIsMidCollapseThenRestingCapsuleFrameStillReportsSingleRowHeight() {
        let sut = makeSUT()
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        container.addSubview(sut)
        let singleRowHeight = BrowserToolbarView.singleRowHeight(withOmnibarHeight: omnibarHeight)

        _ = sut.setButtonRowCollapseProgress(0, reduceMotion: false)
        let heightAtStart = sut.restingCapsuleFrame(in: container).height

        _ = sut.setButtonRowCollapseProgress(0.3, reduceMotion: false)
        let heightMidCollapse = sut.restingCapsuleFrame(in: container).height

        XCTAssertEqual(heightAtStart, singleRowHeight, accuracy: 0.01)
        XCTAssertEqual(heightMidCollapse, singleRowHeight, accuracy: 0.01,
                       "restingCapsuleFrame must not track the live, mid-animation panel height")
    }

    func testWhenNoEmbeddedOmnibarThenRestingCapsuleFrameUsesTheLiveButtonsOnlyHeight() {
        let sut = makeSUT(embeddedOmnibar: false)
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        container.addSubview(sut)

        let height = sut.restingCapsuleFrame(in: container).height

        XCTAssertEqual(height, BrowserToolbarView.floatingButtonsHeight, accuracy: 0.01)
    }

    func testWhenFloatingThenCombinedChromeHeightMatchesTheSpacingSpec() {
        // 14 top + 48 field + 12 gap + 44 buttons + 16 bottom.
        XCTAssertEqual(BrowserToolbarView.floatingEmbeddedButtonsHeight, 44)
        XCTAssertEqual(BrowserToolbarView.floatingEmbeddedTopContentPadding, 14)
        XCTAssertEqual(BrowserToolbarView.floatingEmbeddedBottomContentPadding, 16)
        XCTAssertEqual(
            BrowserToolbarView.totalHeight(withOmnibarHeight: 48, isFloating: true),
            134,
            accuracy: 0.01)
        XCTAssertEqual(
            BrowserToolbarView.singleRowHeight(withOmnibarHeight: 48),
            78,
            accuracy: 0.01)
    }

    func testWhenFloatingWithoutEmbeddedOmnibarThenStandaloneButtonHeightIsUnchanged() {
        XCTAssertEqual(BrowserToolbarView.floatingButtonsHeight, 62)
        XCTAssertEqual(
            BrowserToolbarView.totalHeight(withOmnibarHeight: 0, isFloating: true),
            BrowserToolbarView.floatingButtonsHeight,
            accuracy: 0.01)
    }

    func testWhenStandaloneFloatingThenOuterInsetFollowsConcentricSafeArea() {
        let sut = makeSUT(embeddedOmnibar: false)
        // The safe area layout guide only resolves inside a window; without one it stays empty
        // and the trailing edge is measured against a degenerate guide.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        let container = UIView(frame: window.bounds)
        window.addSubview(container)
        window.makeKeyAndVisible()
        container.addSubview(sut)
        container.layoutIfNeeded()

        let frame = sut.restingCapsuleFrame(in: container)

        if #available(iOS 26.0, *) {
            // Standalone shares the combined chrome's physical inset, so the two line up.
            XCTAssertEqual(frame.minX, BrowserToolbarView.floatingEmbeddedConcentricInset, accuracy: 0.01)
            XCTAssertEqual(container.bounds.width - frame.maxX, BrowserToolbarView.floatingEmbeddedConcentricInset, accuracy: 0.01)
            XCTAssertEqual(container.bounds.maxY - frame.maxY, BrowserToolbarView.floatingEmbeddedConcentricInset, accuracy: 0.01)
        } else {
            XCTAssertEqual(BrowserToolbarView.floatingStandaloneButtonRowHorizontalPadding, 16)
            XCTAssertEqual(BrowserToolbarView.floatingStandaloneHorizontalInset, 24)
            XCTAssertEqual(frame.minX, 24, accuracy: 0.01)
            XCTAssertEqual(container.bounds.width - frame.maxX, 24, accuracy: 0.01)
        }
    }

    func testWhenEmbeddedFloatingThenOuterInsetsMatchTheBottomChromeSpec() {
        let sut = makeSUT(embeddedOmnibar: true)
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        container.addSubview(sut)
        container.layoutIfNeeded()

        let frame = sut.restingCapsuleFrame(in: container)

        if #available(iOS 26.0, *) {
            XCTAssertEqual(frame.minX, BrowserToolbarView.floatingEmbeddedHorizontalInset, accuracy: 0.01)
            XCTAssertEqual(container.bounds.width - frame.maxX, BrowserToolbarView.floatingEmbeddedHorizontalInset, accuracy: 0.01)
            XCTAssertEqual(container.bounds.maxY - frame.maxY, BrowserToolbarView.floatingEmbeddedBottomMargin, accuracy: 0.01)
        } else {
            XCTAssertEqual(BrowserToolbarView.floatingEmbeddedHorizontalInset, 16)
            XCTAssertEqual(frame.minX, 16, accuracy: 0.01)
            XCTAssertEqual(container.bounds.width - frame.maxX, 16, accuracy: 0.01)
        }
    }

    func testWhenHorizontalGuideInsetIsSmallerThanConcentricInsetThenInnerInsetFillsTheGap() {
        let concentric = BrowserToolbarView.floatingEmbeddedConcentricInset
        XCTAssertEqual(BrowserToolbarView.embeddedRestStateInnerInset(guideInset: 0), concentric, accuracy: 0.01)
        XCTAssertEqual(BrowserToolbarView.embeddedRestStateInnerInset(guideInset: 16), concentric - 16, accuracy: 0.01)
        XCTAssertEqual(BrowserToolbarView.embeddedRestStateInnerInset(guideInset: concentric), 0, accuracy: 0.01)
    }

    func testWhenHorizontalGuideInsetExceedsConcentricInsetThenInnerInsetIsClampedToZero() {
        let concentric = BrowserToolbarView.floatingEmbeddedConcentricInset
        XCTAssertEqual(BrowserToolbarView.embeddedRestStateInnerInset(guideInset: concentric + 1), 0, accuracy: 0.01)
        XCTAssertEqual(BrowserToolbarView.embeddedRestStateInnerInset(guideInset: 59), 0, accuracy: 0.01)
        XCTAssertEqual(BrowserToolbarView.embeddedRestStateInnerInset(guideInset: -8), concentric, accuracy: 0.01)
    }

    func testWhenGuidesAreAsymmetricThenEachEdgeIsCompensatedFromItsOwnGuide() {
        guard #available(iOS 26.0, *) else { return }
        let concentric = BrowserToolbarView.floatingEmbeddedConcentricInset
        // Landscape with the Dynamic Island on the leading edge only.
        let container = SafeAreaStubView(frame: CGRect(x: 0, y: 0, width: 844, height: 390))
        container.stubbedSafeAreaInsets = UIEdgeInsets(top: 0, left: concentric + 39, bottom: 21, right: 0)
        let sut = makeSUT(embeddedOmnibar: true)
        container.addSubview(sut)
        container.layoutIfNeeded()

        let frame = sut.restingCapsuleFrame(in: container)
        let guideInsets = BrowserToolbarView.horizontalGuideInsets(in: container)
        let physical = BrowserToolbarView.floatingEmbeddedHorizontalInset

        // Each edge sits at its own guide, or at the physical inset when the guide is smaller.
        XCTAssertEqual(frame.minX, max(guideInsets.left, physical), accuracy: 0.01)
        XCTAssertEqual(container.bounds.width - frame.maxX, max(guideInsets.right, physical), accuracy: 0.01)
        // The wide leading guide must not pull the opposite edge inside the physical inset.
        XCTAssertGreaterThanOrEqual(container.bounds.width - frame.maxX, physical - 0.01)
    }

    func testWhenConcentricGuideHasResolvedThenThePillTucksInFromTheGuide() {
        // Resolved guide wins over the fallback; the narrower side wins under a Dynamic Island.
        let tuck = BrowserToolbarView.floatingConcentricTuck
        XCTAssertEqual(BrowserToolbarView.floatingPhysicalInset(guideInsets: (left: 18, right: 18)), 18 + tuck, accuracy: 0.01)
        XCTAssertEqual(BrowserToolbarView.floatingPhysicalInset(guideInsets: (left: 57, right: 18)), 18 + tuck, accuracy: 0.01)
        XCTAssertEqual(BrowserToolbarView.embeddedRestStateInnerInset(guideInset: 18, physicalInset: 18 + tuck), tuck, accuracy: 0.01)
        XCTAssertEqual(BrowserToolbarView.embeddedRestStateBottomOffset(guideBottomGap: 34, physicalInset: 18 + tuck), 34 - 18 - tuck, accuracy: 0.01)
    }

    func testWhenConcentricGuideIsUnresolvedThenTheFallbackInsetIsUsed() {
        let concentric = BrowserToolbarView.floatingEmbeddedConcentricInset
        XCTAssertEqual(BrowserToolbarView.floatingPhysicalInset(guideInsets: (left: 0, right: 0)), concentric, accuracy: 0.01)
        XCTAssertEqual(BrowserToolbarView.floatingPhysicalInset(guideInsets: (left: 0.5, right: 0.5)), concentric, accuracy: 0.01)
        XCTAssertEqual(BrowserToolbarView.floatingPhysicalInset(guideInsets: (left: 57, right: 0)), concentric, accuracy: 0.01)
    }

    func testWhenGuideGapExceedsConcentricInsetThenGlassShiftsDown() {
        let concentric = BrowserToolbarView.floatingEmbeddedConcentricInset
        // Home indicator: the guide stops short of the bottom, so the glass moves down to it.
        XCTAssertEqual(
            BrowserToolbarView.embeddedRestStateBottomOffset(guideBottomGap: 34),
            34 - concentric,
            accuracy: 0.01)
    }

    func testWhenGuideReachesPhysicalBottomThenGlassShiftsUpToKeepTheInset() {
        let concentric = BrowserToolbarView.floatingEmbeddedConcentricInset
        // No home indicator: the guide already sits at the bottom, so the glass must move up to
        // leave the same inset that restingCapsuleFrame reports, rather than sitting flush.
        XCTAssertEqual(
            BrowserToolbarView.embeddedRestStateBottomOffset(guideBottomGap: 0),
            -concentric,
            accuracy: 0.01)
        XCTAssertEqual(
            BrowserToolbarView.embeddedRestStateBottomOffset(guideBottomGap: concentric),
            0,
            accuracy: 0.01)
    }

    func testWhenSafeAreaGuideIsUnresolvedThenCapsuleStaysWithinBounds() {
        guard #available(iOS 26.0, *) else { return }
        // No window, so the corner-adapted guide never resolves and its layout frame is empty.
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))

        for embedded in [true, false] {
            let sut = makeSUT(embeddedOmnibar: embedded)
            container.addSubview(sut)
            container.layoutIfNeeded()

            let frame = sut.restingCapsuleFrame(in: container)

            XCTAssertGreaterThanOrEqual(frame.width, 0, "embedded: \(embedded)")
            XCTAssertGreaterThanOrEqual(frame.minX, 0, "embedded: \(embedded)")
            XCTAssertLessThanOrEqual(frame.maxX, container.bounds.maxX, "embedded: \(embedded)")
            sut.removeFromSuperview()
        }
    }

    func testWhenBottomOmnibarDetachmentSettlesThenOuterInsetsMatchStandaloneConcentricSpec() {
        let sut = makeSUT(embeddedOmnibar: true)
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        container.addSubview(sut)
        sut.prepareForOmnibarDetachment()
        sut.applyOmnibarDetachmentPose()
        container.layoutIfNeeded()

        let frame = sut.restingCapsuleFrame(in: container)

        if #available(iOS 26.0, *) {
            // Settled: it's a standalone capsule again, not tucked at the tight embedded margin.
            XCTAssertEqual(frame.minX, BrowserToolbarView.floatingEmbeddedConcentricInset, accuracy: 0.01)
            XCTAssertEqual(container.bounds.width - frame.maxX, BrowserToolbarView.floatingEmbeddedConcentricInset, accuracy: 0.01)
            XCTAssertEqual(container.bounds.maxY - frame.maxY, BrowserToolbarView.floatingEmbeddedConcentricInset, accuracy: 0.01)
        }
    }

    func testWhenStandaloneFloatingThenBottomMarginMatchesCombinedChrome() {
        let sut = makeSUT(embeddedOmnibar: false)

        if #available(iOS 26.0, *) {
            XCTAssertEqual(sut.floatingBottomMargin, BrowserToolbarView.floatingEmbeddedConcentricInset, accuracy: 0.01)
            XCTAssertEqual(BrowserToolbarView.floatingOuterHorizontalInset(for: .top), BrowserToolbarView.floatingEmbeddedConcentricInset)
            XCTAssertEqual(BrowserToolbarView.floatingBottomMargin(for: .top), BrowserToolbarView.floatingEmbeddedConcentricInset)
        } else {
            XCTAssertEqual(BrowserToolbarView.floatingStandaloneBottomMargin, 21)
            XCTAssertEqual(sut.floatingBottomMargin, 21, accuracy: 0.01)
            XCTAssertEqual(BrowserToolbarView.floatingOuterHorizontalInset(for: .top), 24)
            XCTAssertEqual(BrowserToolbarView.floatingBottomMargin(for: .top), 21)
        }
    }

    func testWhenEmbeddedFloatingThenBottomMarginMatchesPlatformGeometry() {
        let sut = makeSUT(embeddedOmnibar: true)

        // Even on every edge: the bottom margin matches the horizontal inset.
        XCTAssertEqual(BrowserToolbarView.floatingEmbeddedBottomMargin, 16)
        if #available(iOS 26.0, *) {
            XCTAssertEqual(sut.floatingBottomMargin, 16, accuracy: 0.01)
            XCTAssertEqual(BrowserToolbarView.floatingOuterHorizontalInset(for: .bottom), 16)
            XCTAssertEqual(BrowserToolbarView.floatingBottomMargin(for: .bottom), 16)
        } else {
            XCTAssertEqual(sut.floatingBottomMargin, 16, accuracy: 0.01)
            XCTAssertEqual(BrowserToolbarView.floatingOuterHorizontalInset(for: .bottom), 16)
            XCTAssertEqual(BrowserToolbarView.floatingBottomMargin(for: .bottom), 16)
        }
    }

    func testWhenEmbeddedFloatingThenToolbarIconsAlignWithTheAddressBarIcons() {
        let sut = makeSUT(embeddedOmnibar: true)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        sut.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(sut)
        NSLayoutConstraint.activate([
            sut.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            sut.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            sut.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        sut.setToolbarButtons([
            makeToolbarButton(identifier: "back", width: 44),
            makeToolbarButton(identifier: "forward", width: 44),
            makeToolbarButton(identifier: "Browser.Toolbar.Button.Fire", width: 44),
            makeToolbarButton(identifier: "tabs", width: 44),
            makeToolbarButton(identifier: "menu", width: 44)
        ])
        window.layoutIfNeeded()

        let centers = sut.arrangedToolbarButtonViews.map { window.convert($0.center, from: $0.superview).x }
        guard let first = centers.min(), let last = centers.max() else {
            XCTFail("Missing toolbar buttons")
            return
        }
        // The address field is hosted inside the same glass capsule, so its icons are inset from
        // the capsule's edges rather than the toolbar view's.
        let capsule = sut.restingCapsuleFrame(in: window)

        // Both rows carry 44pt controls, so aligned centres mean the same distance from the glass
        // edge as the address field's icons: its 16pt text-area padding plus half a control.
        let expectedInset = BrowserToolbarView.floatingEmbeddedAddressBarIconInset
        XCTAssertEqual(first - capsule.minX, expectedInset, accuracy: 0.5)
        XCTAssertEqual(capsule.maxX - last, expectedInset, accuracy: 0.5)
    }

    func testWhenStandaloneFloatingThenOuterButtonsSitWhereTheCombinedChromeIconsDo() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Floating UI is iOS 26+") }
        let sut = makeSUT(embeddedOmnibar: false)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        sut.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(sut)
        window.makeKeyAndVisible()
        let horizontalGuide = window.layoutGuide(for: .safeArea(cornerAdaptation: .horizontal))
        NSLayoutConstraint.activate([
            sut.leadingAnchor.constraint(equalTo: horizontalGuide.leadingAnchor),
            sut.trailingAnchor.constraint(equalTo: horizontalGuide.trailingAnchor),
            sut.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            sut.heightAnchor.constraint(equalToConstant: 62)
        ])
        sut.setToolbarButtons([
            makeToolbarButton(identifier: "back", width: 44),
            makeToolbarButton(identifier: "forward", width: 44),
            makeToolbarButton(identifier: "fire", width: 44),
            makeToolbarButton(identifier: "tabs", width: 44),
            makeToolbarButton(identifier: "menu", width: 44)
        ])
        window.layoutIfNeeded()

        let centers = sut.arrangedToolbarButtonViews.map { view in
            window.convert(view.center, from: view.superview).x
        }
        let first = try XCTUnwrap(centers.first)
        let last = try XCTUnwrap(centers.last)
        let capsule = sut.restingCapsuleFrame(in: window)

        // Outer buttons land where the combined chrome's icons do.
        let expectedInset = BrowserToolbarView.floatingEmbeddedAddressBarIconInset
        XCTAssertEqual(first - capsule.minX, expectedInset, accuracy: 0.5)
        XCTAssertEqual(capsule.maxX - last, expectedInset, accuracy: 0.5)
    }

    func testWhenStandaloneFloatingThenButtonsAreEvenlySpacedAndFireButtonIsCentered() {
        let sut = makeSUT(embeddedOmnibar: false)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        sut.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(sut)
        NSLayoutConstraint.activate([
            sut.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            sut.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            sut.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            sut.heightAnchor.constraint(equalToConstant: 62)
        ])
        let fire = makeToolbarButton(identifier: "Browser.Toolbar.Button.Fire", width: 44)
        sut.setToolbarButtons([
            makeToolbarButton(identifier: "back", width: 44),
            makeToolbarButton(identifier: "forward", width: 44),
            fire,
            makeToolbarButton(identifier: "tabs", width: 44),
            makeToolbarButton(identifier: "menu", width: 44)
        ])
        window.layoutIfNeeded()

        let centers = sut.arrangedToolbarButtonViews.map { view in
            sut.convert(view.center, from: view.superview).x
        }
        let spacings = zip(centers.dropFirst(), centers).map { $0 - $1 }
        let fireCenterInToolbar = sut.convert(fire.center, from: fire.superview)

        XCTAssertEqual(fireCenterInToolbar.x, sut.bounds.midX, accuracy: 0.5)
        spacings.dropFirst().forEach {
            XCTAssertEqual($0, spacings[0], accuracy: 0.5)
        }
    }

    private func makeToolbarButton(identifier: String, width: CGFloat) -> UIView {
        let view = UIView()
        view.accessibilityIdentifier = identifier
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        view.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return view
    }

    func testWhenButtonRowCollapsesThenEmbeddedOmnibarKeepsItsHeight() {
        let fieldHeight: CGFloat = 48
        let omnibar = UIView()
        let toolbar = BrowserToolbarView(frame: .zero)
        toolbar.setFloatingStyleEnabled(true)
        toolbar.setOmnibarView(omnibar, height: fieldHeight)

        let collapsedHeight = toolbar.setButtonRowCollapseProgress(1, reduceMotion: false)
        toolbar.frame = CGRect(x: 0, y: 0, width: 390, height: collapsedHeight)
        toolbar.layoutIfNeeded()

        XCTAssertEqual(omnibar.bounds.height, fieldHeight, accuracy: 0.5)
    }

    func testWhenNotFloatingThenCombinedChromeHeightKeepsLegacyPadding() {
        XCTAssertEqual(
            BrowserToolbarView.totalHeight(withOmnibarHeight: 60, isFloating: false),
            115,
            accuracy: 0.01)
    }
}

@MainActor
final class SitePermissionMenuAnimationTests: XCTestCase {

    func testWhenBadgesAreShownThenVisibleSizesAreComparableAndClearTheMenuDuringTheSpring() throws {
        // Visible bounds of the paths in the shared 16 pt SVG assets, excluding transparent padding.
        let glyphs: [(SitePermissionType, CGRect)] = [
            (.location, CGRect(x: 0, y: 0, width: 16, height: 16)),
            (.camera, CGRect(x: 1, y: 3, width: 13.75, height: 10)),
            (.microphone, CGRect(x: 2, y: 0, width: 12, height: 16))
        ]
        let button = BrowserChromeButton(.toolbar)
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        button.setMenuAlertVisible(false, animated: false)
        button.layoutIfNeeded()
        let originalSubviews = button.subviews
        var referenceArea: CGFloat?

        for (permissionType, visibleBounds) in glyphs {
            button.animateSitePermissionGranted([permissionType], reduceMotion: true)
            defer { button.cancelSitePermissionAnimation() }
            let badge = try XCTUnwrap(button.subviews.first { !originalSubviews.contains($0) } as? UIImageView)
            let menuImageView = try XCTUnwrap(button.imageView)
            let scale = badge.bounds.width / 16
            let visibleArea = visibleBounds.width * visibleBounds.height * scale * scale
            if let referenceArea {
                XCTAssertEqual(visibleArea / referenceArea, 1, accuracy: 0.1)
            } else {
                referenceArea = visibleArea
            }

            let center = button.convert(badge.center, to: menuImageView)
            let leftEdgeAtSpringPeak = center.x + (visibleBounds.minX - 8) * scale * 1.31
            XCTAssertGreaterThan(leftEdgeAtSpringPeak, 11, "The badge must clear the shortened menu bars even at the spring peak")
            XCTAssertEqual(badge.bounds.width, badge.bounds.height, "Preserve each square asset's aspect ratio")
        }
    }

    func testWhenCancelledThenDownloadIndicatorAndMenuAccessibilityAreRestored() throws {
        let button = UIButton(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        button.accessibilityLabel = "Menu"
        button.setMenuAlertVisible(true, animated: false)
        let originalImage = try XCTUnwrap(button.image(for: .normal))
        let originalSubviews = button.subviews
        let downloadIndicator = try XCTUnwrap(originalSubviews.first { $0 is UIImageView && $0 !== button.imageView })
        button.animateSitePermissionGranted([.location], reduceMotion: false)

        XCTAssertTrue(downloadIndicator.isHidden)
        XCTAssertNotNil(button.imageView?.layer.mask)
        let badge = try XCTUnwrap(button.subviews.first { !originalSubviews.contains($0) })
        XCTAssertFalse(badge.isUserInteractionEnabled)
        XCTAssertTrue(badge.accessibilityElementsHidden)

        button.cancelSitePermissionAnimation()

        XCTAssertFalse(downloadIndicator.isHidden)
        XCTAssertNil(badge.superview)
        XCTAssertNil(button.imageView?.layer.mask)
        XCTAssertEqual(button.image(for: .normal), originalImage)
        XCTAssertEqual(button.accessibilityLabel, "Menu")
    }

    func testWhenReduceMotionIsEnabledThenBadgeDoesNotScaleAndBarsDoNotAnimate() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let button = UIButton(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        window.addSubview(button)
        window.isHidden = false
        defer {
            button.cancelSitePermissionAnimation()
            window.isHidden = true
        }
        button.setMenuAlertVisible(false, animated: false)
        let originalSubviews = button.subviews
        button.animateSitePermissionGranted([.microphone], reduceMotion: true)
        CATransaction.flush()

        let badge = try XCTUnwrap(button.subviews.first { !originalSubviews.contains($0) })
        XCTAssertEqual(badge.transform, .identity)
        XCTAssertFalse(badge.layer.animationKeys()?.contains { $0.hasPrefix("transform") } ?? false)
        let mask = try XCTUnwrap(button.imageView?.layer.mask)
        XCTAssertTrue(mask.animationKeys()?.isEmpty ?? true)
    }

    func testWhenAnimationEndsThenCombinedSequenceFinishesAndCancelledSequenceDoesNotRestart() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 160, height: 100))
        let buttons: [UIButton] = [BrowserChromeButton(.toolbar), UIButton(), UIButton()]
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: CGFloat(index) * 50, y: 0, width: 44, height: 44)
            window.addSubview(button)
            button.setMenuAlertVisible(index == 1, animated: false)
            button.layoutIfNeeded()
        }
        window.isHidden = false
        defer {
            buttons.forEach { $0.cancelSitePermissionAnimation() }
            window.isHidden = true
        }
        let originalImages = buttons.map { $0.configuration?.image ?? $0.image(for: .normal) }
        let originalSubviews = buttons.map(\.subviews)
        let secondBadgeImage = DesignSystemImages.Glyphs.Size16.permissionMicrophoneSolid
        buttons[0].animateSitePermissionGranted([.camera, .microphone], reduceMotion: false)
        buttons[1].animateSitePermissionGranted([.camera], reduceMotion: false)
        buttons[2].animateSitePermissionGranted([.camera, .microphone], reduceMotion: false)
        buttons[2].cancelSitePermissionAnimation()

        let secondBadgeAppeared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            buttons[0].subviews.contains { ($0 as? UIImageView)?.image == secondBadgeImage }
        }, object: nil)
        await fulfillment(of: [secondBadgeAppeared], timeout: 5)

        let secondBadge = try XCTUnwrap(buttons[0].subviews.first {
            $0 is UIImageView && !originalSubviews[0].contains($0)
        } as? UIImageView)
        XCTAssertEqual(secondBadge.image, secondBadgeImage)
        for (index, button) in buttons.enumerated().dropFirst() {
            XCTAssertNil(button.imageView?.layer.mask)
            XCTAssertEqual(button.configuration?.image ?? button.image(for: .normal), originalImages[index])
            XCTAssertEqual(button.subviews, originalSubviews[index])
        }
        let downloadIndicator = try XCTUnwrap(buttons[1].subviews.first { $0 is UIImageView && $0 !== buttons[1].imageView })
        XCTAssertFalse(downloadIndicator.isHidden)

        let menuRestored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            buttons[0].subviews == originalSubviews[0]
        }, object: nil)
        await fulfillment(of: [menuRestored], timeout: 5)

        XCTAssertNil(buttons[0].imageView?.layer.mask)
        XCTAssertEqual(buttons[0].configuration?.image, originalImages[0])
        XCTAssertEqual(buttons[0].subviews, originalSubviews[0])
    }
}

private final class SafeAreaStubView: UIView {

    var stubbedSafeAreaInsets: UIEdgeInsets = .zero {
        didSet { setNeedsLayout() }
    }

    override var safeAreaInsets: UIEdgeInsets {
        stubbedSafeAreaInsets
    }

}
