//
//  OnboardingBubbleView.swift
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

public struct OnboardingBubbleView<Content: View>: View {
    @Environment(\.onboardingTheme) private var onboardingTheme

    private let tailPosition: TailPosition?
    private let contentInsets: EdgeInsets?
    private let arrowLength: CGFloat?
    private let arrowWidth: CGFloat?
    private let content: () -> Content

    public init(
        tailPosition: TailPosition?,
        contentInsets: EdgeInsets? = nil,
        arrowLength: CGFloat? = nil,
        arrowWidth: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tailPosition = tailPosition
        self.contentInsets = contentInsets
        self.arrowLength = arrowLength
        self.arrowWidth = arrowWidth
        self.content = content
    }

    public var body: some View {
        let tail = TailConfig(position: tailPosition)
        BubbleView(
            arrowLength: arrowLength ?? tail.arrowLength,
            arrowWidth: arrowWidth ?? tail.arrowWidth,
            arrowEdge: tail.arrowEdge,
            arrowOffset: tail.arrowOffset,
            cornerRadius: onboardingTheme.bubbleMetrics.cornerRadius,
            bend: tail.arrowBend,
            finSideCurve: tail.finSideCurve,
            finTipRadius: .greatestFiniteMagnitude,
            finTipRoundness: tail.finTipRoundness,
            fillColor: onboardingTheme.colorPalette.bubbleBackground,
            borderColor: onboardingTheme.colorPalette.bubbleBorder,
            borderWidth: onboardingTheme.bubbleMetrics.borderWidth,
            contentPadding: contentInsets ?? onboardingTheme.bubbleMetrics.contentInsets,
            content: content
        )
        .applyOnboardingShadow()
    }
}

// MARK: OnboardingBubble Factory

public extension OnboardingBubbleView {

    #if os(iOS)
    static func withStepProgressIndicator(
        tailPosition: TailPosition,
        currentStep: Int,
        totalSteps: Int,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        _LinearBubbleWrapper(tailPosition: tailPosition, content: content)
            .onboardingStepProgress(currentStep: currentStep, totalSteps: totalSteps)
    }
    #endif

    static func withDismissButton(
        tailPosition: TailPosition?,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        OnboardingBubbleView(tailPosition: tailPosition, content: content)
            .onboardingDismissable(onDismiss)
    }

}

// MARK: - Linear Bubble Wrapper

#if os(iOS)
/// Internal wrapper that reads the theme to pass linear bubble metrics.
private struct _LinearBubbleWrapper<Content: View>: View {
    @Environment(\.onboardingTheme) private var onboardingTheme

    let tailPosition: OnboardingBubbleView<Content>.TailPosition
    let content: () -> Content

    var body: some View {
        let metrics = onboardingTheme.linearBubbleMetrics
        OnboardingBubbleView(
            tailPosition: tailPosition,
            contentInsets: metrics.contentInsets,
            arrowLength: metrics.arrowLength,
            arrowWidth: metrics.arrowWidth,
            content: content
        )
    }
}
#endif

// MARK: - OnboardingBubble + Tail Helpers

public extension OnboardingBubbleView {

    /// Specifies the position of the bubble's tail (arrow).
    enum TailPosition: Equatable {
        /// Tail on the top edge.
        /// - Parameters:
        ///   - offset: Position along the edge (0.0 = left, 0.5 = center, 1.0 = right)
        ///   - direction: Arrow bend direction
        case top(offset: CGFloat = 0.5, direction: HorizontalTailDirection = .leading)

        /// Tail on the bottom edge.
        /// - Parameters:
        ///   - offset: Position along the edge (0.0 = left, 0.5 = center, 1.0 = right)
        ///   - direction: Arrow bend direction
        case bottom(offset: CGFloat = 0.5, direction: HorizontalTailDirection = .leading)

        /// Tail on the leading (left) edge.
        /// - Parameters:
        ///   - offset: Position along the edge (0.0 = top, 0.5 = center, 1.0 = bottom)
        ///   - direction: Arrow bend direction
        case leading(offset: CGFloat = 0.5, direction: VerticalTailDirection = .top)

        /// Tail on the trailing (right) edge.
        /// - Parameters:
        ///   - offset: Position along the edge (0.0 = top, 0.5 = center, 1.0 = bottom)
        ///   - direction: Arrow bend direction
        case trailing(offset: CGFloat = 0.5, direction: VerticalTailDirection = .top)

        var offset: CGFloat {
            switch self {
            case let .top(offset, _):
                return offset
            case let .leading(offset, _):
                return offset
            case let .trailing(offset, _):
                return offset
            case let .bottom(offset, _):
                return offset
            }
        }
    }

    enum HorizontalTailDirection: Equatable {
        case leading
        case trailing
    }

    enum VerticalTailDirection: Equatable {
        case top
        case bottom
    }

}

extension OnboardingBubbleView {

    struct TailConfig: Equatable {
        let arrowLength: CGFloat
        let arrowWidth: CGFloat
        let finSideCurve: CGFloat
        let finTipRoundness: CGFloat
        let arrowBend: CGFloat
        let arrowEdge: BubbleArrowEdge
        let arrowOffset: CGFloat

