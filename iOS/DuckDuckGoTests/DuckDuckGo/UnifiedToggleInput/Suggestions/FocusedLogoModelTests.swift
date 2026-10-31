//
//  FocusedLogoModelTests.swift
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

import Combine
import SwiftUI
import XCTest
@testable import DuckDuckGo

final class FocusedLogoModelTests: XCTestCase {

    func testEscapeHatchLogoVisibilityTracksOverlapAndAvailableSpace() {
        struct Scenario {
            let name: String
            let centerY: CGFloat
            let viewport: CGRect
            let hatch: CGRect?
            let visible: Bool
        }

        let viewport = CGRect(x: 0, y: 100, width: 390, height: 500)
        let hatch = CGRect(x: 16, y: 110, width: 358, height: 64)
        let cases: [Scenario] = [
            .init(name: "Fits below hatch", centerY: 300, viewport: viewport, hatch: hatch, visible: true),
            .init(name: "Touches hatch without overlap", centerY: 255, viewport: viewport, hatch: hatch, visible: true),
            .init(name: "Overlaps hatch while animating", centerY: 240, viewport: viewport, hatch: hatch, visible: false),
            .init(name: "Clipped at top", centerY: 180, viewport: viewport, hatch: .zero, visible: false),
            .init(name: "Clipped by taller input", centerY: 300, viewport: CGRect(x: 0, y: 100, width: 390, height: 280), hatch: hatch, visible: false),
            .init(name: "Fits exactly above input", centerY: 300, viewport: CGRect(x: 0, y: 100, width: 390, height: 281), hatch: hatch, visible: true),
            .init(name: "Hatch scrolled away", centerY: 200, viewport: viewport, hatch: CGRect(x: 16, y: -100, width: 358, height: 64), visible: true),
            .init(name: "Unmeasured hatch", centerY: 300, viewport: viewport, hatch: nil, visible: false),
            .init(name: "Clipped horizontally", centerY: 300, viewport: CGRect(x: 0, y: 100, width: 209, height: 500), hatch: hatch, visible: false)
        ]

        for item in cases {
            var layout = EscapeHatchLogoLayout(centerY: 300, viewport: item.viewport, hatchFrame: item.hatch, destinationHatchFrame: item.hatch)
            layout.animatableData.first = item.centerY
            XCTAssertEqual(layout.isVisible, item.visible, item.name)
        }
    }

