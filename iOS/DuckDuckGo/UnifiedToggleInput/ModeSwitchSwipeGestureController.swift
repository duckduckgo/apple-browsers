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
///
/// Recognizes simultaneously with descendant scroll views (favorites collection view, suggestion
/// list) so a horizontal flick still switches mode even when it lands on scrollable content.
@MainActor
final class ModeSwitchSwipeGestureController: NSObject {

    private let onSwitch: (TextEntryMode) -> Void
    private var recognizers: [UISwipeGestureRecognizer] = []

    /// Suppresses the mode-switch flick (e.g. while the toggle pill is being dragged) without
    /// uninstalling the recognizers.
    var isEnabled = true {
        didSet { recognizers.forEach { $0.isEnabled = isEnabled } }
    }

    init(onSwitch: @escaping (TextEntryMode) -> Void) {
        self.onSwitch = onSwitch
    }

    func install(on view: UIView) {
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipe.direction = direction
            // Cancel the underlying touch once the swipe is recognized so a flick doesn't also fire a
            // row tap / favorite selection. (A sub-threshold movement never recognizes, so taps and
            // scrolls are unaffected.)
            swipe.cancelsTouchesInView = true
            swipe.isEnabled = isEnabled
            swipe.delegate = self
            recognizers.append(swipe)
            view.addGestureRecognizer(swipe)
        }
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        onSwitch(gesture.direction == .left ? .aiChat : .search)
    }
}

extension ModeSwitchSwipeGestureController: UIGestureRecognizerDelegate {
    /// Coexist with every other recognizer (scroll pans AND the SwiftUI/favorites content gesture)
    /// so a horizontal flick is always recognized; `cancelsTouchesInView` then stops it co-firing a tap.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
