//
//  UIResponder+FirstResponder.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

extension UIResponder {

    /// Finds the current first responder in the application's key window.
    static func currentFirstResponder() -> UIResponder? {
        var firstResponder: UIResponder?

        func findFirstResponder(in view: UIView) {
            if view.isFirstResponder {
                firstResponder = view
                return
            }
            for subview in view.subviews {
                findFirstResponder(in: subview)
                if firstResponder != nil {
                    return
                }
            }
        }

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.isKeyWindow {
                findFirstResponder(in: window)
                if firstResponder != nil {
                    break
                }
            }
            if firstResponder != nil {
                break
            }
        }

        return firstResponder
    }

    /// Checks if this responder is within the view hierarchy of the specified parent view.
    /// Walks up the responder chain to determine if any UIView in the chain is a descendant of the parent view.
    func isInViewHierarchy(of parentView: UIView) -> Bool {
        var current: UIResponder? = self
        while let responder = current {
            if let currentView = responder as? UIView {
                if currentView == parentView || currentView.isDescendant(of: parentView) {
                    return true
                }
            }
            current = responder.next
        }
        return false
    }
}
