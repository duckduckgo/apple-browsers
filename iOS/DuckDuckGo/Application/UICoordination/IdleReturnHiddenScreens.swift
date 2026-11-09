//
//  IdleReturnHiddenScreens.swift
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

/// The screen a warm return's New Tab Page draw hid: hidden rather than dismissed, because the return can
/// still be cancelled at Face ID and UIKit only completes a dismissal once the app is active.
@MainActor
final class IdleReturnHiddenScreens {

    private weak var hidden: UIViewController?
    /// Non-nil while a close is in progress: what waits for it to finish.
    private var waitingForClose: [() -> Void]?

    /// Hides `presented` and anything it presents. Skips an alert, which would leave a site's request
    /// unanswered, and a screen already being dismissed.
    func hide(_ presented: UIViewController?) {
        guard let presented, !presented.isBeingDismissed, !(presented is UIAlertController) else { return }
        setHidden(true, from: presented)
        hidden = presented
    }

    /// The return was cancelled: shows the hidden screens as they were.
    func restore() {
        guard let hidden else { return }
        setHidden(false, from: hidden)
        self.hidden = nil
    }

    /// The return is certain: hands over the hidden screen to be dismissed, once.
    func takeForClosing() -> UIViewController? {
        defer { hidden = nil }
        // A new close replaces one whose foreground ended before UIKit finished it.
        waitingForClose = hidden == nil ? nil : []
        return hidden
    }

    /// The hidden screens are gone: runs what waited for them.
    func didClose() {
        let waiting = waitingForClose ?? []
        waitingForClose = nil
        waiting.forEach { $0() }
    }

    /// Runs `handler` once nothing a draw hid is still closing, right away if nothing is.
    func runWhenClosed(_ handler: @escaping () -> Void) {
        if waitingForClose != nil {
            waitingForClose?.append(handler)
        } else {
            handler()
        }
    }

    /// The container also holds the dimming behind a sheet; a screen with none falls back to its own view.
    private func setHidden(_ isHidden: Bool, from screen: UIViewController) {
        var current: UIViewController? = screen
        while let screen = current {
            (screen.presentationController?.containerView ?? screen.view)?.isHidden = isHidden
            current = screen.presentedViewController
        }
    }

}
