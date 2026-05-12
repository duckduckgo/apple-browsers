//
//  MainViewController+UnifiedToggleInputSwipeTabs.swift
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
import os.log

/// Marker subclass — used to identify "our" pan recognizers in `gestureRecognizerShouldBegin`
/// without having to maintain a list of `pan.view` comparisons that grows with every surface.
final class UnifiedInputSwipeTabsPanGestureRecognizer: UIPanGestureRecognizer {}

// Bridges swipe-between-tabs to the Unified Toggle Input surfaces. With UTI on, the bar that
// replaces the omnibar (and, on AI tabs, the chat header) sits as a sibling on top of
// `navigationBarCollectionView`, so the legacy swipe path — touches on the omnibar driving the
// collection view's pan recognizer — never fires. We attach our own pan recognizers and forward
// them to `SwipeTabsCoordinator.handleExternalPan(_:)`, which scrubs `contentOffset` to reuse
// the existing animation + tab-selection state machine.
extension MainViewController {

    func installSwipeTabsGesturesForUnifiedInput() {
        Logger.swipeTabs.debug("installSwipeTabsGesturesForUnifiedInput: attaching to unifiedToggleInputContainer + aiChatTabChatHeaderContainer + toolbar")
        viewCoordinator.unifiedToggleInputContainer.addGestureRecognizer(makeSwipeTabsPanGesture())
        viewCoordinator.aiChatTabChatHeaderContainer.addGestureRecognizer(makeSwipeTabsPanGesture())
        viewCoordinator.toolbar.addGestureRecognizer(makeSwipeTabsPanGesture())
        swipeTabsCoordinator?.auxiliarySwipeViews = [
            viewCoordinator.unifiedToggleInputContainer,
            viewCoordinator.aiChatTabChatHeaderContainer,
        ]
    }

    private func makeSwipeTabsPanGesture() -> UnifiedInputSwipeTabsPanGestureRecognizer {
        let pan = UnifiedInputSwipeTabsPanGestureRecognizer(target: self, action: #selector(handleUnifiedInputSwipeTabsPan(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        return pan
    }

    @objc func handleUnifiedInputSwipeTabsPan(_ gesture: UnifiedInputSwipeTabsPanGestureRecognizer) {
        Logger.swipeTabs.debug("handleUnifiedInputSwipeTabsPan: state=\(String(describing: gesture.state.rawValue)) source=\(String(describing: gesture.view.map { type(of: $0) }))")
        swipeTabsCoordinator?.handleExternalPan(gesture)
    }

    func shouldBeginUnifiedInputSwipeTabsPan(_ pan: UIPanGestureRecognizer) -> Bool {
        guard let swipeTabsCoordinator, swipeTabsCoordinator.isEnabled else {
            Logger.swipeTabs.debug("shouldBegin: false — swipeTabsCoordinator missing or disabled")
            return false
        }
        guard let coordinator = unifiedToggleInputCoordinator else {
            Logger.swipeTabs.debug("shouldBegin: false — UTI coordinator missing")
            return false
        }

        // Don't use `isInputEditing` here — it lumps `.aiTab(.expanded)` (Duck.ai's normal
        // "chat input is expanded" layout, no keyboard required) in with real editing sessions
        // and would block every pan while sitting on Duck.ai. Block only the two states where
        // a horizontal page swipe would genuinely steal from the user's current task:
        //   1. `.omnibar(.active)` — suggestion tray is open + keyboard up for URL editing.
        //   2. The input is first responder — user is actively typing somewhere.
        if case .omnibar(.active) = coordinator.displayState {
            Logger.swipeTabs.debug("shouldBegin: false — omnibar URL editing is active")
            return false
        }
        if coordinator.viewController.isInputFirstResponder {
            Logger.swipeTabs.debug("shouldBegin: false — UTI input is first responder")
            return false
        }

        // Horizontal-dominant only; lets vertical scrolls in nearby surfaces (e.g. the
        // suggestion tray, or future drag-to-dismiss gestures) win.
        let velocity = pan.velocity(in: pan.view)
        let allow = abs(velocity.x) > abs(velocity.y)
        Logger.swipeTabs.debug("shouldBegin: \(allow) — velocity=\(String(describing: velocity)) source=\(String(describing: pan.view.map { type(of: $0) })) displayState=\(String(describing: coordinator.displayState))")
        return allow
    }
}
