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

import XCTest
@testable import DuckDuckGo

final class FocusedLogoModelTests: XCTestCase {

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
