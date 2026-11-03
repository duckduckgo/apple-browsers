//
//  FireAnimationInstrumentationTests.swift
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

@_spi(Testing) import PixelKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class FireAnimationInstrumentationTests: XCTestCase {
    private var pixels: PixelKitMock!
    private var sut: DefaultFireAnimationInstrumentation!
    private var currentTime: CFTimeInterval = 0

    override func setUp() {
        super.setUp()
        pixels = PixelKitMock()
        currentTime = 0
        sut = makeInstrumentation()
    }

    override func tearDown() {
        sut = nil
        pixels = nil
        super.tearDown()
    }

    func testBurnFinishesBeforeAnimation() {
        sut.burnDidStart()
        sut.burnDidFinish()
        sut.animationDidFinish(animation: .fireRising)

        pixels.expectedFireCalls = [animationCompleted(burnInProgress: false)]
        XCTAssertEqual(pixels.actualFireCalls, pixels.expectedFireCalls)
    }

    func testSlowBurnIsReportedWithoutWaitingForCompletion() {
        sut.burnDidStart()
        sut.animationDidFinish(animation: .fireRising)

        pixels.expectedFireCalls = [animationCompleted(burnInProgress: true), burnOutlastedAnimation()]
        XCTAssertEqual(pixels.actualFireCalls, pixels.expectedFireCalls)
    }

    func testRemainingTimeStartsAtAnimationEnd() {
        sut.burnDidStart()
        currentTime = 10
        sut.animationDidFinish(animation: .fireRising)
        currentTime = 12
        sut.burnDidFinish()

        pixels.expectedFireCalls = [
            animationCompleted(burnInProgress: true),
            burnOutlastedAnimation(),
            .init(pixel: FireAnimationPixels.burnCompletedAfterAnimation(elapsed: .lessThan5), frequency: .standard)
        ]
        XCTAssertEqual(pixels.actualFireCalls, pixels.expectedFireCalls)
    }

    func testDroppedBurnDoesNotReportAnimationMetrics() {
        sut.burnDidStart(accepted: false)
        sut.animationDidFinish(animation: .fireRising)
        sut.burnDidFinish()

        XCTAssertTrue(pixels.actualFireCalls.isEmpty)
    }

    func testAutomaticBurnDoesNotReportAnimationMetrics() {
        let request = FireRequest(options: .all, trigger: .autoClearOnForeground, scope: .all, source: .autoClear)
        let instrumentation = DefaultFireAnimationInstrumentation(request: request, pixelFiring: pixels)
        instrumentation.burnDidStart()
        instrumentation.animationDidFinish(animation: .fireRising)
        instrumentation.burnDidFinish()

        XCTAssertTrue(pixels.actualFireCalls.isEmpty)
    }

    func testBurnWithoutCompletedAnimationDoesNotReportAnimationMetrics() {
        sut.burnDidStart()
        sut.burnDidFinish()

        XCTAssertTrue(pixels.actualFireCalls.isEmpty)
    }

    func testDuplicateCallbacksDoNotReportTwice() {
        sut.burnDidStart()
        sut.animationDidFinish(animation: .fireRising)
        sut.animationDidFinish(animation: .fireRising)
        sut.burnDidFinish()
        sut.burnDidFinish()

        XCTAssertEqual(pixels.actualFireCalls.count, 3)
    }

    func testLaterBurnDoesNotChangeEarlierBurnMeasurement() {
        sut.burnDidStart()
        sut.burnDidFinish()
        let laterBurn = makeInstrumentation()
        laterBurn.burnDidStart()
        sut.animationDidFinish(animation: .fireRising)

        pixels.expectedFireCalls = [animationCompleted(burnInProgress: false)]
        XCTAssertEqual(pixels.actualFireCalls, pixels.expectedFireCalls)
    }

    func testScopeSourceAndAnimationAreOnlyReportedAtAnimationCompletion() {
        let request = FireRequest(options: .all, trigger: .manualFire, scope: .fireMode, source: .escapeHatch)
        let instrumentation = DefaultFireAnimationInstrumentation(request: request, pixelFiring: pixels, timeProvider: { 0 })
        instrumentation.burnDidStart()
        instrumentation.animationDidFinish(animation: .waterSwirl)
        instrumentation.burnDidFinish()

        XCTAssertEqual(pixels.actualFireCalls.map { $0.pixel.name }, [
            "fire_animation-completed", "fire_burn-outlasted-animation", "fire_post-animation-burn-completed"
        ])
        XCTAssertEqual(pixels.actualFireCalls.map { $0.pixel.parameters }, [
            ["scope": "fire_mode", "source": "escapeHatch", "animation": "waterSwirl", "burn_in_progress": "true"],
            nil,
            ["elapsed": "1"]
        ])
    }

    private func makeInstrumentation() -> DefaultFireAnimationInstrumentation {
        DefaultFireAnimationInstrumentation(
            request: FireRequest(options: .all, trigger: .manualFire, scope: .all, source: .browsing),
            pixelFiring: pixels, timeProvider: { [weak self] in self?.currentTime ?? 0 })
    }

    private func animationCompleted(burnInProgress: Bool) -> ExpectedFireCall {
        .init(pixel: FireAnimationPixels.animationCompleted(
            scope: "all", source: "browsing", animation: "fireRising", burnInProgress: burnInProgress), frequency: .dailyAndCount)
    }

    private func burnOutlastedAnimation() -> ExpectedFireCall {
        .init(pixel: FireAnimationPixels.burnOutlastedAnimation, frequency: .dailyAndCount)
    }
}
