//
//  DuckAIKeyboardEdgeSweepViewTests.swift
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

final class DuckAIKeyboardEdgeSweepViewTests: XCTestCase {

    func test_isActive_whenFlagOnAndEditingDuckAIInput() {
        XCTAssertTrue(isActive())
    }

    func test_isActive_falseWhenFlagOff() {
        XCTAssertFalse(isActive(isFeatureOn: false))
    }

    func test_isActive_falseWhenNotEditing() {
        XCTAssertFalse(isActive(isInputEditing: false))
    }

    func test_isActive_falseInSearchMode() {
        XCTAssertFalse(isActive(inputMode: .search))
    }

    func test_isActive_falseWhenUnifiedToggleInputUnavailable() {
        XCTAssertFalse(isActive(isUnifiedToggleInputAvailable: false))
    }

    func test_isActive_falseWhenUserSettingDisabled() {
        XCTAssertFalse(isActive(isUserSettingEnabled: false))
    }

    @MainActor
    func test_activationInstallsSweepImmediatelyWithEaseOutAndTwoAndHalfSecondDuration() throws {
        let view = try makeStartedView()
        let rotations = allLayers(in: view.layer).compactMap { $0.animation(forKey: "sweep") as? CABasicAnimation }
        XCTAssertEqual(rotations.count, 2)
        for rotation in rotations {
            XCTAssertEqual(rotation.keyPath, "transform.rotation.z")
            XCTAssertEqual(rotation.duration, 2.5)
            let timing = try XCTUnwrap(rotation.timingFunction)
            var firstControlPoint: [Float] = [0, 0]
            var secondControlPoint: [Float] = [0, 0]
            timing.getControlPoint(at: 1, values: &firstControlPoint)
            timing.getControlPoint(at: 2, values: &secondControlPoint)
            XCTAssertEqual(firstControlPoint, [0, 0])
            XCTAssertEqual(secondControlPoint[0], 0.58, accuracy: 0.001)
            XCTAssertEqual(secondControlPoint[1], 1)
        }
    }

    @MainActor
    func test_activationWaitsForUsableBoundsWithoutConsumingSweep() throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Sweep is disabled with Reduce Motion")
        let view = DuckAIKeyboardEdgeSweepView(frame: .zero)
        view.isActive = true
        XCTAssertTrue(animatedLayers(in: view).isEmpty)

        layout(view, width: 390, height: 300)

        XCTAssertFalse(animatedLayers(in: view).isEmpty)
        XCTAssertFalse(view.isHidden)
    }

    @MainActor
    func test_keyboardHeightChangesPreserveRingGeometry() throws {
        let view = try makeStartedView()
        let gradients = allLayers(in: view.layer).compactMap { $0 as? CAGradientLayer }.filter { $0.type == .conic }
        let masks = allLayers(in: view.layer).compactMap { $0 as? CAShapeLayer }
        XCTAssertEqual(gradients.count, 2)
        XCTAssertEqual(masks.count, 2)
        let gradientBounds = gradients.map(\.bounds)
        let gradientPositions = gradients.map(\.position)
        let gradientLocations = gradients.map(\.locations)
        let paths = masks.compactMap(\.path)

        layout(view, width: 390, height: 400)

        XCTAssertEqual(gradients.map(\.bounds), gradientBounds)
        XCTAssertEqual(gradients.map(\.position), gradientPositions)
        XCTAssertEqual(gradients.map(\.locations), gradientLocations)
        for (mask, path) in zip(masks, paths) {
            XCTAssertEqual(mask.path?.boundingBoxOfPath, path.boundingBoxOfPath)
        }
        XCTAssertFalse(animatedLayers(in: view).isEmpty)
    }

    @MainActor
    func test_repeatedActivationAndBriefHideDoNotReplayCompletedSweep() throws {
        let view = try makeStartedView()
        allLayers(in: view.layer).forEach { $0.removeAllAnimations() }

        view.isActive = true
        view.setNeedsLayout()
        view.layoutIfNeeded()
        view.isActive = false
        view.isActive = true
        layout(view, width: 390, height: 70)
        layout(view, width: 390, height: 300)

        XCTAssertTrue(animatedLayers(in: view).isEmpty)
    }

    @MainActor
    func test_widthChangeCancelsSweepWithoutRearmingIt() throws {
        let view = try makeStartedView()

        layout(view, width: 600, height: 300)

        XCTAssertTrue(animatedLayers(in: view).isEmpty)
        view.isActive = false
        view.isActive = true
        layout(view, width: 390, height: 300)
        XCTAssertTrue(animatedLayers(in: view).isEmpty)
    }

    // MARK: - Helper

    @MainActor
    private func makeStartedView() throws -> DuckAIKeyboardEdgeSweepView {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Sweep is disabled with Reduce Motion")
        let view = DuckAIKeyboardEdgeSweepView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        view.isActive = true
        XCTAssertFalse(animatedLayers(in: view).isEmpty)
        return view
    }

    @MainActor
    private func layout(_ view: UIView, width: CGFloat, height: CGFloat) {
        view.frame.size = CGSize(width: width, height: height)
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    @MainActor
    private func animatedLayers(in view: UIView) -> [CALayer] {
        allLayers(in: view.layer).filter { !($0.animationKeys() ?? []).isEmpty }
    }

    @MainActor
    private func allLayers(in layer: CALayer) -> [CALayer] {
        [layer] + (layer.sublayers ?? []).flatMap { allLayers(in: $0) } + (layer.mask.map { allLayers(in: $0) } ?? [])
    }

    private func isActive(
        isFeatureOn: Bool = true,
        isUserSettingEnabled: Bool = true,
        isInputEditing: Bool = true,
        inputMode: TextEntryMode = .aiChat,
        isUnifiedToggleInputAvailable: Bool = true
    ) -> Bool {
        DuckAIKeyboardEdgeSweepView.isActive(
            isFeatureOn: isFeatureOn,
            isUserSettingEnabled: isUserSettingEnabled,
            isInputEditing: isInputEditing,
            inputMode: inputMode,
            isUnifiedToggleInputAvailable: isUnifiedToggleInputAvailable
        )
    }
}
