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

/// Owns the typing timer and the published visible character count.
/// Uses weak self in the Timer callback to avoid retain cycles.
@MainActor
private final class TypingAnimationState: ObservableObject {
    /// Number of characters currently visible. The view uses this to style
    /// typed characters as visible and the remainder as transparent.
    @Published private(set) var visibleCount: Int = 0
    /// `true` once the full text has been revealed (or skipped).
    @Published private(set) var isFinished: Bool = false

    private var timer: Timer?
    /// Once set, `start()` becomes a no-op until `stop()` resets this flag.
    private var skipped = false
    private static let typingInterval: TimeInterval = 0.02

    func start(totalCount: Int, onFinished: (() -> Void)? = nil) {
        guard !skipped else { return }
        invalidateTimer()
        visibleCount = 0
        isFinished = false
        guard totalCount > 0 else {
            visibleCount = totalCount
            isFinished = true
            onFinished?()
            return
        }

        var current = 0
        let t = Timer(timeInterval: Self.typingInterval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, timer.isValid else { return }
                current += 1
                self.visibleCount = current
                if current >= totalCount {
                    timer.invalidate()
                    self.timer = nil
                    self.isFinished = true
                    onFinished?()
                }
            }
        }
        // .common mode keeps the timer firing during scroll and other UI interactions.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func skip(totalCount: Int, onFinished: (() -> Void)? = nil) {
        skipped = true
        invalidateTimer()
        visibleCount = totalCount
        isFinished = true
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
    private let attributedText: AttributedString
    private let startAnimating: Binding<Bool>
    private let onTypingFinished: (() -> Void)?

    @StateObject private var state = TypingAnimationState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.typingAnimationSkip) private var skipAnimation

    public init(_ attributedText: AttributedString, startAnimating: Binding<Bool> = .constant(true), onTypingFinished: (() -> Void)? = nil) {
        self.attributedText = attributedText
        self.startAnimating = startAnimating
        self.onTypingFinished = onTypingFinished
    }

    public init(_ text: String, startAnimating: Binding<Bool> = .constant(true), onTypingFinished: (() -> Void)? = nil) {
        self.init(AttributedString(text), startAnimating: startAnimating, onTypingFinished: onTypingFinished)
    }

    /// Builds an `AttributedString` where the first `visibleCount` characters inherit
    /// the environment's foreground style and the rest are transparent.
    /// Because the full text is always rendered, line breaks never shift.
    private var revealedText: Text {
        if state.isFinished {
            return Text(attributedText)
        }

        let splitIndex = attributedText.characters.index(attributedText.startIndex, offsetBy: state.visibleCount)
        let visibleAttributedString = AttributedString(attributedText[..<splitIndex])
        var hiddenAttributedString = AttributedString(attributedText[splitIndex...])
        hiddenAttributedString.foregroundColor = .clear

        return Text(visibleAttributedString) + Text(hiddenAttributedString)
    }

    public var body: some View {
        revealedText
            .onChange(of: skipAnimation) { shouldSkip in
                if shouldSkip { state.skip(totalCount: attributedText.characters.count, onFinished: onTypingFinished) }
            }
            .onChange(of: startAnimating.wrappedValue) { shouldAnimate in
                if shouldAnimate {
                    if reduceMotion {
                        state.skip(totalCount: attributedText.characters.count, onFinished: onTypingFinished)
                    } else {
                        state.start(totalCount: attributedText.characters.count, onFinished: onTypingFinished)
                    }
                } else {
                    state.stop()
                }
            }
            .onChange(of: reduceMotion) { shouldReduce in
                if shouldReduce { state.skip(totalCount: attributedText.characters.count, onFinished: onTypingFinished) }
            }
            .onAppear {
                if reduceMotion || skipAnimation {
                    state.skip(totalCount: attributedText.characters.count, onFinished: onTypingFinished)
                } else if startAnimating.wrappedValue {
                    state.start(totalCount: attributedText.characters.count, onFinished: onTypingFinished)
                }
            }
            .onDisappear { state.stop() }
    }
}

#endif
