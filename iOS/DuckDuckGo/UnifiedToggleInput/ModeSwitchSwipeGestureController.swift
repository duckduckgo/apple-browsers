//
//  ModeSwitchSwipeGestureController.swift
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

/// Installs left/right flick recognizers that switch Search↔Duck.ai (Search is the left page),
/// mirroring a toggle tap. A quick flick triggers it; slow horizontal drags (e.g. row
/// swipe-to-delete) don't. The recognizers don't retain this controller — the owner must.
@MainActor
final class ModeSwitchSwipeGestureController: NSObject {

    private let onSwitch: (TextEntryMode) -> Void

    init(onSwitch: @escaping (TextEntryMode) -> Void) {
        self.onSwitch = onSwitch
    }

    func install(on view: UIView) {
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipe.direction = direction
            swipe.cancelsTouchesInView = false
            view.addGestureRecognizer(swipe)
        }
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        onSwitch(gesture.direction == .left ? .aiChat : .search)
    }
}
