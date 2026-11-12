//
//  FireButtonAnimatorTests.swift
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
@_spi(Testing) import PixelKit
@testable import DuckDuckGo

@MainActor
final class FireButtonAnimatorTests: XCTestCase {

    func testCompletedAnimationReportsBurnStillRunning() async throws {
        _ = try XCTUnwrap(UIApplication.shared.firstKeyWindow)
        let pixels = PixelKitMock()
        let instrumentation = DefaultFireAnimationInstrumentation(
            request: FireRequest(options: .all, trigger: .manualFire, scope: .all, source: .browsing),
            pixelFiring: pixels)
        let animator = FireButtonAnimator(appSettings: AppSettingsMock())
        let animationFinished = expectation(description: "Animation finished")

        animator.animate(instrumentation: instrumentation) {
            instrumentation.burnDidStart()
        } onTransitionCompleted: {
        } completion: {
            animationFinished.fulfill()
        }

        await fulfillment(of: [animationFinished], timeout: 5)

        pixels.expectedFireCalls = [
            .init(pixel: FireAnimationPixels.animationCompleted(
                scope: "all", source: "browsing", animation: "fireRising", burnInProgress: true), frequency: .dailyAndCount),
            .init(pixel: FireAnimationPixels.burnOutlastedAnimation, frequency: .dailyAndCount)
        ]
        XCTAssertEqual(pixels.actualFireCalls, pixels.expectedFireCalls)
    }

    func testDisabledAnimationDoesNotReportAnimationMetrics() async {
        let pixels = PixelKitMock()
        let instrumentation = DefaultFireAnimationInstrumentation(
            request: FireRequest(options: .all, trigger: .manualFire, scope: .all, source: .browsing),
            pixelFiring: pixels)
        let settings = AppSettingsMock()
        settings.currentFireButtonAnimation = .none
        let animator = FireButtonAnimator(appSettings: settings)
        let completed = expectation(description: "Completed without animation")

        animator.animate(instrumentation: instrumentation) {
            instrumentation.burnDidStart()
            instrumentation.burnDidFinish()
        } onTransitionCompleted: {
        } completion: {
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 1)

        XCTAssertTrue(pixels.actualFireCalls.isEmpty)
    }

    func testWhenApplicationWillResignActiveThenRetainedPreBurnSnapshotIsRemoved() throws {
        let window = try XCTUnwrap(UIApplication.shared.firstKeyWindow)
        let notificationCenter = NotificationCenter()
        let animator = FireButtonAnimator(appSettings: AppSettingsMock(), notificationCenter: notificationCenter)
        let existingSubviews = window.subviews

        animator.animate {
        } onTransitionCompleted: {
        } completion: {
        }

        let addedSubviews = window.subviews.filter { subview in
            !existingSubviews.contains(where: { $0 === subview })
        }
        defer { addedSubviews.forEach { $0.removeFromSuperview() } }

        let snapshot = try XCTUnwrap(addedSubviews.first?.subviews.first)

        notificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)

        XCTAssertNil(snapshot.superview)
    }

    func testExplicitWindowsAnimateTogetherWithoutUsingTheKeyWindowOrRepeatingCallbacks() async throws {
        let keyWindow = try XCTUnwrap(UIApplication.shared.firstKeyWindow)
        let scene = try XCTUnwrap(keyWindow.windowScene)
        let first = FireAnimationWindow(windowScene: scene)
        let second = FireAnimationWindow(windowScene: scene)
        first.frame = CGRect(x: 20, y: 30, width: 500, height: 700)
        second.frame = CGRect(x: 80, y: 90, width: 320, height: 600)
        first.rootViewController = UIViewController()
        second.rootViewController = UIViewController()
        first.isHidden = false
        second.isHidden = false
        defer {
            first.isHidden = true
            second.isHidden = true
        }
        let originalSubviews = keyWindow.subviews
        let animator = FireButtonAnimator(appSettings: AppSettingsMock())
        var starts = 0
        var transitions = 0
        let finished = expectation(description: "All windows finished")
        finished.assertForOverFulfill = true

        animator.animate(in: [first, second, first]) {
            starts += 1
        } onTransitionCompleted: {
            transitions += 1
        } completion: {
            finished.fulfill()
        }

        for window in [first, second] {
            let overlays = window.subviews.filter { $0.accessibilityIdentifier == FireButtonAnimator.overlayIdentifier }
            XCTAssertEqual(overlays.count, 1)
            let overlay = try XCTUnwrap(overlays.first)
            XCTAssertEqual(overlay.frame, window.bounds)
            XCTAssertTrue(overlay.subviews.allSatisfy { $0.frame == overlay.bounds })
        }
        XCTAssertEqual(keyWindow.subviews, originalSubviews)
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(transitions, 1)
        XCTAssertFalse(first.subviews.contains { $0.accessibilityIdentifier == FireButtonAnimator.overlayIdentifier })
        XCTAssertFalse(second.subviews.contains { $0.accessibilityIdentifier == FireButtonAnimator.overlayIdentifier })
    }

    func testMissingOriginWindowStillRunsTheBurnAndCompletion() async {
        let animator = FireButtonAnimator(appSettings: AppSettingsMock())
        var events: [String] = []
        let finished = expectation(description: "Cleared without a window")
        animator.animate(in: []) {
            events.append("burn")
        } onTransitionCompleted: {
            events.append("transition")
        } completion: {
            events.append("completion")
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(events, ["burn", "transition", "completion"])
    }
}

private final class FireAnimationWindow: UIWindow {
    override func snapshotView(afterScreenUpdates afterUpdates: Bool) -> UIView? {
        UIView(frame: bounds)
    }
}
