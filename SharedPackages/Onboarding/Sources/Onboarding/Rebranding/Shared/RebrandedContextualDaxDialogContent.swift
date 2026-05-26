//
//  RebrandedContextualDaxDialogContent.swift
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
import UIComponents

/// Process-wide cache of dialogs that have completed their entrance animation. Keyed by
/// `(title? + message)` so a view rebuild (e.g. device rotation) skips re-animation and
/// renders the final state on the first frame.
private enum RebrandedContextualDaxDialogCache {
    static var completed: Set<String> = []

    static func key(title: NSAttributedString?, message: NSAttributedString) -> String {
        (title?.string ?? "") + "|" + message.string
    }

    static func isCompleted(title: NSAttributedString?, message: NSAttributedString) -> Bool {
        completed.contains(key(title: title, message: message))
    }

    static func markCompleted(title: NSAttributedString?, message: NSAttributedString) {
        completed.insert(key(title: title, message: message))
    }
}

extension OnboardingRebranding {

    public enum ContextualDaxDialogOrientation: Equatable {
        case verticalStack
        case horizontalStack(alignment: VerticalAlignment)
    }

    public struct ContextualDaxDialogContent<Content: View>: View {
        @Environment(\.onboardingTheme.contextualOnboardingMetrics) private var theme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private let orientation: ContextualDaxDialogOrientation
        private let title: NSAttributedString?
        private let message: NSAttributedString

        private let titleTextAlignment: TextAlignment?
        private let messageTextAlignment: TextAlignment?
        private let titleBodyVerticalSpacingOverride: CGFloat?
        private let content: Content

        @State private var startTypingTitle: Bool
        @State private var startTypingMessage: Bool
        @State private var shouldShowContent: Bool

        #if os(iOS)
        public init(
            orientation: ContextualDaxDialogOrientation = .verticalStack,
            title: AttributedString? = nil,
            titleTextAlignment: TextAlignment? = nil,
            message: AttributedString,
            messageTextAlignment: TextAlignment? = nil,
            titleBodyVerticalSpacingOverride: CGFloat? = nil,
            @ViewBuilder content: () -> Content
        ) {
            let nsTitle = title.map(NSAttributedString.init)
            let nsMessage = NSAttributedString(message)
            self.orientation = orientation
            self.title = nsTitle
            self.titleTextAlignment = titleTextAlignment
            self.message = nsMessage
            self.messageTextAlignment = messageTextAlignment
            self.titleBodyVerticalSpacingOverride = titleBodyVerticalSpacingOverride
            self.content = content()
            let cached = RebrandedContextualDaxDialogCache.isCompleted(title: nsTitle, message: nsMessage)
            _startTypingTitle = State(initialValue: cached)
            _startTypingMessage = State(initialValue: cached)
            _shouldShowContent = State(initialValue: cached)
        }

        public init(
            orientation: ContextualDaxDialogOrientation = .verticalStack,
            title: String? = nil,
            titleTextAlignment: TextAlignment? = nil,
            message: String,
            messageTextAlignment: TextAlignment? = nil,
            titleBodyVerticalSpacingOverride: CGFloat? = nil,
            @ViewBuilder content: () -> Content
        ) {
            self.init(
                orientation: orientation,
                title: title.flatMap(AttributedString.init),
                titleTextAlignment: titleTextAlignment,
                message: AttributedString(message),
                messageTextAlignment: messageTextAlignment,
                titleBodyVerticalSpacingOverride: titleBodyVerticalSpacingOverride,
                content: content
            )
        }

        #else
        public init(
            orientation: ContextualDaxDialogOrientation = .verticalStack,
            title: NSAttributedString? = nil,
            titleTextAlignment: TextAlignment? = nil,
            message: NSAttributedString,
            messageTextAlignment: TextAlignment? = nil,
            titleBodyVerticalSpacingOverride: CGFloat? = nil,
            @ViewBuilder content: () -> Content
        ) {
            self.orientation = orientation
            self.title = title
            self.titleTextAlignment = titleTextAlignment
            self.message = message
            self.messageTextAlignment = messageTextAlignment
            self.titleBodyVerticalSpacingOverride = titleBodyVerticalSpacingOverride
            self.content = content()
            let cached = RebrandedContextualDaxDialogCache.isCompleted(title: title, message: message)
            _startTypingTitle = State(initialValue: cached)
            _startTypingMessage = State(initialValue: cached)
            _shouldShowContent = State(initialValue: cached)
        }
        #endif

