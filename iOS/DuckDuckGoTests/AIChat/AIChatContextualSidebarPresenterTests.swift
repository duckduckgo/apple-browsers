//
//  AIChatContextualSidebarPresenterTests.swift
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

final class AIChatContextualSidebarPresenterTests: XCTestCase {

    /// Records the containment flag the sheet reads to tell being opened from coming back from under a modal.
    private final class RecordingChildViewController: UIViewController {
        var isMovingToParentOnWillAppear: Bool?

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            isMovingToParentOnWillAppear = isMovingToParent
        }
    }

    private let sidebarWidth: CGFloat = 380

    private var window: UIWindow!
    private var parentViewController: UIViewController!
    private var container: UIView!
    private var page: UIView!
    private var sut: AIChatContextualSidebarPresenter!

    @MainActor
    override func setUp() {
        super.setUp()
        parentViewController = UIViewController()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1180, height: 820))
        window.rootViewController = parentViewController
        window.makeKeyAndVisible()

        let parentView: UIView = parentViewController.view
        page = UIView()
        container = UIView()
        container.isHidden = true
        for view in [page!, container!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            parentView.addSubview(view)
        }
        let hidden = container.leadingAnchor.constraint(equalTo: parentView.trailingAnchor)
        let shown = container.trailingAnchor.constraint(equalTo: parentView.trailingAnchor)
        NSLayoutConstraint.activate([
            page.topAnchor.constraint(equalTo: parentView.topAnchor),
            page.bottomAnchor.constraint(equalTo: parentView.bottomAnchor),
            page.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: container.leadingAnchor),
            container.topAnchor.constraint(equalTo: parentView.topAnchor),
            container.bottomAnchor.constraint(equalTo: parentView.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: sidebarWidth),
            hidden,
        ])
        parentView.layoutIfNeeded()

        sut = AIChatContextualSidebarPresenter(parent: parentViewController,
                                               pageView: page,
                                               container: container,
                                               shownConstraint: shown,
                                               hiddenConstraint: hidden)
    }

    @MainActor
    override func tearDown() {
        window.isHidden = true
        window = nil
        sut = nil
        page = nil
        container = nil
        parentViewController = nil
        super.tearDown()
    }

    @MainActor
    func testWhenPresentedThenChildFillsTheColumnAndThePageMakesRoomForIt() {
        let child = RecordingChildViewController()

        sut.present(child, animated: false)

        XCTAssertTrue(child.parent === parentViewController)
        XCTAssertTrue(sut.hostedViewController === child)
        XCTAssertTrue(sut.isPresenting)
        XCTAssertFalse(container.isHidden)
        XCTAssertEqual(container.frame.maxX, parentViewController.view.bounds.maxX)
        XCTAssertEqual(page.frame.width, parentViewController.view.bounds.width - sidebarWidth)
        XCTAssertEqual(child.view.frame.size, container.bounds.size)
    }

    @MainActor
    func testWhenPresentedThenChildIsToldItIsMovingToItsParent() {
        let child = RecordingChildViewController()

        sut.present(child, animated: false)

        XCTAssertEqual(child.isMovingToParentOnWillAppear, true)
    }

    @MainActor
    func testWhenDismissedThenChildLeavesAndThePageGetsTheFullWidthBack() {
        let child = RecordingChildViewController()
        sut.present(child, animated: false)
        var didComplete = false

        sut.dismiss(child, animated: false) { didComplete = true }

        XCTAssertTrue(didComplete)
        XCTAssertNil(child.parent)
        XCTAssertNil(child.view.superview)
        XCTAssertNil(sut.hostedViewController)
        XCTAssertFalse(sut.isPresenting)
        XCTAssertTrue(container.isHidden)
        XCTAssertEqual(page.frame.width, parentViewController.view.bounds.width)
    }

    @MainActor
    func testWhenDismissedAnimatedThenChildStaysUntilTheSlideEnds() {
        let child = RecordingChildViewController()
        sut.present(child, animated: false)
        let removed = expectation(description: "Child removed")

        sut.dismiss(child, animated: true) { removed.fulfill() }

        XCTAssertTrue(child.parent === parentViewController)
        XCTAssertFalse(sut.isPresenting)
        wait(for: [removed], timeout: 2)
        XCTAssertNil(child.parent)
        XCTAssertTrue(container.isHidden)
    }

    @MainActor
    func testWhenDismissedWithoutAnimationWhileSlidingOutThenRemovalFinishesAtOnceAndEveryCompletionRuns() {
        let child = RecordingChildViewController()
        sut.present(child, animated: false)
        var completionCount = 0
        sut.dismiss(child, animated: true) { completionCount += 1 }

        sut.dismiss(child, animated: false) { completionCount += 1 }

        XCTAssertNil(child.parent)
        XCTAssertEqual(completionCount, 2)
    }

    @MainActor
    func testWhenDismissingAViewControllerThatIsNotInTheColumnThenCompletionRunsAndTheColumnStays() {
        let child = RecordingChildViewController()
        sut.present(child, animated: false)
        var didComplete = false

        sut.dismiss(UIViewController(), animated: false) { didComplete = true }

        XCTAssertTrue(didComplete)
        XCTAssertTrue(child.parent === parentViewController)
        XCTAssertTrue(sut.isPresenting)
    }

    @MainActor
    func testWhenAnotherViewControllerIsPresentedWhileShownThenItReplacesTheFirstInPlace() {
        let first = RecordingChildViewController()
        let second = RecordingChildViewController()
        sut.present(first, animated: false)

        sut.present(second, animated: true)

        XCTAssertNil(first.parent)
        XCTAssertTrue(second.parent === parentViewController)
        XCTAssertTrue(sut.hostedViewController === second)
        XCTAssertEqual(container.frame.maxX, parentViewController.view.bounds.maxX)
    }
}
