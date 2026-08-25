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
/// Takes precedence over descendant scroll views (favorites collection view, suggestion list) so a
/// horizontal flick still switches mode without changing their content offset.
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
        let targetMode: TextEntryMode = gesture.direction == .left ? .aiChat : .search
        // Let the List's pan recognizer finish before changing its safe-area inset. Updating it from
        // inside the swipe callback can preserve an offset based on the previous UTI height.
        DispatchQueue.main.async { [weak self] in
            self?.onSwitch(targetMode)
        }
    }
}

extension ModeSwitchSwipeGestureController: UIGestureRecognizerDelegate {
    /// A scroll pan must wait for the horizontal flick to fail; otherwise its small vertical component
    /// changes the shared List offset while the UTI height is animating.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        !isScrollViewPan(other)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        isScrollViewPan(other)
    }

    private func isScrollViewPan(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let scrollView = gestureRecognizer.view as? UIScrollView else { return false }
        return gestureRecognizer === scrollView.panGestureRecognizer
    }
}
