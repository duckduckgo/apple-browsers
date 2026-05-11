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

extension OnboardingRebranding {

    public enum ContextualDaxDialogOrientation: Equatable {
        case verticalStack
        case horizontalStack(alignment: VerticalAlignment)
    }

    public struct ContextualDaxDialogContent<Content: View>: View {
        @Environment(\.onboardingTheme.contextualOnboardingMetrics) private var theme

        private let orientation: ContextualDaxDialogOrientation
        private let title: NSAttributedString?
        private let message: NSAttributedString

        private let titleTextAlignment: TextAlignment?
        private let messageTextAlignment: TextAlignment?
        private let titleBodyVerticalSpacingOverride: CGFloat?
        private let content: Content

        @State private var startTypingTitle = false
        @State private var startTypingMessage = false
        @State private var shouldShowContent = false

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
            self.orientation = orientation
            self.title = title.map(NSAttributedString.init)
            self.titleTextAlignment = titleTextAlignment
            self.message = NSAttributedString(message)
            self.messageTextAlignment = messageTextAlignment
            self.titleBodyVerticalSpacingOverride = titleBodyVerticalSpacingOverride
            self.content = content()
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
        }
        #endif

        public var body: some View {
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
                            onTypingFinished: animateContentIn
                        )
                        Spacer(minLength: theme.contentSpacing)
                        content
                            .visibility(shouldShowContent ? .visible : .invisible)
                    }
                }
            }
            .onAppear {
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
            withAnimation(.easeIn(duration: theme.contentFadeInDuration).delay(0.1)) {
                shouldShowContent = true
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

        let title: NSAttributedString?
        let message: NSAttributedString

        let titleBodyVerticalSpacing: CGFloat

        var titleTextAlignment: TextAlignment?
        var messageTextAlignment: TextAlignment?

        @Binding var startTypingTitle: Bool
        @Binding var startTypingMessage: Bool
        let onTypingFinished: () -> Void

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
            // In horizontal layouts (text + button side-by-side), SwiftUI will
            // truncate the text to a single line unless we tell it to size to
            // its content vertically — wrap instead of truncate.
            .fixedSize(horizontal: false, vertical: true)
        }

        #if os(iOS)
        @ViewBuilder
        private func titleTypingView(_ title: NSAttributedString, alignment: TextAlignment) -> some View {
            AnimatableTypingText(title, startAnimating: $startTypingTitle, onTypingFinished: {
                startTypingMessage = true
            })
            .font(theme.typography.contextual.title)
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity, alignment: Alignment(alignment))
        }

        @ViewBuilder
        private func messageTypingView(alignment: TextAlignment) -> some View {
            AnimatableTypingText(message, startAnimating: $startTypingMessage, onTypingFinished: onTypingFinished)
                .font(theme.typography.contextual.body)
                .multilineTextAlignment(alignment)
                .frame(maxWidth: .infinity, alignment: Alignment(alignment))
        }
        #else
        @ViewBuilder
        private func titleTypingView(_ title: NSAttributedString, alignment: TextAlignment) -> some View {
            AnimatableTypingText(title, startAnimating: $startTypingTitle, onTypingFinished: {
                startTypingMessage = true
            })
            .font(theme.typography.contextual.title)
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity, alignment: Alignment(alignment))
        }

        @ViewBuilder
        private func messageTypingView(alignment: TextAlignment) -> some View {
            AnimatableTypingText(message, startAnimating: $startTypingMessage, onTypingFinished: onTypingFinished)
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