    func testEscapeHatchLogoStaysVisibleWhileInputAndLogoAnimateTogether() {
        let hatch = CGRect(x: 16, y: 72, width: 370, height: 56)
        let start = EscapeHatchLogoLayout(centerY: 379, viewport: CGRect(x: 0, y: 0, width: 402, height: 516), hatchFrame: hatch, destinationHatchFrame: hatch)
        let end = EscapeHatchLogoLayout(centerY: 278, viewport: CGRect(x: 0, y: 0, width: 402, height: 415), hatchFrame: hatch, destinationHatchFrame: hatch)

        for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
            var delta = end.animatableData - start.animatableData
            delta.scale(by: progress)
            var layout = end
            layout.animatableData = start.animatableData + delta
            XCTAssertTrue(layout.isVisible, "The logo must remain visible at animation progress \(progress)")
        }
    }

    func testEscapeHatchLogoStaysHiddenWhenTheDestinationCannotFitIt() {
        let hatch = CGRect(x: 16, y: 72, width: 370, height: 56)
        let start = EscapeHatchLogoLayout(centerY: 379, viewport: CGRect(x: 0, y: 0, width: 402, height: 516), hatchFrame: hatch, destinationHatchFrame: hatch)
        let end = EscapeHatchLogoLayout(centerY: 103, viewport: CGRect(x: 0, y: 0, width: 402, height: 240), hatchFrame: hatch, destinationHatchFrame: hatch)

        for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
            var delta = end.animatableData - start.animatableData
            delta.scale(by: progress)
            var layout = end
            layout.animatableData = start.animatableData + delta
            XCTAssertFalse(layout.isVisible, "The logo must never flash at animation progress \(progress)")
        }
    }

    func testRecordedHatchInsetTransitionNeverRevealsAnOverlappingDestination() {
        let viewport = CGRect(x: 0, y: 240, width: 440, height: 396)
        for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let appliedInset = 131 + 109 * progress
            let geometry = EmbeddedEscapeHatchGeometry(frame: CGRect(x: 16, y: 203 + 109 * progress, width: 408, height: 56),
                                                       appliedContentTopInset: appliedInset)
            let destination = geometry.destinationFrame(contentTopInset: 240)
            XCTAssertEqual(destination, CGRect(x: 16, y: 312, width: 408, height: 56))
            let layout = EscapeHatchLogoLayout(centerY: 423, viewport: viewport, hatchFrame: geometry.frame, destinationHatchFrame: destination)
            XCTAssertFalse(layout.isVisible, "The pending hatch overlap must hide the logo before the hatch reaches it")
        }
    }

    func testProjectedHatchKeepsLogoVisibleWhenBothLayoutsFit() {
        let viewport = CGRect(x: 0, y: 184, width: 440, height: 452)
        for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let geometry = EmbeddedEscapeHatchGeometry(frame: CGRect(x: 16, y: 203 + 53 * progress, width: 408, height: 56),
                                                       appliedContentTopInset: 131 + 53 * progress)
            let destination = geometry.destinationFrame(contentTopInset: 184)
            XCTAssertEqual(destination, CGRect(x: 16, y: 256, width: 408, height: 56))
            let layout = EscapeHatchLogoLayout(centerY: 423, viewport: viewport, hatchFrame: geometry.frame, destinationHatchFrame: destination)
            XCTAssertTrue(layout.isVisible, "A fitting destination must not interrupt the logo during the inset animation")
        }
    }

    @MainActor
    func testPendingInsetUpdatesDestinationBeforeAnotherHatchMeasurement() {
        let viewModel = UnifiedSuggestionsViewModel(inputsPublisher: Empty<UnifiedSuggestionsInputs, Never>().eraseToAnyPublisher(),
                                                    listViewModel: SuggestionsListViewModel(source: EmptySuggestionsSource()))
        viewModel.setEscapeHatchPlacement(.embedded)
        viewModel.contentTopInset = 131
        viewModel.setEmbeddedEscapeHatchGeometry(EmbeddedEscapeHatchGeometry(frame: CGRect(x: 16, y: 203, width: 408, height: 56),
                                                                           appliedContentTopInset: 131))
        let insetChanges: [(CGFloat, CGFloat)] = [(131, 203), (138, 210), (184, 256), (240, 312), (184, 256)]
        for (targetInset, destinationY) in insetChanges {
            viewModel.contentTopInset = targetInset
            XCTAssertEqual(viewModel.embeddedEscapeHatchDestinationFrame?.minY, destinationY)
            XCTAssertEqual(viewModel.embeddedEscapeHatchFrame?.minY, 203)
        }
    }

    func testHatchProjectionShiftsByTheRemainingInsetDuringAnInsetAnimation() {
        let geometry = EmbeddedEscapeHatchGeometry(frame: CGRect(x: 16, y: 222, width: 408, height: 56),
                                                   appliedContentTopInset: 180)
        XCTAssertEqual(geometry.destinationFrame(contentTopInset: 240), CGRect(x: 16, y: 282, width: 408, height: 56))
        XCTAssertEqual(geometry.destinationFrame(contentTopInset: 131), CGRect(x: 16, y: 173, width: 408, height: 56))
    }

    func testLogoMovesBelowTheHatchOnlyWhenTheKeyboardLeavesRoom() {
        let chromeBottom: CGFloat = 240
        let hatch = CGRect(x: 16, y: 312, width: 408, height: 56)
        func layout(barTop: CGFloat) -> (centerY: CGFloat, layout: EscapeHatchLogoLayout) {
            let top = UnifiedSuggestionsView.logoTopClearance(chromeBottom: chromeBottom, embeddedHatchFrame: hatch)
            let centerY = UnifiedSuggestionsView.logoCenterY(restingAt: 423, topChromeBottom: top, barTop: barTop)
            let viewport = CGRect(x: 0, y: chromeBottom, width: 440, height: barTop - chromeBottom)
            return (centerY, EscapeHatchLogoLayout(centerY: centerY, viewport: viewport, hatchFrame: hatch, destinationHatchFrame: hatch,
                                                   fitsMargins: UnifiedSuggestionsView.logoFits(topChromeBottom: top, barTop: barTop)))
        }

        let keyboardHidden = layout(barTop: 922)
        XCTAssertEqual(keyboardHidden.centerY, 449, "The logo touches the hatch's bottom instead of hiding behind it")
        XCTAssertTrue(keyboardHidden.layout.isVisible)

        XCTAssertFalse(layout(barTop: 560).layout.isVisible, "A logo squeezed between the hatch and the keyboard must hide")
    }

    func testHatchAboveTheChromeDoesNotMoveTheLogo() {
        XCTAssertEqual(UnifiedSuggestionsView.logoTopClearance(chromeBottom: 131, embeddedHatchFrame: CGRect(x: 16, y: -100, width: 408, height: 56)), 131)
        XCTAssertEqual(UnifiedSuggestionsView.logoTopClearance(chromeBottom: 131, embeddedHatchFrame: nil), 131)
    }

    func testFittingDestinationDoesNotRevealALogoOverlappingTheAnimatedHatch() {
        let layout = EscapeHatchLogoLayout(centerY: 423, viewport: CGRect(x: 0, y: 131, width: 440, height: 505),
                                          hatchFrame: CGRect(x: 16, y: 312, width: 408, height: 56),
                                          destinationHatchFrame: CGRect(x: 16, y: 203, width: 408, height: 56))
        XCTAssertFalse(layout.isVisible)
    }

    // MARK: - update: morph gating

    func test_firstResolveSinceActivation_snaps_evenLogoToLogo() {
        var model = FocusedLogoModel()
        model.update(wasLogo: true, isLogo: true, isDuckAI: true, isFirstSinceActivation: true)
        XCTAssertFalse(model.morphs, "The first resolve after a focus must snap, not replay a morph")
        XCTAssertEqual(model.progress, 1)
    }

    func test_inSessionLogoToLogo_morphs() {
        var model = FocusedLogoModel()
        model.update(wasLogo: true, isLogo: true, isDuckAI: true, isFirstSinceActivation: false)
        XCTAssertTrue(model.morphs)
        XCTAssertEqual(model.progress, 1)
    }

    func test_logoToNonLogo_doesNotMorph_andKeepsMark() {
        var model = FocusedLogoModel()
        // Settle on the Duck.ai mark first.
        model.update(wasLogo: true, isLogo: true, isDuckAI: true, isFirstSinceActivation: false)
        // Now resolve to a non-logo (e.g. a list): keep the mark so it fades out as-is.
        model.update(wasLogo: true, isLogo: false, isDuckAI: true, isFirstSinceActivation: false)
        XCTAssertFalse(model.morphs)
        XCTAssertEqual(model.progress, 1, "A non-logo resolve must not retarget the mark")
    }

    func test_nonLogoToLogo_doesNotMorph() {
        var model = FocusedLogoModel()
        model.update(wasLogo: false, isLogo: true, isDuckAI: false, isFirstSinceActivation: false)
        XCTAssertFalse(model.morphs, "Appearing from a non-logo state crossfades, it doesn't morph")
        XCTAssertEqual(model.progress, 0)
    }

    // MARK: - update: mark by mode

    func test_resolveToLogo_setsMarkByMode() {
        var model = FocusedLogoModel()
        model.update(wasLogo: true, isLogo: true, isDuckAI: false, isFirstSinceActivation: false)
        XCTAssertEqual(model.progress, 0, "Search resolves to the Dax mark")
        model.update(wasLogo: true, isLogo: true, isDuckAI: true, isFirstSinceActivation: false)
        XCTAssertEqual(model.progress, 1, "Duck.ai resolves to the Duck.ai mark")
    }

    // MARK: - morphToDax (dismiss)

    func test_morphToDax_pinsToDaxMark_andMorphs() {
        var model = FocusedLogoModel()
        model.update(wasLogo: true, isLogo: true, isDuckAI: true, isFirstSinceActivation: false)
        model.morphToDax(matching: 0.25)
        XCTAssertEqual(model.progress, 0)
        XCTAssertTrue(model.morphs)
    }

    func test_morphToDax_speedsUpToFitShortCollapse() {
        var model = FocusedLogoModel()
        model.morphToDax(matching: 0.25)
        // transitionDuration (~0.53s) / 0.25s ≈ 2.13.
        XCTAssertEqual(model.morphSpeed, FocusedLogoModel.transitionDuration / 0.25, accuracy: 0.0001)
        XCTAssertGreaterThan(model.morphSpeed, 1)
    }

    func test_morphToDax_clampsSpeedToOne_whenCollapseIsLongerThanMorph() {
        var model = FocusedLogoModel()
        model.morphToDax(matching: 2.0)
        XCTAssertEqual(model.morphSpeed, 1, "Never slow the morph below its natural speed")
    }

    // MARK: - speed reset

    func test_update_resetsMorphSpeed_afterADismissMorph() {
        var model = FocusedLogoModel()
        model.morphToDax(matching: 0.25)
        XCTAssertGreaterThan(model.morphSpeed, 1)
        // The next focus's first resolve runs `update`, which must restore the natural speed.
        model.update(wasLogo: false, isLogo: true, isDuckAI: false, isFirstSinceActivation: true)
        XCTAssertEqual(model.morphSpeed, 1)
    }
}
