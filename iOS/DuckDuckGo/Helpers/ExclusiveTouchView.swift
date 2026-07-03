//
//  ExclusiveTouchView.swift
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

import SwiftUI
import UIKit

final class ExclusiveTouchHandle {
    fileprivate weak var view: ExclusiveTouchView.UIViewType?

    func cancel() {
        view?.cancelEnclosingGestures()
    }
}

/// Allows us to cancel enclosing GestureRecognizers to avoid external interference while processing a SwiftUI Gesture
///
struct ExclusiveTouchView: UIViewRepresentable {
    let handle: ExclusiveTouchHandle

    func makeUIView(context: Context) -> UIViewType {
        let view = UIViewType()
        handle.view = view
        return view
    }

    func updateUIView(_ uiView: UIViewType, context: Context) {
        // NO-OP
    }

    final class UIViewType: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

        /// Walks the superview chain and bounces every gesture recognizer's `isEnabled` to force any in-flight recognizers to fail.
        /// Needed because the EscapeHatch row lives inside the Search/Duck.ai switcher container, whose horizontal swipe
        /// recognizer otherwise wins the horizontal pan and flips modes — dismissing the EscapeHatch mid-swipe.
        /// Called when our own DragGesture begins so the enclosing recognizers drop the touch sequence and the row's
        /// swipe-to-reveal action can complete uncontested.
        func cancelEnclosingGestures() {
            var current: UIView? = superview
            while let view = current {
                for recognizer in view.gestureRecognizers ?? [] {
                    recognizer.isEnabled = false
                    recognizer.isEnabled = true
                }
                current = view.superview
            }
        }
    }
}