        public var body: some View {
            let cached = RebrandedContextualDaxDialogCache.isCompleted(title: title, message: message)
            Group {
                switch orientation {
                case .verticalStack:
                    VStack(alignment: .leading, spacing: theme.contentSpacing) {
                        TypingTitleMessageStack(
                            title: title,
                            message: message,
                            titleBodyVerticalSpacing: titleBodyVerticalSpacingOverride ?? theme.titleBodyVerticalSpacingVerticalLayout,
                            titleTextAlignment: titleTextAlignment,
                            messageTextAlignment: messageTextAlignment,
                            startTypingTitle: $startTypingTitle,
                            startTypingMessage: $startTypingMessage,
                            initiallyRevealed: cached,
                            onTypingFinished: animateContentIn
                        )
                        content
                            .visibility(shouldShowContent ? .visible : .invisible)
                    }
                case let .horizontalStack(alignment):
                    HStack(alignment: alignment) {
                        TypingTitleMessageStack(
                            title: title,
                            message: message,
                            titleBodyVerticalSpacing: titleBodyVerticalSpacingOverride ?? theme.titleBodyVerticalSpacingHorizontalLayout,
                            titleTextAlignment: titleTextAlignment,
                            messageTextAlignment: messageTextAlignment,
                            startTypingTitle: $startTypingTitle,
                            startTypingMessage: $startTypingMessage,
                            initiallyRevealed: cached,
                            onTypingFinished: animateContentIn
                        )
                        Spacer(minLength: theme.contentSpacing)
                        content
                            .visibility(shouldShowContent ? .visible : .invisible)
                    }
                }
            }
            .onAppear {
                guard !RebrandedContextualDaxDialogCache.isCompleted(title: title, message: message) else { return }
                Task { @MainActor in
                    try await Task.sleep(interval: theme.contentFadeInDelay)
                    if title != nil {
                        startTypingTitle = true
                    } else {
                        startTypingMessage = true
                    }
                }
            }
        }

        private func animateContentIn() {
            RebrandedContextualDaxDialogCache.markCompleted(title: title, message: message)
            if reduceMotion {
                shouldShowContent = true
            } else {
                withAnimation(.easeIn(duration: theme.contentFadeInDuration).delay(0.1)) {
                    shouldShowContent = true
                }
            }
        }
    }
}

#if os(iOS)
extension OnboardingRebranding.ContextualDaxDialogContent where Content == EmptyView {

    /// Convenience initializer for dialogs without additional content.
    public init(
        orientation: OnboardingRebranding.ContextualDaxDialogOrientation = .verticalStack,
        title: AttributedString? = nil,
        titleBodyVerticalSpacingOverride: CGFloat? = nil,
        message: AttributedString
    ) {
        self.init(orientation: orientation, title: title, message: message, titleBodyVerticalSpacingOverride: titleBodyVerticalSpacingOverride) {
            EmptyView()
        }
    }

    /// Convenience initializer for dialogs without additional content, accepting plain strings.
    public init(
        orientation: OnboardingRebranding.ContextualDaxDialogOrientation = .verticalStack,
        title: String? = nil,
        titleBodyVerticalSpacingOverride: CGFloat? = nil,
        message: String
    ) {
        self.init(
            orientation: orientation,
            title: title.flatMap(AttributedString.init),
            message: AttributedString(message),
            titleBodyVerticalSpacingOverride: titleBodyVerticalSpacingOverride
        ) {
            EmptyView()
        }
    }
}
#endif

#if os(macOS)
extension OnboardingRebranding.ContextualDaxDialogContent where Content == EmptyView {

    /// Convenience initializer for dialogs without additional content.
    public init(
        orientation: OnboardingRebranding.ContextualDaxDialogOrientation = .verticalStack,
        title: NSAttributedString? = nil,
        titleBodyVerticalSpacingOverride: CGFloat? = nil,
        message: NSAttributedString
    ) {
        self.init(orientation: orientation, title: title, message: message, titleBodyVerticalSpacingOverride: titleBodyVerticalSpacingOverride) {
            EmptyView()
        }
    }
}
#endif

// MARK: Inner Views

private extension OnboardingRebranding {

    struct TypingTitleMessageStack: View {
        @Environment(\.onboardingTheme) private var theme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        let title: NSAttributedString?
        let message: NSAttributedString

        let titleBodyVerticalSpacing: CGFloat

