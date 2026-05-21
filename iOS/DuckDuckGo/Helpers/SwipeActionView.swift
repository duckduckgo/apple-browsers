//
//  SwipeActionView.swift
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
import Common

private final class SwipeActionViewState: ObservableObject {
    let haptics = UIImpactFeedbackGenerator(style: .light)
    let enclosingTouchHandle = ExclusiveTouchHandle()
}

private enum SwipeState {
    case idle
    case dragging(thresholdCrossed: Bool)
    case pendingCommit
}

struct SwipeActionView<Content: View, Actions: View>: View {
    @StateObject private var state = SwipeActionViewState()
    @Environment(\.layoutDirection) private var layoutDirection

    @State private var contentOffset: CGFloat = 0
    @State private var swipeState: SwipeState = .idle

    let content: Content
    let actions: Actions
    let configuration: SwipeActionViewConfiguration
    let onCommit: () -> Void

    init(
        configuration: SwipeActionViewConfiguration = .default,
        onCommit: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) {
        self.configuration = configuration
        self.onCommit = onCommit
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width

            ZStack(alignment: actionsAlignment) {
                content
                    .offset(x: contentOffset)
                    .frame(maxWidth: .infinity)

                actions
                    .frame(width: actionsWidth(in: availableWidth))
                    .clipShape(Capsule())
                    .opacity(progress(in: availableWidth))
            }
            .animation(
                .spring(response: configuration.springResponse, dampingFraction: configuration.springDamping),
                value: contentOffset
            )
            .background(
                ExclusiveTouchView(handle: state.enclosingTouchHandle)
            )
            .highPriorityGesture(
                dragGesture(in: availableWidth)
            )
            .onAppear {
                state.haptics.prepare()
            }
        }
        .clipped()
    }
}

// MARK: - Calculated Properties

private extension SwipeActionView {

    /// Trailing while the user is dragging so actions emerge from the trailing edge.
    /// Flips to leading on commit so the post-commit spring fills the row from the leading edge rather than chasing the exit.
    var actionsAlignment: Alignment {
        if case .pendingCommit = swipeState {
            return .leading
        }

        return isRTL ? .leading : .trailing
    }

    var isRTL: Bool {
        layoutDirection == .rightToLeft
    }
}

// MARK: - Recognizer

private extension SwipeActionView {

    func dragGesture(in availableWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: configuration.minimumDragDistance)
            .onChanged { recognizer in
                beginDraggingIfNeeded()

                guard case .dragging = swipeState else {
                    return
                }

                processDragChanged(in: availableWidth, dragOffset: recognizer.translation.width)
            }
            .onEnded { _ in
                guard case .dragging = swipeState else {
                    return
                }

                processDragEnded(in: availableWidth)
            }
    }

    func beginDraggingIfNeeded() {
        guard case .idle = swipeState else {
            return
        }
        state.enclosingTouchHandle.cancel()
        swipeState = .dragging(thresholdCrossed: false)
    }

    /// Only accept drags toward the trailing edge: leftward (negative) in LTR, rightward (positive) in RTL.
    /// SwiftUI mirrors `.trailing` to the physical left in RTL, so the reveal direction flips with `layoutDirection`.
    func processDragChanged(in availableWidth: CGFloat, dragOffset: CGFloat) {
        contentOffset = isRTL ? max(dragOffset, 0) : min(dragOffset, 0)
        performHapticsIfNeeded(in: availableWidth)
    }

    func processDragEnded(in availableWidth: CGFloat) {
        guard isPastCommit(in: availableWidth) else {
            contentOffset = .zero
            swipeState = .idle
            return
        }

        let directionalMultiplier: CGFloat = isRTL ? 1 : -1
        contentOffset = availableWidth * directionalMultiplier
        commit()
    }
}

// MARK: - Helpers

private extension SwipeActionView {

    /// Opacity ramp tied to the commit point: reaches 1 at the trigger distance so the post-release spring doesn't also have to animate alpha.
    /// Starts counting after `spacing` so the alpha ramp aligns with the width ramp (which is also offset by `spacing`).
    ///
    func progress(in availableWidth: CGFloat) -> CGFloat {
        if case .pendingCommit = swipeState {
            return 1
        }

        let commitDistance = availableWidth * configuration.threshold
        guard commitDistance > 0 else {
            return 0
        }

        let progress = actionsWidth(in: availableWidth) / commitDistance
        return progress.clamped(to: 0...1)
    }

    func isPastCommit(in availableWidth: CGFloat) -> Bool {
        progress(in: availableWidth) >= 1
    }

    func actionsWidth(in availableWidth: CGFloat) -> CGFloat {
        let width = abs(contentOffset) - configuration.spacing
        return width.clamped(to: 0...availableWidth)
    }
}

// MARK: - Haptics

private extension SwipeActionView {

    func performHapticsIfNeeded(in availableWidth: CGFloat) {
        guard case .dragging(let thresholdCrossed) = swipeState else {
            return
        }

        let pastCommit = isPastCommit(in: availableWidth)
        guard pastCommit != thresholdCrossed else {
            return
        }

        state.haptics.impactOccurred()
        state.haptics.prepare()
        swipeState = .dragging(thresholdCrossed: pastCommit)
    }

    func commit() {
        swipeState = .pendingCommit

        DispatchQueue.main.asyncAfter(deadline: .now() + configuration.commitDelay) {
            onCommit()
        }
    }
}

struct SwipeActionViewConfiguration {
    let threshold: CGFloat
    let spacing: CGFloat
    let commitDelay: TimeInterval
    let minimumDragDistance: CGFloat
    let springResponse: Double
    let springDamping: Double

    static let `default` = SwipeActionViewConfiguration(
        threshold: 0.4, spacing: 4, commitDelay: 0.2, minimumDragDistance: 10, springResponse: 0.3, springDamping: 0.8
    )
}
