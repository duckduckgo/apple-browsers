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
    // Replace values with @Environment(\.onboardingTheme) var onboardingTheme
    let cornerRadius: CGFloat = 36.0

    private let tailPosition: TailPosition?
    private let content: () -> Content

    public init(
        tailPosition: TailPosition?,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tailPosition = tailPosition
        self.content = content
    }

    public var body: some View {
        let tail = TailConfig(position: tailPosition)
        BubbleView(
            arrowLength: tail.arrowLength,
            arrowWidth: tail.arrowWidth,
            arrowEdge: tail.arrowEdge,
            arrowOffset: tail.arrowOffset,
            cornerRadius: cornerRadius,
            bend: tail.arrowBend,
            finSideCurve: tail.finSideCurve,
            finTipRadius: .greatestFiniteMagnitude,
            finTipRoundness: tail.finTipRoundness,
            fillColor: Color(red: 1/255, green: 29/255, blue: 52/255),
            borderColor: Color(red: 19/255, green: 62/255, blue: 124/255),
            borderWidth: 1.5,
            contentPadding: EdgeInsets(top: 32, leading: 20, bottom: 20, trailing: 20),
            content: content
        )
        .shadow(
            color: .black.opacity(0.3),
            radius: 6,
            x: 0, y: 7
        )
    }
}

// MARK: OnboardingBubble Factory

public extension OnboardingBubbleView {

    static func withStepProgressIndicator(
        tailPosition: TailPosition,
        currentStep: Int,
        totalSteps: Int,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        OnboardingBubbleView(tailPosition: tailPosition, content: content)
            .onboardingStepProgress(currentStep: currentStep, totalSteps: totalSteps)
    }

    static func withDismissButton(
        tailPosition: TailPosition?,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        OnboardingBubbleView(tailPosition: tailPosition, content: content)
            .onboardingDismissable(onDismiss)
    }

}

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

#Preview("Onboarding Speech Bubble") {
    ZStack {
        Color(red: 43/255, green: 85/255, blue: 202/255).ignoresSafeArea()

        OnboardingBubbleView(tailPosition: .bottom(offset: 0.4, direction: .leading)) {
            VStack(alignment: .center, spacing: 20) {
                VStack(alignment: .center, spacing: 28) {
                    Text(verbatim: "Hi there.")
                        .font(.system(size: 24, weight: .bold))

                    Text(verbatim: "Ready for a better, more private internet?")
                        .font(.system(size: 18))
                }
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)

                Button(action: { }) {
                    Text(verbatim: "Let's do it!")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.black)
                        .padding()
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: 44.0)
                .background(Color(red: 255/255, green: 216/255, blue: 133/255))
                .cornerRadius(64)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Onboarding Speech Bubble + Progress Indicator") {
    ZStack {
        Color(red: 43/255, green: 85/255, blue: 202/255).ignoresSafeArea()

        OnboardingBubbleView.withStepProgressIndicator(
            tailPosition: .bottom(offset: 0, direction: .leading),
            currentStep: 1, totalSteps: 5
        ) {
                VStack(alignment: .center, spacing: 20) {
                    VStack(alignment: .center, spacing: 28) {
                        Text(verbatim: "Hi there.")
                            .font(.system(size: 24, weight: .bold))

                        Text(verbatim: "Ready for a better, more private internet?")
                            .font(.system(size: 18))
                    }
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)

                    Button(action: { }) {
                        Text(verbatim: "Let's do it!")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.black)
                            .padding()
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: 44.0)
                    .background(Color(red: 255/255, green: 216/255, blue: 133/255))
                    .cornerRadius(64)
                }
            }
            .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Onboarding Speech Bubble + Dismiss Button") {
    ZStack {
        Color(red: 43/255, green: 85/255, blue: 202/255).ignoresSafeArea()

        OnboardingBubbleView.withDismissButton(
            tailPosition: .bottom(offset: 0, direction: .leading),
            onDismiss: {}
        ) {
            VStack(alignment: .center, spacing: 20) {
                VStack(alignment: .center, spacing: 28) {
                    Text(verbatim: "Hi there.")
                        .font(.system(size: 24, weight: .bold))

                    Text(verbatim: "Ready for a better, more private internet?")
                        .font(.system(size: 18))
                }
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)

                Button(action: { }) {
                    Text(verbatim: "Let's do it!")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.black)
                        .padding()
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: 44.0)
                .background(Color(red: 255/255, green: 216/255, blue: 133/255))
                .cornerRadius(64)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Onboarding Speech Bubble No Tail") {
    ZStack {
        Color(red: 43/255, green: 85/255, blue: 202/255).ignoresSafeArea()

        OnboardingBubbleView(tailPosition: nil) {
            VStack(alignment: .center, spacing: 20) {
                VStack(alignment: .center, spacing: 28) {
                    Text(verbatim: "Hi there.")
                        .font(.system(size: 24, weight: .bold))

                    Text(verbatim: "Ready for a better, more private internet?")
                        .font(.system(size: 18))
                }
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)

                Button(action: { }) {
                    Text(verbatim: "Let's do it!")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.black)
                        .padding()
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: 44.0)
                .background(Color(red: 255/255, green: 216/255, blue: 133/255))
                .cornerRadius(64)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
