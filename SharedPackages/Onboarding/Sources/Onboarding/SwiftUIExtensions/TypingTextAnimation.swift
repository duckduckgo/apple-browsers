//
//  TypingTextAnimation.swift
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

// MARK: - Animation State

/// Owns the typing timer and the published display text, enabling safe weak-capture inside the Timer callback.
private final class TypingAnimationState: ObservableObject {
    @Published private(set) var displayedText: String = ""

    private var timer: Timer?
    private static let typingInterval: TimeInterval = 0.04

    func start(text: String, onFinished: (() -> Void)? = nil) {
        invalidateTimer()
        displayedText = ""
        guard !text.isEmpty else {
            displayedText = text
            onFinished?()
            return
        }

        var index = text.startIndex
        let t = Timer(timeInterval: Self.typingInterval, repeats: true) { [weak self] timer in
            guard let self, timer.isValid else { return }
            text.formIndex(after: &index)
            displayedText = String(text[..<index])
            if index == text.endIndex {
                timer.invalidate()
                self.timer = nil
                onFinished?()
            }
        }
        // Schedule on .common so the timer fires during scroll and other UI interactions.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func skip(to text: String, onFinished: (() -> Void)? = nil) {
        invalidateTimer()
        displayedText = text
        onFinished?()
    }

    func stop() {
        invalidateTimer()
    }

    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}

// MARK: - TypingText

/// A `Text`-equivalent view that reveals its content character-by-character with a typing animation.
///
/// The full text is rendered **invisibly** to keep layout dimensions stable throughout the animation.
/// An overlay `Text` is drawn on top and updated every 20 ms. Because formatting propagates through
/// SwiftUI's environment, appearance modifiers (`.font`, `.foregroundStyle`, `.multilineTextAlignment`,
/// etc.) work exactly as they do on a plain `Text`:
///
/// ```swift
/// TypingText("Hello, world!", startAnimating: $shouldAnimate)
///     .font(.title)
///     .foregroundStyle(.primary)
///     .multilineTextAlignment(.center)
/// ```
///
/// Accessibility: when `accessibilityReduceMotion` is `true` the full text is shown immediately
/// without animation.
public struct TypingText: View {
    private let text: String
    private let startAnimating: Binding<Bool>
    private let onTypingFinished: (() -> Void)?

    @StateObject private var state = TypingAnimationState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ text: String, startAnimating: Binding<Bool> = .constant(true), onTypingFinished: (() -> Void)? = nil) {
        self.text = text
        self.startAnimating = startAnimating
        self.onTypingFinished = onTypingFinished
    }

    public var body: some View {
        Text(text)
            .hidden()   // Reserves layout space using the full text dimensions.
            .overlay {
                Text(state.displayedText)
            }
            .onChange(of: startAnimating.wrappedValue) { shouldAnimate in
                if shouldAnimate {
                    if reduceMotion {
                        state.skip(to: text, onFinished: onTypingFinished)
                    } else {
                        state.start(text: text, onFinished: onTypingFinished)
                    }
                } else {
                    state.stop()
                }
            }
            .onChange(of: reduceMotion) { shouldReduce in
                if shouldReduce {
                    state.skip(to: text, onFinished: onTypingFinished)
                }
            }
            .onAppear {
                if reduceMotion {
                    state.skip(to: text, onFinished: onTypingFinished)
                } else if startAnimating.wrappedValue {
                    state.start(text: text, onFinished: onTypingFinished)
                }
            }
            .onDisappear {
                state.stop()
            }
    }
}
