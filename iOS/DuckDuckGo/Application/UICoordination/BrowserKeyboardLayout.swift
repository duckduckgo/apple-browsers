//
//  BrowserKeyboardLayout.swift
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

struct BrowserKeyboardLayout {
    let frame: CGRect
    let duration: TimeInterval
    let animationCurve: UIView.AnimationOptions

    init?(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let frame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return nil }
        self.frame = frame
        duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
        let curve = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue
        animationCurve = UIView.AnimationOptions(rawValue: curve ?? UIView.AnimationOptions.curveEaseInOut.rawValue)
    }

    static func obscuredInsets(chromeInsets: UIEdgeInsets, keyboardFrame: CGRect, viewBounds: CGRect) -> UIEdgeInsets {
        let overlap = viewBounds.intersection(keyboardFrame)
        guard !overlap.isNull, !overlap.isEmpty, overlap.maxY >= viewBounds.maxY else { return chromeInsets }
        var insets = chromeInsets
        insets.bottom = max(insets.bottom, overlap.height)
        return insets
    }
}
