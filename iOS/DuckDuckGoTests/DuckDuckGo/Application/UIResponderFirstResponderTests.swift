//
//  UIResponderFirstResponderTests.swift
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

final class UIResponderFirstResponderTests: XCTestCase {

    private var window: UIWindow!
    private var rootViewController: UIViewController!
    private var sheetViewController: UIViewController!
    private var pickerViewController: UIViewController!

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        rootViewController = UIViewController()
        sheetViewController = UIViewController()
        pickerViewController = UIViewController()
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
        present(sheetViewController, from: rootViewController)
        present(pickerViewController, from: sheetViewController)
    }

    /// A presentation requested while another is still settling is deferred, so wait for each one.
    private func present(_ presented: UIViewController, from presenter: UIViewController) {
        let presentedExpectation = expectation(description: "presented \(presented)")
        presenter.present(presented, animated: false) { presentedExpectation.fulfill() }
        wait(for: [presentedExpectation], timeout: 5)
        XCTAssertTrue(presenter.presentedViewController === presented)
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    func testFieldInControllerPresentedOverSheetIsInSheetPresentationChain() {
        let field = UITextField()
        pickerViewController.view.addSubview(field)

        XCTAssertFalse(field.isInViewHierarchy(of: sheetViewController.view),
                       "a presented controller's view lives outside the sheet's own view")
        XCTAssertTrue(field.isInViewHierarchy(ofPresentationChainFrom: sheetViewController))
    }

    func testFieldInSheetItselfIsInSheetPresentationChain() {
        let field = UITextField()
        sheetViewController.view.addSubview(field)

        XCTAssertTrue(field.isInViewHierarchy(ofPresentationChainFrom: sheetViewController))
    }

    func testFieldBehindSheetIsNotInSheetPresentationChain() {
        let field = UITextField()
        rootViewController.view.addSubview(field)

        XCTAssertFalse(field.isInViewHierarchy(ofPresentationChainFrom: sheetViewController))
    }
}
