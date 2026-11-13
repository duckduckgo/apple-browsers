//
//  NewTabKeyboardHideWait.swift
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

import PixelKit
import UIKit

/// Runs its action once, when the keyboard has hidden.
@MainActor
final class NewTabKeyboardHideWait {

    /// Only for a keyboardDidHide iOS never sends; a normal hide ends in about a third of this.
    static let safetyNetDelay: TimeInterval = 1

    private var action: (() -> Void)?
    private var observer: NSObjectProtocol?
    private let pixelFiring: PixelFiring?

    init(pixelFiring: PixelFiring? = PixelKit.shared, then action: @escaping () -> Void) {
        self.pixelFiring = pixelFiring
        self.action = action
    }

    func start() {
        observer = NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidHideNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.safetyNetDelay) { [self] in
            guard action != nil else { return }
            pixelFiring?.fire(NewTabTransitionPixel.keyboardHideMissed, frequency: .dailyAndCount)
            finish()
        }
    }

    /// Opens now, as when the focused field wouldn't let go of the keyboard.
    func finish() {
        guard let action else { return }
        self.action = nil
        observer.map(NotificationCenter.default.removeObserver)
        observer = nil
        action()
    }
}
