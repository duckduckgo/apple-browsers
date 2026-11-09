//
//  IdleReturnHiddenScreensTests.swift
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

import Testing
import UIKit
@testable import DuckDuckGo

@MainActor
struct IdleReturnHiddenScreensTests {

    private let screens = IdleReturnHiddenScreens()

    @available(iOS 16, macOS 13, *)
    @Test("A presented screen is hidden and handed over for closing", .timeLimit(.minutes(1)))
    func hidesAndHandsOver() {
        let screen = UIViewController()

        screens.hide(screen)

        #expect(screen.view.isHidden)
        #expect(screens.takeForClosing() === screen)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Restoring shows the screen again and forgets it", .timeLimit(.minutes(1)))
    func restoreShowsAndForgets() {
        let screen = UIViewController()
        screens.hide(screen)

        screens.restore()

        #expect(!screen.view.isHidden)
        #expect(screens.takeForClosing() == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The hidden screen is handed over for closing only once", .timeLimit(.minutes(1)))
    func handsOverOnce() {
        let screen = UIViewController()
        screens.hide(screen)
        _ = screens.takeForClosing()

        #expect(screens.takeForClosing() == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A screen handed over for closing stays hidden when a later return is cancelled", .timeLimit(.minutes(1)))
    func restoreAfterHandOverLeavesScreenHidden() {
        let screen = UIViewController()
        screens.hide(screen)
        _ = screens.takeForClosing()

        screens.restore()

        #expect(screen.view.isHidden)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An alert is neither hidden nor remembered", .timeLimit(.minutes(1)))
    func alertIsSkipped() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)

        screens.hide(alert)

        #expect(!alert.view.isHidden)
        #expect(screens.takeForClosing() == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A screen already being dismissed is neither hidden nor remembered", .timeLimit(.minutes(1)))
    func screenBeingDismissedIsSkipped() {
        let screen = DismissingViewController()

        screens.hide(screen)

        #expect(!screen.view.isHidden)
        #expect(screens.takeForClosing() == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With nothing presented, nothing is remembered and restoring does nothing", .timeLimit(.minutes(1)))
    func nothingPresented() {
        screens.hide(nil)
        screens.restore()

        #expect(screens.takeForClosing() == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A hidden screen released elsewhere is forgotten", .timeLimit(.minutes(1)))
    func releasedScreenIsForgotten() {
        autoreleasepool {
            screens.hide(UIViewController())
        }

        #expect(screens.takeForClosing() == nil)
    }

}

private final class DismissingViewController: UIViewController {
    override var isBeingDismissed: Bool { true }
}
