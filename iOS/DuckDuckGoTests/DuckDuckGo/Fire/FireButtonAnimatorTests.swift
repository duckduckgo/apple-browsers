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

    func testCompletedAnimationUncoversWindowAndReportsBurnStillRunning() async throws {
        let window = try XCTUnwrap(UIApplication.shared.firstKeyWindow)
        let pixels = PixelKitMock()
        let instrumentation = DefaultFireAnimationInstrumentation(
            request: FireRequest(options: .all, trigger: .manualFire, scope: .all, source: .browsing),
            pixelFiring: pixels)
        let settings = AppSettingsMock()
        settings.currentFireButtonAnimation = .fireRising
        let animator = FireButtonAnimator(appSettings: settings)
        let existingSubviews = window.subviews
        var overlayViews: [UIView] = []
        let overlayRemoved = expectation(description: "Overlay removed")
        let animationFinished = expectation(description: "Animation finished")

        animator.animate(instrumentation: instrumentation) {
            instrumentation.burnDidStart()
        } onTransitionCompleted: {
        } completion: {
            animationFinished.fulfill()
        } onOverlayRemoved: {
            XCTAssertFalse(overlayViews.isEmpty)
            XCTAssertTrue(overlayViews.allSatisfy { $0.window == nil })
            overlayRemoved.fulfill()
        }

        overlayViews = window.subviews.filter { subview in
            !existingSubviews.contains(where: { $0 === subview })
        }
        await fulfillment(of: [overlayRemoved, animationFinished], timeout: 5, enforceOrder: true)

        pixels.expectedFireCalls = [
            .init(pixel: FireAnimationPixels.animationCompleted(
                scope: "all", source: "browsing", animation: "fireRising", burnInProgress: true), frequency: .dailyAndCount),
            .init(pixel: FireAnimationPixels.burnOutlastedAnimation, frequency: .dailyAndCount)
        ]
        XCTAssertEqual(pixels.actualFireCalls, pixels.expectedFireCalls)
    }

    func testDisabledAnimationUncoversBeforeBurnWithoutReportingMetrics() async throws {
        _ = try XCTUnwrap(UIApplication.shared.firstKeyWindow)
        let pixels = PixelKitMock()
        let instrumentation = DefaultFireAnimationInstrumentation(
            request: FireRequest(options: .all, trigger: .manualFire, scope: .all, source: .browsing),
            pixelFiring: pixels)
        let settings = AppSettingsMock()
        settings.currentFireButtonAnimation = .none
        let animator = FireButtonAnimator(appSettings: settings)
        var events: [String] = []
        let completed = expectation(description: "Completed without animation")

        animator.animate(instrumentation: instrumentation) {
            events.append("burn")
            instrumentation.burnDidStart()
            instrumentation.burnDidFinish()
        } onTransitionCompleted: {
        } completion: {
            completed.fulfill()
        } onOverlayRemoved: {
            events.append("overlayRemoved")
        }

        XCTAssertEqual(events, ["overlayRemoved"])
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(events, ["overlayRemoved", "burn"])
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

        let snapshot = try XCTUnwrap(addedSubviews.first)

        notificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)

        XCTAssertNil(snapshot.superview)
    }
}
