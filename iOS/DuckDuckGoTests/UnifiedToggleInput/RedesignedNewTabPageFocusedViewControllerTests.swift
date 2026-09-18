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

    func testWhenBrowserContentIsFocusedThenSameContentIsHostedAndLoadedOnlyOnce() throws {
        let parent = UIViewController()
        let content = ContentViewControllerSpy()
        attach(content, to: parent, focused: false)
        XCTAssertTrue(content.parent === parent)

        attach(content, to: parent, focused: true)
        let focused = try XCTUnwrap(content.parent as? RedesignedNewTabPageFocusedViewController)
        attach(content, to: parent, focused: true)

        XCTAssertTrue(focused.parent === parent)
        XCTAssertEqual(parent.children, [focused])
        XCTAssertEqual(focused.children, [content])
        XCTAssertTrue(content.view.superview === focused.view)
        XCTAssertEqual(content.loadCount, 1)
        XCTAssertEqual(content.attachmentCount, 2)
    }

    func testWhenLeavingFocusedPresentationThenWrapperIsReleasedAndContentReturnsToBrowser() {
        let parent = UIViewController()
        let content = ContentViewControllerSpy()
        attach(content, to: parent, focused: true)
        weak var focused = content.parent

        attach(content, to: parent, focused: false)
        attach(content, to: parent, focused: false)

        XCTAssertNil(focused)
        XCTAssertEqual(parent.children, [content])
        XCTAssertTrue(content.view.superview === parent.view)
        XCTAssertEqual(parent.view.subviews, [content.view])
        XCTAssertEqual(content.attachmentCount, 2)
    }

    func testWhenImmediatelyRefocusingThenContentIsReusedWithoutAccumulatingChildrenOrConstraints() {
        let parent = UIViewController()
        let content = ContentViewControllerSpy()
        for _ in 0..<3 {
            attach(content, to: parent, focused: true)
            attach(content, to: parent, focused: false)
        }
        attach(content, to: parent, focused: true)

        XCTAssertEqual(parent.children.count, 1)
        XCTAssertEqual(content.parent?.children, [content])
        XCTAssertEqual(parent.view.subviews.count, 1)
        XCTAssertEqual(parent.view.constraints.count, 4)
        XCTAssertEqual(content.parent?.view.constraints.count, 4)
        XCTAssertEqual(content.loadCount, 1)
    }

    func testWhenAvailableBoundsChangeThenFocusedContentFillsTheContainer() throws {
        let parent = UIViewController()
        let content = ContentViewControllerSpy()
        attach(content, to: parent, focused: true)
        let focused = try XCTUnwrap(content.parent)

        for size in [CGSize(width: 390, height: 500), CGSize(width: 844, height: 230)] {
            parent.view.frame = CGRect(origin: .zero, size: size)
            parent.view.layoutIfNeeded()
            focused.view.layoutIfNeeded()

            XCTAssertEqual(focused.view.frame, parent.view.bounds)
            XCTAssertEqual(content.view.frame, focused.view.bounds)
        }
    }

    private func attach(_ content: UIViewController, to parent: UIViewController, focused: Bool) {
        RedesignedNewTabPageFocusedViewController.updateContainment(
            of: content,
            in: parent,
            container: parent.view,
            usesFocusedContainer: focused)
    }
}

private final class ContentViewControllerSpy: UIViewController {
    private(set) var loadCount = 0
    private(set) var attachmentCount = 0

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
}
