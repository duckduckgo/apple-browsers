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

final class UnifiedInputSwipeTabsPanGestureRecognizer: UIPanGestureRecognizer {}

extension MainViewController {

    func installSwipeTabsGesturesForUnifiedInput() {
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
        swipeTabsCoordinator?.handleExternalPan(gesture)
    }

    func shouldBeginUnifiedInputSwipeTabsPan(_ pan: UIPanGestureRecognizer) -> Bool {
        guard let swipeTabsCoordinator, swipeTabsCoordinator.isEnabled else {
            return false
        }
        guard let coordinator = unifiedToggleInputCoordinator else {
            return false
        }

        if case .omnibar(.active) = coordinator.displayState {
            return false
        }
        if coordinator.viewController.isInputFirstResponder {
            return false
        }

        let velocity = pan.velocity(in: pan.view)
        let allow = abs(velocity.x) > abs(velocity.y)
        return allow
    }
}
