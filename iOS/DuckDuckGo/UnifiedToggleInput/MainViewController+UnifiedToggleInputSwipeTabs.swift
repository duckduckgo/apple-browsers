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

// Bridges swipe-between-tabs to the Unified Toggle Input surfaces. With UTI on, the bar that
// replaces the omnibar (and, on AI tabs, the chat header) sits as a sibling on top of
// `navigationBarCollectionView`, so the legacy swipe path — touches on the omnibar driving the
// collection view's pan recognizer — never fires. We attach our own pan recognizers and forward
// them to `SwipeTabsCoordinator.handleExternalPan(_:)`, which scrubs `contentOffset` to reuse
// the existing animation + tab-selection state machine.
extension MainViewController {

    func installSwipeTabsGesturesForUnifiedInput() {
        let utiPan = makeSwipeTabsPanGesture()
        viewCoordinator.unifiedToggleInputContainer.addGestureRecognizer(utiPan)

        if let header = aiChatTabChatHeaderView {
            let headerPan = makeSwipeTabsPanGesture()
            header.addGestureRecognizer(headerPan)
        }
    }

    private func makeSwipeTabsPanGesture() -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleUnifiedInputSwipeTabsPan(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        return pan
    }

    @objc func handleUnifiedInputSwipeTabsPan(_ gesture: UIPanGestureRecognizer) {
        swipeTabsCoordinator?.handleExternalPan(gesture)
    }

    func shouldBeginUnifiedInputSwipeTabsPan(_ pan: UIPanGestureRecognizer) -> Bool {
        guard let swipeTabsCoordinator, swipeTabsCoordinator.isEnabled else { return false }
        guard let coordinator = unifiedToggleInputCoordinator else { return false }

        // Editing states own their gesture surface — text selection, suggestion-tray scrolling,
        // and keyboard-driven layout all conflict with a horizontal page swipe.
        if coordinator.isInputEditing { return false }
        if coordinator.viewController.isInputFirstResponder { return false }

        // Horizontal-dominant only; lets vertical scrolls in nearby surfaces (e.g. the
        // suggestion tray, or future drag-to-dismiss gestures) win.
        let velocity = pan.velocity(in: pan.view)
        return abs(velocity.x) > abs(velocity.y)
    }
}
