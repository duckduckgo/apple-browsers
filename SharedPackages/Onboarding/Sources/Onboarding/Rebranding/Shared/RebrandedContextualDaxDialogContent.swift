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

extension OnboardingRebranding {

    public enum ContextualDaxDialogOrientation: Equatable {
        case verticalStack
        case horizontalStack(alignment: VerticalAlignment)
    }

    public struct ContextualDaxDialogContent<Content: View>: View {
        @Environment(\.onboardingTheme.contextualOnboardingMetrics) private var theme

        private let orientation: ContextualDaxDialogOrientation
        #if os(iOS)
        private let title: AttributedString?
        private let message: AttributedString
        #else
        private let title: NSAttributedString?
        private let message: NSAttributedString
        #endif

        private let titleTextAlignment: TextAlignment?
        private let messageTextAlignment: TextAlignment?
        private let content: Content

        @State private var shouldShowContent = false

        #if os(iOS)
        public init(
            orientation: ContextualDaxDialogOrientation = .verticalStack,
            title: AttributedString? = nil,
            titleTextAlignment: TextAlignment? = nil,
            message: AttributedString,
            messageTextAlignment: TextAlignment? = nil,
            @ViewBuilder content: () -> Content
        ) {
            self.orientation = orientation
            self.title = title
            self.titleTextAlignment = titleTextAlignment
            self.message = message
            self.messageTextAlignment = messageTextAlignment
            self.content = content()
        }

        public init(
            orientation: ContextualDaxDialogOrientation = .verticalStack,
            title: String? = nil,
            titleTextAlignment: TextAlignment? = nil,
            message: String,
            messageTextAlignment: TextAlignment? = nil,
            @ViewBuilder content: () -> Content
        ) {
            self.init(
                orientation: orientation,
                title: title.flatMap(AttributedString.init),
                titleTextAlignment: titleTextAlignment,
                message: AttributedString(message),
                messageTextAlignment: messageTextAlignment,
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
            @ViewBuilder content: () -> Content
        ) {
            self.orientation = orientation
            self.title = title
            self.titleTextAlignment = titleTextAlignment
            self.message = message
            self.messageTextAlignment = messageTextAlignment
            self.content = content()
        }
        #endif

        public var body: some View {
            Group {
                switch orientation {
                case .verticalStack:
                    VStack(alignment: .leading, spacing: theme.contentSpacing) {
                        TitleMessageStack(title: title, message: message, titleBodyVerticalSpacing: theme.titleBodyVerticalSpacingVerticalLayout, titleTextAlignment: titleTextAlignment, messageTextAlignment: messageTextAlignment)
                        content
                    }
                case let .horizontalStack(alignment):
                    HStack(alignment: alignment) {
                        TitleMessageStack(title: title, message: message, titleBodyVerticalSpacing: theme.titleBodyVerticalSpacingHorizontalLayout, titleTextAlignment: titleTextAlignment, messageTextAlignment: messageTextAlignment)
                        Spacer(minLength: theme.contentSpacing)
                        content
                    }
                }
            }
            .opacity(shouldShowContent ? 1 : 0)
            .onAppear {
                Task { @MainActor in
                    try await Task.sleep(interval: theme.contentFadeInDelay)
                    withAnimation(.easeIn(duration: theme.contentFadeInDuration)) {
                        shouldShowContent = true
                    }
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
        message: AttributedString
    ) {
        self.init(orientation: orientation, title: title, message: message) {
            EmptyView()
        }
    }

    /// Convenience initializer for dialogs without additional content, accepting plain strings.
    public init(
        orientation: OnboardingRebranding.ContextualDaxDialogOrientation = .verticalStack,
        title: String? = nil,
        message: String
    ) {
        self.init(
            orientation: orientation,
            title: title.flatMap(AttributedString.init),
            message: AttributedString(message)
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
        message: NSAttributedString
    ) {
        self.init(orientation: orientation, title: title, message: message) {
            EmptyView()
        }
    }
}
#endif

// MARK: Inner Views

private extension OnboardingRebranding {

    struct TitleMessageStack: View {
        @Environment(\.onboardingTheme) private var theme

        #if os(iOS)
        let title: AttributedString?
        let message: AttributedString
        #else
        let title: NSAttributedString?
        let message: NSAttributedString
        #endif

        let titleBodyVerticalSpacing: CGFloat

        var titleTextAlignment: TextAlignment?
        var messageTextAlignment: TextAlignment?

        var body: some View {
            VStack(alignment: .leading, spacing: titleBodyVerticalSpacing) {
                if let title {
                    let titleAlignment = titleTextAlignment ?? theme.contextualOnboardingMetrics.contextualTitleTextAlignment
                    StyledAttributedText(title)
                        .font(theme.typography.contextual.title)
                        .multilineTextAlignment(titleAlignment)
                        .frame(maxWidth: .infinity, alignment: Alignment(titleAlignment))
                }
                let messageAlignment = messageTextAlignment ?? theme.contextualOnboardingMetrics.contextualBodyTextAlignment
                StyledAttributedText(message)
                    .font(theme.typography.contextual.body)
                    .multilineTextAlignment(messageAlignment)
                    .frame(maxWidth: .infinity, alignment: Alignment(messageAlignment))
            }
            .padding(theme.contextualOnboardingMetrics.titleBodyInset)

        }
    }

}

// MARK: - Helpers

#if os(iOS)
private struct StyledAttributedText: View {
    private let attributedString: AttributedString

    init(_ attributedString: AttributedString) {
        self.attributedString = attributedString
    }

    var body: some View {
        Text(attributedString)
    }
}
#endif

#if os(macOS)
private struct StyledAttributedText: View {
    private let attributedString: NSAttributedString

    init(_ attributedString: NSAttributedString) {
        self.attributedString = attributedString
    }

    var body: some View {
        if #available(macOS 12, *) {
            Text(AttributedString(attributedString))
        } else {
            Text(attributedString.string)
        }
    }
}
#endif

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
