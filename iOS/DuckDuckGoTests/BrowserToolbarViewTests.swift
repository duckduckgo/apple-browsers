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

import XCTest
@testable import DuckDuckGo

/// Covers `setButtonRowCollapseProgress`, the button-fade/shrink stage of the scroll-coupled chrome
/// collapse, and the corresponding fix to `restingCapsuleFrame` (which must report a stable single-row
/// height rather than the live, mid-animation panel height).
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
        XCTAssertEqual(sut.panelHeightForTesting, fullHeight, accuracy: 0.01)
        XCTAssertEqual(sut.buttonRowAlphaForTesting, 1, accuracy: 0.001)
        XCTAssertTrue(sut.buttonRowTransformForTesting.isIdentity)
    }

    func testWhenProgressIsOneThenButtonRowIsGoneAtSingleRowHeight() {
        let sut = makeSUT()
        let singleRowHeight = BrowserToolbarView.singleRowHeight(withOmnibarHeight: omnibarHeight)

        let height = sut.setButtonRowCollapseProgress(1, reduceMotion: false)

        XCTAssertEqual(height, singleRowHeight, accuracy: 0.01)
        XCTAssertEqual(sut.buttonRowAlphaForTesting, 0, accuracy: 0.001)
        XCTAssertFalse(sut.buttonRowTransformForTesting.isIdentity, "Should have scaled/translated away, not just faded")
    }

    func testWhenProgressIsHalfThenHeightIsBetweenFullAndSingleRow() {
        let sut = makeSUT()
        let fullHeight = BrowserToolbarView.totalHeight(withOmnibarHeight: omnibarHeight, isFloating: true)
        let singleRowHeight = BrowserToolbarView.singleRowHeight(withOmnibarHeight: omnibarHeight)

        let height = sut.setButtonRowCollapseProgress(0.5, reduceMotion: false)

        XCTAssertEqual(height, (fullHeight + singleRowHeight) / 2, accuracy: 0.01)
        XCTAssertEqual(sut.buttonRowAlphaForTesting, 0.5, accuracy: 0.001)
    }

    func testWhenReduceMotionThenProgressIsIgnoredAndButtonRowStaysFullyShown() {
        let sut = makeSUT()
        let fullHeight = BrowserToolbarView.totalHeight(withOmnibarHeight: omnibarHeight, isFloating: true)

        let height = sut.setButtonRowCollapseProgress(1, reduceMotion: true)

        XCTAssertEqual(height, fullHeight, accuracy: 0.01)
        XCTAssertEqual(sut.buttonRowAlphaForTesting, 1, accuracy: 0.001)
        XCTAssertTrue(sut.buttonRowTransformForTesting.isIdentity)
    }

    func testWhenNoEmbeddedOmnibarThenProgressIsANoOp() {
        let sut = makeSUT(embeddedOmnibar: false)
        let buttonsOnlyHeight = BrowserToolbarView.totalHeight(withOmnibarHeight: 0, isFloating: true)

        let height = sut.setButtonRowCollapseProgress(1, reduceMotion: false)

        XCTAssertEqual(height, buttonsOnlyHeight, accuracy: 0.01)
        XCTAssertEqual(sut.buttonRowAlphaForTesting, 1, accuracy: 0.001)
    }

    func testWhenNotFloatingThenProgressIsANoOp() {
        let sut = makeSUT(floating: false)
        let legacyFullHeight = BrowserToolbarView.totalHeight(withOmnibarHeight: omnibarHeight, isFloating: false)

        let height = sut.setButtonRowCollapseProgress(1, reduceMotion: false)

        XCTAssertEqual(height, legacyFullHeight, accuracy: 0.01)
        XCTAssertEqual(sut.buttonRowAlphaForTesting, 1, accuracy: 0.001)
    }

    // MARK: - restingCapsuleFrame stability

    /// The regression this guards: the pill's morph target used to read the live, animating
    /// `buttonsHeightConstraint.constant` directly, so as the button row shrank the pill's own target
    /// moved under it -- a feedback loop. It must report the stable single-row height throughout.
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
}