        var titleTextAlignment: TextAlignment?
        var messageTextAlignment: TextAlignment?

        @Binding var startTypingTitle: Bool
        @Binding var startTypingMessage: Bool
        let initiallyRevealed: Bool
        let onTypingFinished: () -> Void

        #if os(iOS)
        @State private var showStaticMessage: Bool
        #endif

        init(
            title: NSAttributedString?,
            message: NSAttributedString,
            titleBodyVerticalSpacing: CGFloat,
            titleTextAlignment: TextAlignment? = nil,
            messageTextAlignment: TextAlignment? = nil,
            startTypingTitle: Binding<Bool>,
            startTypingMessage: Binding<Bool>,
            initiallyRevealed: Bool,
            onTypingFinished: @escaping () -> Void
        ) {
            self.title = title
            self.message = message
            self.titleBodyVerticalSpacing = titleBodyVerticalSpacing
            self.titleTextAlignment = titleTextAlignment
            self.messageTextAlignment = messageTextAlignment
            self._startTypingTitle = startTypingTitle
            self._startTypingMessage = startTypingMessage
            self.initiallyRevealed = initiallyRevealed
            self.onTypingFinished = onTypingFinished
            #if os(iOS)
            _showStaticMessage = State(initialValue: initiallyRevealed)
            #endif
        }

        var body: some View {
            VStack(alignment: .leading, spacing: titleBodyVerticalSpacing) {
                if let title {
                    let titleAlignment = titleTextAlignment ?? theme.contextualOnboardingMetrics.contextualTitleTextAlignment
                    titleTypingView(title, alignment: titleAlignment)
                }
                let messageAlignment = messageTextAlignment ?? theme.contextualOnboardingMetrics.contextualBodyTextAlignment
                messageTypingView(alignment: messageAlignment)
            }
            .padding(theme.contextualOnboardingMetrics.titleBodyInset)
            .fixedSize(horizontal: false, vertical: true)
        }

        #if os(iOS)
        @ViewBuilder
        private func titleTypingView(_ title: NSAttributedString, alignment: TextAlignment) -> some View {
            AnimatableTypingText(
                title,
                startAnimating: $startTypingTitle,
                skipAnimation: .constant(initiallyRevealed),
                alignment: Alignment(alignment),
                onTypingFinished: { revealStaticMessageAndFinish() }
            )
            .font(theme.typography.contextual.title)
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity, alignment: Alignment(alignment))
        }

        @ViewBuilder
        private func messageTypingView(alignment: TextAlignment) -> some View {
            Text(attributedStringWithAttachments: message)
                .font(theme.typography.contextual.body)
                .multilineTextAlignment(alignment)
                .frame(maxWidth: .infinity, alignment: Alignment(alignment))
                .opacity(showStaticMessage ? 1 : 0)
                .onChange(of: startTypingMessage) { shouldStart in
                    if shouldStart { revealStaticMessageAndFinish() }
                }
        }

        private func revealStaticMessageAndFinish() {
            guard !reduceMotion else {
                showStaticMessage = true
                onTypingFinished()
                return
            }
            let duration = theme.contextualOnboardingMetrics.contentFadeInDuration
            withAnimation(.easeIn(duration: duration)) {
                showStaticMessage = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                onTypingFinished()
            }
        }
        #else
        @ViewBuilder
        private func titleTypingView(_ title: NSAttributedString, alignment: TextAlignment) -> some View {
            AnimatableTypingText(
                title,
                startAnimating: $startTypingTitle,
                skipAnimation: .constant(initiallyRevealed),
                alignment: Alignment(alignment),
                onTypingFinished: { startTypingMessage = true }
            )
            .font(theme.typography.contextual.title)
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity, alignment: Alignment(alignment))
        }

        @ViewBuilder
        private func messageTypingView(alignment: TextAlignment) -> some View {
            AnimatableTypingText(
                message,
                startAnimating: $startTypingMessage,
                skipAnimation: .constant(initiallyRevealed),
                alignment: Alignment(alignment),
                onTypingFinished: onTypingFinished
            )
            .font(theme.typography.contextual.body)
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity, alignment: Alignment(alignment))
        }
        #endif
    }

}

// MARK: - Helpers

private extension Alignment {

    init(_ textAlignment: TextAlignment) {
        switch textAlignment {
        case .center:
            self = .center
        case .leading:
            self = .leading
        case .trailing:
            self = .trailing
        }
    }

}
