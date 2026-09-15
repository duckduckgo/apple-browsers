//
//  FireAnimationHandoffTests.swift
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
import Common
import FoundationExtensions
import Foundation
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// The animation takes part in the burn's dispatch group, so these cover the report never arriving —
/// what left users with a burn that never ended. The hooks are driven directly because the Lottie view
/// only loads in the `.normal` run type, so no test can drive the real animation.
final class FireAnimationHandoffTests: XCTestCase {

    private var pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        pinnedTabsManagerProvider = PinnedTabsManagerProvidingMock()
    }

    @MainActor
    override func tearDown() {
        autoreleasepool {
            WindowsManager.closeWindows()
            for controller in Application.appDelegate.windowControllersManager.mainWindowControllers {
                Application.appDelegate.windowControllersManager.unregister(controller)
            }
            cancellables = []
            pinnedTabsManagerProvider = nil
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
    }

    // MARK: - Animation handoff

    @MainActor
    func testWhenFireAnimationNeverFinishes_thenBurnStillCompletes() {
        let fire = makeFire(fireAnimationTimeout: 0.3)
        reportAnimationStarted(on: fire, thenFinish: false)

        let burned = expectation(description: "Burning")
        fire.burnAll { burned.fulfill() }

        wait(for: [burned], timeout: 5)
        XCTAssertNil(fire.burningData, "A burn nobody reported the animation for still has to release")
    }

    /// Guards the test above against passing for the wrong reason: with the timeout out of the way,
    /// the lost callback does hang the burn.
    @MainActor
    func testWhenFireAnimationNeverFinishesAndTheTimeoutIsFarOff_thenTheBurnHangs() {
        let fire = makeFire(fireAnimationTimeout: 30, burnTimeout: 30)
        reportAnimationStarted(on: fire, thenFinish: false)

        let burned = expectation(description: "Burning")
        burned.isInverted = true
        fire.burnAll { burned.fulfill() }

        wait(for: [burned], timeout: 1)
        XCTAssertNotNil(fire.burningData, "Only the timeout can release this burn")
    }

    @MainActor
    func testWhenFireAnimationFinishes_thenBurnCompletesExactlyOnce() {
        let fire = makeFire(fireAnimationTimeout: 30)
        reportAnimationStarted(on: fire, thenFinish: true)

        let burned = expectation(description: "Burning")
        burned.assertForOverFulfill = true
        fire.burnAll { burned.fulfill() }

        wait(for: [burned], timeout: 5)
        XCTAssertNil(fire.burningData)
    }

    // MARK: - Whole-burn watchdog

    /// The animation holds the group open, standing in for any clearing callback that never arrives.
    @MainActor
    func testWhenNothingReleasesTheGroup_thenTheBurnWatchdogReleasesTheBurn() {
        let fire = makeFire(fireAnimationTimeout: 60, burnTimeout: 0.3)
        reportAnimationStarted(on: fire, thenFinish: false)

        let burned = expectation(description: "Burning")
        fire.burnAll { burned.fulfill() }

        wait(for: [burned], timeout: 5)
        XCTAssertNil(fire.burningData)
    }

    @MainActor
    func testWhenABurnTimedOut_thenAFurtherBurnStillRuns() {
        let fire = makeFire(fireAnimationTimeout: 60, burnTimeout: 0.3)
        reportAnimationStarted(on: fire, thenFinish: false)

        let firstBurn = expectation(description: "First burn")
        fire.burnAll { firstBurn.fulfill() }
        wait(for: [firstBurn], timeout: 5)

        // A timed-out animation still holding the previous group would get this burn dropped by the
        // re-entry guard, leaving the Fire button dead for the rest of the session.
        let secondBurn = expectation(description: "Second burn")
        fire.burnAll { secondBurn.fulfill() }

        wait(for: [secondBurn], timeout: 5)
        XCTAssertNil(fire.burningData)
    }

    // MARK: - Animation state

    /// Releasing only the dispatch group isn't enough: `isFirePresentationInProgress` is
    /// `isAnimationPlaying || burningData != nil`, and `FireViewModel` is app-wide, so a stuck flag
    /// leaves the overlay up in every window and blocks every later animation.
    @MainActor
    func testWhenFireAnimationNeverFinishes_thenAnimationStateIsReleasedToo() {
        assertAnimationStateIsReleased(isFireWindow: false)
    }

    @MainActor
    func testWhenFireWindowAnimationNeverFinishes_thenAnimationStateIsReleasedToo() {
        assertAnimationStateIsReleased(isFireWindow: true)
    }

    @MainActor
    private func assertAnimationStateIsReleased(isFireWindow: Bool) {
        // The animation timeout on `Fire` is the backstop and only releases the group, so keep it out
        // of the way — this is about `FireViewModel` reporting the stop edge itself.
        let viewModel = FireViewModel(fire: makeFire(fireAnimationTimeout: 60), animationTimeout: 0.3)

        let released = expectation(description: "Animation state released")
        viewModel.$isAnimationPlaying
            .dropFirst()
            .filter { $0 == false }
            .sink { _ in released.fulfill() }
            .store(in: &cancellables)

        viewModel.setAnimationPlaying(true, isFireWindow: isFireWindow)
        XCTAssertTrue(viewModel.isAnimationPlaying)

        wait(for: [released], timeout: 5)
        XCTAssertFalse(viewModel.isAnimationPlaying, "A lost callback must not leave the overlay up")
    }

    // MARK: - Re-entry

    @MainActor
    func testWhenBurnStartedWhileOneIsInProgress_thenItsCompletionStillRuns() {
        var reportedAssertions = [String]()
        customAssertionFailure = { message, _, _ in reportedAssertions.append(message()) }
        defer { customAssertionFailure = nil }

        let fire = makeFire(fireAnimationTimeout: 30)
        reportAnimationStarted(on: fire, thenFinish: true)

        let firstBurn = expectation(description: "First burn")
        let droppedBurn = expectation(description: "Dropped burn")
        fire.burnAll { firstBurn.fulfill() }
        // Callers await this completion, so a dropped burn has to complete rather than hang them.
        fire.burnAll { droppedBurn.fulfill() }

        wait(for: [droppedBurn], timeout: 1)
        wait(for: [firstBurn], timeout: 5)
        XCTAssertEqual(reportedAssertions, ["burnAll called while burn already in progress"])
    }

    // MARK: - Helpers

    @MainActor
    private func makeFire(fireAnimationTimeout: TimeInterval, burnTimeout: TimeInterval = 30) -> Fire {
        let visualizeFire = MockVisualizeFireAnimationDecider()
        visualizeFire.shouldShowFireAnimation = true

        return Fire(cacheManager: WebCacheManagerMock(),
                    historyCoordinating: HistoryCoordinatingMock(),
                    permissionManager: PermissionManagerMock(),
                    windowControllersManager: Application.appDelegate.windowControllersManager,
                    faviconManagement: FaviconManagerMock(),
                    pinnedTabsManagerProvider: pinnedTabsManagerProvider,
                    tld: Application.appDelegate.tld,
                    visualizeFireAnimationDecider: visualizeFire,
                    // Keeps the burn from opening or keeping windows, so these stay about the handoff.
                    isAppActiveProvider: { false },
                    fireAnimationTimeout: fireAnimationTimeout,
                    burnTimeout: burnTimeout)
    }

    /// Stands in for `FireViewModel`, which reports start and finish as `burningData` comes and goes.
    @MainActor
    private func reportAnimationStarted(on fire: Fire, thenFinish: Bool) {
        fire.burningDataPublisher
            .sink { burningData in
                guard burningData != nil else { return }

                fire.fireAnimationDidStart()
                if thenFinish {
                    fire.fireAnimationDidFinish()
                }
            }
            .store(in: &cancellables)
    }

}