        init(position: TailPosition?) {
            switch position {
            case .none:
                self.arrowLength = 0
                self.arrowWidth = 0
                self.finSideCurve = 0
                self.finTipRoundness = 0
                self.arrowBend = 0
                self.arrowEdge = .top
                self.arrowOffset = 0.0
            case let .some(position):
                self.arrowLength = 25
                self.arrowWidth = 18
                self.finSideCurve = 0.4
                self.finTipRoundness = 0.3
                self.arrowBend = position.arrowBend
                self.arrowEdge = position.arrowEdge
                self.arrowOffset = position.offset
            }
        }
    }

}

private extension OnboardingBubbleView.TailPosition {

    var arrowBend: CGFloat {
        switch self {
        case .top(_, .leading),
                .bottom(_, .trailing),
                .leading(_, .bottom),
                .trailing(_, .top):
            return -1.5
        case .top(_, .trailing),
                .bottom(_, .leading),
                .trailing(_, .bottom),
                .leading(_, .top):
            return 1.5

        }
    }

    var arrowEdge: BubbleArrowEdge {
        switch self {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .left
        case .trailing: return .right
        }
    }

}

// MARK: - Preview

#if os(iOS) && DEBUG
private struct OnboardingBubblePreviewContent: View {
    @Environment(\.onboardingTheme) private var onboardingTheme

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            VStack(alignment: .center, spacing: 28) {
                Text(verbatim: "Hi there.")
                    .font(onboardingTheme.typography.title)
                    .multilineTextAlignment(onboardingTheme.linearTitleTextAlignment)

                Text(verbatim: "Ready for a better, more private internet?")
                    .font(onboardingTheme.typography.body)
                    .multilineTextAlignment(onboardingTheme.linearBodyTextAlignment)
            }
            .foregroundColor(onboardingTheme.colorPalette.textPrimary)

            Button(action: { }) {
                Text(verbatim: "Let's do it!")
            }
            .buttonStyle(onboardingTheme.primaryButtonStyle.style)
        }
    }
}

#Preview("Onboarding Speech Bubble - Light") {
    ZStack {
        Color.white.ignoresSafeArea()

        OnboardingBubbleView(tailPosition: .bottom(offset: 0.4, direction: .leading)) {
            OnboardingBubblePreviewContent()
        }
        .padding()
        .applyOnboardingTheme(.rebranding2026, stepProgressTheme: .rebranding2026)
    }
    .preferredColorScheme(.light)
}

#Preview("Onboarding Speech Bubble - Dark") {
    ZStack {
        Color(red: 43/255, green: 85/255, blue: 202/255).ignoresSafeArea()

        OnboardingBubbleView(tailPosition: .bottom(offset: 0.4, direction: .leading)) {
            OnboardingBubblePreviewContent()
        }
        .padding()
        .applyOnboardingTheme(.rebranding2026, stepProgressTheme: .rebranding2026)
    }
    .preferredColorScheme(.dark)
}

#Preview("Onboarding Speech Bubble + Progress Indicator - Light") {
    ZStack {
        Color.white.ignoresSafeArea()

        OnboardingBubbleView.withStepProgressIndicator(
            tailPosition: .bottom(offset: 0, direction: .leading),
            currentStep: 1, totalSteps: 5,
        ) {
            OnboardingBubblePreviewContent()
        }
        .padding()
    }
    .preferredColorScheme(.light)
}

#Preview("Onboarding Speech Bubble + Progress Indicator - Dark") {
    ZStack {
        Color(red: 43/255, green: 85/255, blue: 202/255).ignoresSafeArea()

        OnboardingBubbleView.withStepProgressIndicator(
            tailPosition: .bottom(offset: 0, direction: .leading),
            currentStep: 1, totalSteps: 5,
        ) {
            OnboardingBubblePreviewContent()
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Onboarding Speech Bubble + Dismiss Button - Light") {
    ZStack {
        Color.white.ignoresSafeArea()

        OnboardingBubbleView.withDismissButton(
            tailPosition: .bottom(offset: 0, direction: .leading),
            onDismiss: {}
        ) {
            OnboardingBubblePreviewContent()
        }
        .padding()
    }
    .preferredColorScheme(.light)
}

#Preview("Onboarding Speech Bubble + Dismiss Button - Dark") {
    ZStack {
        Color(red: 43/255, green: 85/255, blue: 202/255).ignoresSafeArea()

        OnboardingBubbleView.withDismissButton(
            tailPosition: .bottom(offset: 0, direction: .leading),
            onDismiss: {}
        ) {
            OnboardingBubblePreviewContent()
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Onboarding Speech Bubble - No Tail - Light") {
    ZStack {
        Color.white.ignoresSafeArea()

        OnboardingBubbleView(tailPosition: nil) {
            OnboardingBubblePreviewContent()
        }
        .padding()
    }
    .preferredColorScheme(.light)
}

#Preview("Onboarding Speech Bubble - No Tail - Dark") {
    ZStack {
        Color(red: 43/255, green: 85/255, blue: 202/255).ignoresSafeArea()

        OnboardingBubbleView(tailPosition: nil) {
            OnboardingBubblePreviewContent()
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
#endif
