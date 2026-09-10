//
//  SubscriptionOnboardingViewCoordinatorTests.swift
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
import SwiftUI

@MainActor
final class SubscriptionOnboardingViewCoordinatorTests: XCTestCase {

    /// `UIViewController.present` is a no-op — `presentedViewController` never gets set — unless the
    /// presenter is actually installed in a real window, so tests asserting on presentation need one.
    private var windows: [UIWindow] = []

    override func tearDown() {
        for window in windows {
            window.rootViewController = nil
            window.isHidden = true
        }
        windows = []
        super.tearDown()
    }

    private func makePresenter() -> UIViewController {
        let viewController = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        windows.append(window)
        return viewController
    }

    // MARK: - Presenting

    func testWhenPresentingThenThePresenterShowsAFullScreenCover() {
        let sut = SubscriptionOnboardingViewCoordinator()
        let presenter = makePresenter()

        sut.present(Text("content"), from: { presenter })

        XCTAssertEqual(presenter.presentedViewController?.modalPresentationStyle, .overFullScreen)
    }

    func testWhenAlreadyPresentingTheSameContentTypeThenPresentingAgainRefreshesInPlace() {
        let sut = SubscriptionOnboardingViewCoordinator()
        let presenter = makePresenter()

        sut.present(Text("first"), from: { presenter })
        let firstPresented = presenter.presentedViewController
        XCTAssertNotNil(firstPresented)
        sut.present(Text("second"), from: { presenter })

        XCTAssertTrue(presenter.presentedViewController === firstPresented,
                      "A second present(...) call should refresh the existing cover, not create a new one")
    }

    /// The parent-chain walk building `from` is only worth skipping if `present` actually skips calling it
    /// on the refresh path. Doesn't need a real window — it only counts closure invocations.
    func testWhenAlreadyPresentingThenThePresenterClosureIsNotInvokedAgain() {
        let sut = SubscriptionOnboardingViewCoordinator()
        let presenter = UIViewController()
        var presenterCallCount = 0

        sut.present(Text("first"), from: { presenterCallCount += 1; return presenter })
        sut.present(Text("second"), from: { presenterCallCount += 1; return presenter })

        XCTAssertEqual(presenterCallCount, 1, "presenter() must only run when actually presenting for the first time")
    }

    // MARK: - Finishing

    func testWhenNothingIsPresentedThenFinishDoesNotRunBeforeDismiss() {
        let sut = SubscriptionOnboardingViewCoordinator()
        var beforeDismissRan = false

        sut.finish { beforeDismissRan = true }

        XCTAssertFalse(beforeDismissRan)
    }

    /// The whole reason `beforeDismiss` exists: navigation hidden behind the cover must happen while it's
    /// still fully covering the screen, not after.
    func testWhenFinishingThenBeforeDismissRunsWhileTheCoverIsStillPresented() {
        let sut = SubscriptionOnboardingViewCoordinator()
        let presenter = makePresenter()
        sut.present(Text("content"), from: { presenter })
        var beforeDismissRan = false

        sut.finish {
            beforeDismissRan = true
            XCTAssertNotNil(presenter.presentedViewController, "the cover must still be up while beforeDismiss runs")
        }

        XCTAssertTrue(beforeDismissRan)
    }

    /// Doesn't need a real window — the coordinator's own bookkeeping (what `finish`'s guard checks) is set
    /// before the real UIKit presentation is even attempted.
    func testWhenFinishedTwiceThenTheSecondCallIsANoOp() {
        let sut = SubscriptionOnboardingViewCoordinator()
        let presenter = UIViewController()
        sut.present(Text("content"), from: { presenter })
        sut.finish()

        var secondBeforeDismissRan = false
        sut.finish { secondBeforeDismissRan = true }

        XCTAssertFalse(secondBeforeDismissRan, "once finished, a second finish() call must be a no-op")
    }

    // MARK: - Force dismiss

    func testWhenNothingIsPresentedThenForceDismissDoesNothing() {
        let sut = SubscriptionOnboardingViewCoordinator()

        sut.forceDismiss()
        // No crash, and a later present(...) still works normally — see next test.
        let presenter = makePresenter()
        sut.present(Text("content"), from: { presenter })

        XCTAssertNotNil(presenter.presentedViewController)
    }

    /// This is the stranded-cover safety net: if the presenting screen is torn down while the cover is
    /// still up, `forceDismiss` must leave the coordinator able to present again from a new screen.
    func testWhenForceDismissedThenTheCoordinatorCanPresentAgain() {
        let sut = SubscriptionOnboardingViewCoordinator()
        let firstPresenter = makePresenter()
        sut.present(Text("content"), from: { firstPresenter })

        sut.forceDismiss()

        let secondPresenter = makePresenter()
        sut.present(Text("content"), from: { secondPresenter })

        XCTAssertNotNil(secondPresenter.presentedViewController)
    }
}
