//
//  SlideToDeleteFeedback.swift
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

@MainActor
final class SlideToDeleteFeedback: ObservableObject {
    private var generator: UIImpactFeedbackGenerator?
    private var isTouchActive = false

    func attach(to view: UIView) {
        if #available(iOS 17.5, *) {
            generator = UIImpactFeedbackGenerator(style: .medium, view: view)
        } else {
            generator = UIImpactFeedbackGenerator(style: .medium)
        }
    }

    func prepare() {
        generator?.prepare()
    }

    @discardableResult
    func beginTouch() -> Bool {
        guard !isTouchActive else { return false }
        isTouchActive = true
        prepare()
        guard let generator else { return false }
        generator.impactOccurred(intensity: 0.45)
        return true
    }

    func endTouch() {
        isTouchActive = false
    }

    @discardableResult
    func impact() -> Bool {
        guard let generator else { return false }
        generator.impactOccurred()
        return true
    }
}

struct SlideToDeleteFeedbackView: UIViewRepresentable {
    let feedback: SlideToDeleteFeedback

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isAccessibilityElement = false
        feedback.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) { }
}
