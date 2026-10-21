//
//  MainViewController+TabSwitcherSwipeUp.swift
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

extension MainViewController {

    func installTabSwitcherSwipeUpGesture() {
        tabSwitcherSwipeUpTransition.mainViewController = self
        tabSwitcherTransition.swipeUpTransition = tabSwitcherSwipeUpTransition

        let bottomChrome: [UIView?] = [
            viewCoordinator.toolbar,
            viewCoordinator.navigationBarContainer,
            viewCoordinator.unifiedToggleInputContainer,
        ]
        for view in bottomChrome.compactMap({ $0 }) {
            let pan = TabSwitcherSwipeUpGestureRecognizer(target: tabSwitcherSwipeUpTransition,
                                                          action: #selector(TabSwitcherSwipeUpTransition.handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            view.addGestureRecognizer(pan)
            // The omnibar collection view pages horizontally between tabs; it waits for a vertical swipe to fail.
            viewCoordinator.navigationBarCollectionView?.panGestureRecognizer.require(toFail: pan)
        }
    }

    func shouldBeginTabSwitcherSwipeUp(_ pan: UIPanGestureRecognizer) -> Bool {
        guard tabSwitcherSwipeUpTransition.canBegin,
              !viewCoordinator.omniBar.isTextFieldEditing else { return false }

        if let coordinator = unifiedToggleInputCoordinator,
           coordinator.isOmnibarEditing || coordinator.viewController.isInputFirstResponder {
            return false
        }

        let velocity = pan.velocity(in: pan.view)
        return velocity.y < 0 && abs(velocity.y) > abs(velocity.x)
    }
}
