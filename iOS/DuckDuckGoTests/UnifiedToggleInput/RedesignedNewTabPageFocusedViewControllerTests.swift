//
//  RedesignedNewTabPageFocusedViewControllerTests.swift
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

@MainActor
final class RedesignedNewTabPageFocusedViewControllerTests: XCTestCase {

    func testWhenContainmentIsUpdatedBeforeInstallationThenContentIsNotLoadedOrAttached() {
        let parent = UIViewController()
        let content = ContentViewControllerSpy()

        update(content, in: parent, focused: true)
        update(content, in: parent, focused: false)

        XCTAssertFalse(content.isViewLoaded)
        XCTAssertEqual(content.loadCount, 0)
        XCTAssertNil(content.parent)
        XCTAssertTrue(parent.children.isEmpty)
    }

    func testWhenBrowserContentIsFocusedThenSameContentStaysAttachedAndLoadsOnlyOnce() throws {
        let parent = UIViewController()
        let content = ContentViewControllerSpy()
        install(content, in: parent)
        install(content, in: parent)
        update(content, in: parent, focused: true)
        let focused = try XCTUnwrap(parent.children.compactMap { $0 as? RedesignedNewTabPageFocusedViewController }.first)
        update(content, in: parent, focused: true)

        XCTAssertTrue(content.parent === parent)
        XCTAssertEqual(parent.children, [content, focused])
        XCTAssertTrue(focused.children.isEmpty)
        XCTAssertTrue(content.view.superview === focused.view)
        XCTAssertEqual(content.loadCount, 1)
        XCTAssertEqual(content.attachmentCount, 1)
    }

    func testWhenLeavingFocusedPresentationThenWrapperIsReleasedAndContentReturnsToBrowser() {
        let parent = UIViewController()
        let content = ContentViewControllerSpy()
        install(content, in: parent)
        weak var focused: UIViewController?

        autoreleasepool {
            update(content, in: parent, focused: true)
            focused = parent.children.first { $0 is RedesignedNewTabPageFocusedViewController }
            XCTAssertNotNil(focused)
            update(content, in: parent, focused: false)
            update(content, in: parent, focused: false)
        }

        XCTAssertNil(focused)
        XCTAssertEqual(parent.children, [content])
        XCTAssertTrue(content.view.superview === parent.view)
        XCTAssertEqual(parent.view.subviews, [content.view])
        XCTAssertEqual(content.attachmentCount, 1)
    }

    func testWhenImmediatelyRefocusingThenContentIsReusedWithoutAccumulatingChildrenOrConstraints() throws {
        let parent = UIViewController()
        let content = ContentViewControllerSpy()
        install(content, in: parent)
        for _ in 0..<3 {
            update(content, in: parent, focused: true)
            update(content, in: parent, focused: false)
        }
        update(content, in: parent, focused: true)
        let focused = try XCTUnwrap(parent.children.compactMap { $0 as? RedesignedNewTabPageFocusedViewController }.first)

        XCTAssertEqual(parent.children.count, 2)
        XCTAssertTrue(content.parent === parent)
        XCTAssertEqual(parent.view.subviews.count, 1)
        XCTAssertEqual(parent.view.constraints.count, 4)
        XCTAssertEqual(focused.view.constraints.count, 4)
        XCTAssertEqual(content.loadCount, 1)
        XCTAssertEqual(content.attachmentCount, 1)
    }

    func testWhenAvailableBoundsChangeThenFocusedContentFillsTheContainer() throws {
        let parent = UIViewController()
        let content = ContentViewControllerSpy()
        install(content, in: parent)
        update(content, in: parent, focused: true)
        let focused = try XCTUnwrap(content.view.superview)

        for size in [CGSize(width: 390, height: 500), CGSize(width: 844, height: 230)] {
            parent.view.frame = CGRect(origin: .zero, size: size)
            parent.view.layoutIfNeeded()
            focused.layoutIfNeeded()

            XCTAssertEqual(focused.frame, parent.view.bounds)
            XCTAssertEqual(content.view.frame, focused.bounds)
        }
    }

    func testWhenVisibleContentChangesPresentationThenItsAppearanceLifecycleDoesNotRestart() async {
        let parent = UIViewController()
        let content = ContentViewControllerSpy()
        let descendant = ContentViewControllerSpy()
        install(content, in: parent)
        content.addChild(descendant)
        content.view.addSubview(descendant.view)
        descendant.didMove(toParent: content)
        let appeared = expectation(description: "Content and descendant appeared in the window")
        appeared.expectedFulfillmentCount = 2
        content.onDidAppear = { appeared.fulfill() }
        descendant.onDidAppear = { appeared.fulfill() }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = parent
        window.isHidden = false
        parent.view.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        await fulfillment(of: [appeared], timeout: 2)
        content.onDidAppear = nil
        descendant.onDidAppear = nil
        XCTAssertNotNil(content.view.window)
        XCTAssertGreaterThan(content.didAppearCount, 0)
        XCTAssertGreaterThan(descendant.didAppearCount, 0)
        let contentAppearances = content.appearanceCounts
        let descendantAppearances = descendant.appearanceCounts
        for focused in [true, true, false, false, true, false] {
            update(content, in: parent, focused: focused)
            parent.view.layoutIfNeeded()
            XCTAssertTrue(content.view.window === window)
            XCTAssertEqual(content.appearanceCounts, contentAppearances)
            XCTAssertEqual(descendant.appearanceCounts, descendantAppearances)
        }
        XCTAssertEqual(content.attachmentCount, 1)
        XCTAssertEqual(descendant.attachmentCount, 1)

        // Genuine browser disappearance must still reach content and its descendants.
        update(content, in: parent, focused: true)
        parent.beginAppearanceTransition(false, animated: false)
        parent.endAppearanceTransition()
        XCTAssertEqual(content.didDisappearCount, contentAppearances[3] + 1)
        XCTAssertEqual(descendant.didDisappearCount, descendantAppearances[3] + 1)
    }

    private func install(_ content: UIViewController, in parent: UIViewController) {
        RedesignedNewTabPageFocusedViewController.install(content, in: parent, container: parent.view)
    }

    private func update(_ content: UIViewController, in parent: UIViewController, focused: Bool) {
        RedesignedNewTabPageFocusedViewController.updateContainment(
            of: content,
            in: parent,
            container: parent.view,
            usesFocusedContainer: focused)
    }
}

private final class ContentViewControllerSpy: UIViewController {
    var onDidAppear: (() -> Void)?
    private(set) var loadCount = 0
    private(set) var attachmentCount = 0
    private(set) var willAppearCount = 0
    private(set) var didAppearCount = 0
    private(set) var willDisappearCount = 0
    private(set) var didDisappearCount = 0

    var appearanceCounts: [Int] { [willAppearCount, didAppearCount, willDisappearCount, didDisappearCount] }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadCount += 1
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent != nil {
            attachmentCount += 1
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        willAppearCount += 1
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didAppearCount += 1
        onDidAppear?()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        willDisappearCount += 1
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        didDisappearCount += 1
    }
}
