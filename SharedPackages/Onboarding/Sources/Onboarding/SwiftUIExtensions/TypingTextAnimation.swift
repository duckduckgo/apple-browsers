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

#if os(iOS)

import SwiftUI

// MARK: - Skip Environment Key

private struct TypingAnimationSkipKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// Set to `true` on a container to immediately skip all `TypingText` animations in the subtree.
    public var typingAnimationSkip: Bool {
        get { self[TypingAnimationSkipKey.self] }
        set { self[TypingAnimationSkipKey.self] = newValue }
    }
}

// MARK: - Animation State

/// Owns the typing timer and the published display text.
/// Uses weak self in the Timer callback to avoid retain cycles.
@MainActor
private final class TypingAnimationState: ObservableObject {
    @Published private(set) var displayedText: String = ""

    private var timer: Timer?
    /// Once set, `start()` becomes a no-op until `stop()` resets this flag.
    private var skipped = false
    private static let typingInterval: TimeInterval = 0.025

    func start(text: String, onFinished: (() -> Void)? = nil) {
        guard !skipped else { return }
        invalidateTimer()
        displayedText = ""
        guard !text.isEmpty else {
            displayedText = text
            onFinished?()
            return
        }

        var index = text.startIndex
        let t = Timer(timeInterval: Self.typingInterval, repeats: true) { [weak self] timer in
            // Timer is added to RunLoop.main so it always fires on the main thread;
            // assumeIsolated lets the compiler verify @MainActor property access is safe.
            MainActor.assumeIsolated {
                guard let self, timer.isValid else { return }
                text.formIndex(after: &index)
                self.displayedText = String(text[..<index])
                if index == text.endIndex {
                    timer.invalidate()
                    self.timer = nil
                    onFinished?()
                }
            }
        }
        // .common mode keeps the timer firing during scroll and other UI interactions.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func skip(to text: String, onFinished: (() -> Void)? = nil) {
        skipped = true
        invalidateTimer()
        displayedText = text
        onFinished?()
    }

    func stop() {
        skipped = false
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

/// Reveals text character-by-character with a typing animation.
///
/// The full text is rendered **hidden** to keep layout stable, with an overlay showing the
/// progressively revealed text. Supports `.font`, `.foregroundStyle`, `.multilineTextAlignment`, etc.
///
/// - Setting `.environment(\.typingAnimationSkip, true)` on a container instantly completes all
///   `TypingText` animations in the subtree (used for tap-to-skip).
/// - When `accessibilityReduceMotion` is enabled, the full text appears immediately.
public struct TypingText: View {
    private let text: String
    private let startAnimating: Binding<Bool>
    private let onTypingFinished: (() -> Void)?

    @StateObject private var state = TypingAnimationState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.typingAnimationSkip) private var skipAnimation

    public init(_ text: String, startAnimating: Binding<Bool> = .constant(true), onTypingFinished: (() -> Void)? = nil) {
        self.text = text
        self.startAnimating = startAnimating
        self.onTypingFinished = onTypingFinished
    }

    public var body: some View {
        // Hidden text reserves layout space; overlay reveals progressively.
        Text(text)
            .hidden()
            .overlay(alignment: .topLeading) { Text(state.displayedText) }
            .onChange(of: skipAnimation) { shouldSkip in
                if shouldSkip { state.skip(to: text, onFinished: onTypingFinished) }
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
                if shouldReduce { state.skip(to: text, onFinished: onTypingFinished) }
            }
            .onAppear {
                if reduceMotion || skipAnimation {
                    state.skip(to: text, onFinished: onTypingFinished)
                } else if startAnimating.wrappedValue {
                    state.start(text: text, onFinished: onTypingFinished)
                }
            }
            .onDisappear { state.stop() }
    }
}

#endif
