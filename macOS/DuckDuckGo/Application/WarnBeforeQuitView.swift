//
//  WarnBeforeQuitView.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import AppKit
import SwiftUI
import DesignResourcesKit

/// SwiftUI view for the "Warn Before Quit/Close" confirmation overlay.
/// Displays a balloon notification with animated progress indicator for quit/close pinned tab actions.
/// Supports two variants: centered (quit) and tab-anchored with arrow (close tab).
struct WarnBeforeQuitView: View {

    // MARK: - Layout Constants

    enum Constants {
        static let shadowPadding: CGFloat = 120  // 60px padding on each side
        static let arrowHeight: CGFloat = 7
        static let arrowWidth: CGFloat = 16
        static let arrowOffset: CGFloat = 40  // From left edge
        static let tabGapOffset: CGFloat = 8  // Gap between notification and tab
        static let quitPanelTopOffset: CGFloat = -4  // Distance from top of window for quit panel
        // Spacing between elements (circle -> text, text -> button area)
        static var circleToTextSpacing: CGFloat = 16
        static var textToButtonSpacing: CGFloat = 40

        // Animation constants
        static let animationYOffset: CGFloat = 12  // Vertical offset for enter/exit animation
        static let animationScale: CGFloat = 0.96  // Scale for enter/exit animation
        static let animationResponse: Double = 0.28  // Spring response time (converted from stiffness 500, damping 40)
        static let animationDampingFraction: Double = 0.89  // Spring damping (converted from stiffness 500, damping 40)
        static let animationSettlingTime: Double = 0.35  // Time to wait for animation to complete before cleanup
    }

    @ObservedObject var viewModel: WarnBeforeQuitViewModel
    @State private var isButtonHovered = false
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    // Animation properties
    @State private var balloonOpacity: Double = 0
    @State private var balloonYOffset: CGFloat = Constants.animationYOffset
    @State private var balloonScale: CGFloat = Constants.animationScale

    private var backgroundColor: Color {
        colorScheme == .dark ?
            Color(designSystemColor: .surfaceBackdrop) :
            Color(designSystemColor: .surfaceTertiary)
    }

    // Sizing for close action (compact variant)
    private var isCloseAction: Bool { viewModel.action == .close }
    private var progressSize: CGFloat { isCloseAction ? 50 : 55 }
    private var circleSize: CGFloat { isCloseAction ? 46 : 52 }
    private var shortcutFontSize: CGFloat { isCloseAction ? 13 : 15 }
    private var titleFontSize: CGFloat { isCloseAction ? 15 : 17 }
    private var buttonPaddingH: CGFloat { isCloseAction ? 14 : 16 }
    private var buttonPaddingV: CGFloat { isCloseAction ? 8 : 9 }
    private var buttonFontSize: CGFloat { 13 }
    private var contentHeight: CGFloat { isCloseAction ? 86 : 100 }
    private var contentWidth: CGFloat { isCloseAction ? 400 : 450 }
    // Padding from edges
    private var horizontalPadding: CGFloat { isCloseAction ? 24 : 32 }
    private var verticalPadding: CGFloat { 24 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            if isCloseAction {
                // Close action: position relative to tab anchor
                balloonContent
                    .fixedSize()
                    .offset(x: calculateCloseOffset().x, y: calculateCloseOffset().y)
            } else {
                // Quit action: position at top center
                HStack {
                    Spacer()
                    balloonContent
                        .fixedSize()
                    Spacer()
                }
                .offset(y: Constants.quitPanelTopOffset)
            }
        }
    }

    private var balloonContent: some View {
        ZStack(alignment: .topLeading) {
            HStack {
                mainContent
                Spacer(minLength: 0)
            }
            .offset(y: isCloseAction ? Constants.arrowHeight : 0)

            // Arrow pointing up for close pinned tab action
            if viewModel.action == .close {
                Triangle()
                    .fill(backgroundColor)
                    .frame(width: Constants.arrowWidth, height: Constants.arrowHeight)
                    .offset(x: Constants.arrowOffset, y: 0)
            }
        }
        .shadow(color: Color(designSystemColor: .shadowPrimary), radius: 40, x: 0, y: 20)
        .shadow(color: Color(designSystemColor: .shadowSecondary), radius: 12, x: 0, y: 4)
        .padding(Constants.shadowPadding / 2)
        .opacity(balloonOpacity)
        .offset(y: balloonYOffset)
        .scaleEffect(balloonScale)
        .onAppear {
            animateIn()
        }
        .onChange(of: viewModel.shouldHide) { shouldHide in
            if shouldHide {
                animateOut()
            } else {
                animateIn()
            }
        }
    }

    private func calculateCloseOffset() -> CGPoint {
        let anchorPosition = viewModel.balloonAnchorPosition
        let shadowPadding = Constants.shadowPadding / 2
        let arrowOffset = Constants.arrowOffset
        let halfArrowWidth = Constants.arrowWidth / 2
        let tabGapOffset = Constants.tabGapOffset

        // anchorPosition.y is the distance from window top to tab bottom (SwiftUI coordinates)
        // We want the arrow tip (top of arrow, pointing up) to be at: anchorPosition.y + tabGapOffset
        // The view structure: shadowPadding -> arrow at y=0 (tip at top) -> main content offset down
        // So: viewTop + shadowPadding = anchorPosition.y + tabGapOffset
        // Therefore: viewTop = anchorPosition.y + tabGapOffset - shadowPadding
        let x = anchorPosition.x - arrowOffset - halfArrowWidth - shadowPadding
        let y = anchorPosition.y + tabGapOffset - shadowPadding

        return CGPoint(x: x, y: y)
    }

    // MARK: - Animation

    /// Animates the balloon entering with spring animation.
    /// Spring parameters: stiffness 500, damping 40
    /// Converted to SwiftUI: response ≈ 0.28, dampingFraction ≈ 0.89
    private func animateIn() {
        var response = Constants.animationResponse
#if DEBUG
        response *= AnimatedCircleProgress.slowMotionMultiplier
#endif
        withAnimation(.spring(response: response, dampingFraction: Constants.animationDampingFraction, blendDuration: 0)) {
            balloonOpacity = 1.0
            balloonYOffset = 0
            balloonScale = 1.0
        }
    }

    /// Animates the balloon exiting with spring animation.
    /// Spring parameters: stiffness 500, damping 40
    /// Converted to SwiftUI: response ≈ 0.28, dampingFraction ≈ 0.89
    private func animateOut() {
        var response = Constants.animationResponse
#if DEBUG
        response *= AnimatedCircleProgress.slowMotionMultiplier
#endif
        withAnimation(.spring(response: response, dampingFraction: Constants.animationDampingFraction, blendDuration: 0)) {
            balloonOpacity = 0
            balloonYOffset = Constants.animationYOffset
            balloonScale = Constants.animationScale
        }
    }

    private var mainContent: some View {
        HStack(spacing: 0) {
            // Circular progress indicator
            ZStack {
                // Progress arc with enhanced glow - drawn FIRST (bottom layer)
                AnimatedCircleProgress(
                    progressState: viewModel.progressState,
                    lineWidth: 3,
                    strokeColor: Color(designSystemColor: .accentPrimary)
                )
                .frame(width: progressSize, height: progressSize)
                .rotationEffect(.degrees(-90))
                .shadow(color: Color(designSystemColor: .accentPrimary).opacity(0.8), radius: 2, x: 0, y: 0)
                .shadow(color: Color(designSystemColor: .accentPrimary).opacity(0.5), radius: 6, x: 0, y: 0)
                .shadow(color: Color(designSystemColor: .accentPrimary).opacity(0.3), radius: 12, x: 0, y: 0)

                // Background layer - masks the shadow
                Circle()
                    .fill(backgroundColor)
                    .frame(width: circleSize, height: circleSize)

                // Background circle - drawn THIRD (on top of mask)
                Circle()
                    .fill(Color(designSystemColor: .controlsFillPrimary))
                    .frame(width: circleSize, height: circleSize)

                // Shortcut text - drawn LAST (on top)
                Text(verbatim: viewModel.action.shortcutText)
                    .font(.system(size: shortcutFontSize, weight: .semibold))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
            }
            .padding(.trailing, Constants.circleToTextSpacing)

            // Text content
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.action.actionText)
                    .font(.system(size: titleFontSize, weight: .bold))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: true, vertical: false)

                if let subtitle = viewModel.subtitleText {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.trailing, Constants.textToButtonSpacing)

            // "Don‘t Show Again" button
            Text(UserText.confirmDontShowAgain)
                .font(.system(size: buttonFontSize, weight: .regular))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .padding(.horizontal, buttonPaddingH)
                .padding(.vertical, buttonPaddingV)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isButtonHovered ?
                                Color(designSystemColor: .controlsFillSecondary) :
                                Color(designSystemColor: .controlsFillPrimary))
                )
                .fixedSize()
                .animation(.easeInOut(duration: 0.15), value: isButtonHovered)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isButtonHovered = hovering
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                // Handle mouse-down event on the "Don‘t Show Again" button
                // apply conditionally only if the mouse is hovering over the view when `window.ignoresMouseEvents` is false,
                // otherwise, the gesture recognizer breaks.
                .conditionalGesture(isHovering: isHovering) {
                    viewModel.dontAskAgainTapped()
                }
        }
        .padding(.trailing, horizontalPadding)
        .padding(.leading, horizontalPadding - 2) // Circle has own padding of 2px
        .padding(.vertical, verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(backgroundColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
            viewModel.hoverChanged(hovering)
        }
    }
}

// MARK: - Conditional Gesture Modifier

/// A view modifier that conditionally applies a gesture only when hovering.
/// This works in conjunction with `window.ignoresMouseEvents` to allow click-through when not hovering.
/// DragGesture with minimumDistance: 0 fires on mouse down, ensuring the callback executes before
/// the event monitor's async resume in WarnBeforeQuitManager.
struct ConditionalGestureModifier: ViewModifier {
    let isHovering: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if isHovering {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        action()
                    }
            )
        } else {
            content
        }
    }
}

extension View {
    func conditionalGesture(isHovering: Bool, action: @escaping () -> Void) -> some View {
        modifier(ConditionalGestureModifier(isHovering: isHovering, action: action))
    }
}

// MARK: - Animated Progress Circle

/// A view that displays an animated circular progress indicator.
/// Handles its own animations internally based on ProgressState changes.
/// Uses a custom TrimmedCircle shape to animate only the trim path, preventing layout shifts.
struct AnimatedCircleProgress: View {
    let progressState: ProgressState
    let lineWidth: CGFloat
    let strokeColor: Color
#if DEBUG
    static var slowMotionMultiplier: Double = 1
#endif

    @State private var displayProgress: CGFloat = 0

    var body: some View {
        TrimmedCircle(progress: displayProgress)
            .stroke(strokeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .onChange(of: progressState) { newState in
                switch newState {
                case .idle:
                    displayProgress = 0

                case .animating(var duration, let targetValue):
#if DEBUG
                    duration *= Self.slowMotionMultiplier
#endif
                    // Animate to 100% with linear animation
                    withAnimation(.linear(duration: duration)) {
                        displayProgress = targetValue
                    }

                case .complete:
                    // Snap to 100% immediately
                    displayProgress = 1.0

                case .resetting:
                    // Animate back to 0 with spring
                    var response = 0.3
#if DEBUG
                    response *= Self.slowMotionMultiplier
#endif
                    withAnimation(.spring(response: response, dampingFraction: 0.7)) {
                        displayProgress = 0
                    }
                }
            }
            .onAppear {
                displayProgress = progressState.targetProgress
            }
    }
}

/// Custom animatable shape for a trimmed circle arc.
/// Animates only the trim path (arc length), not layout, preventing unwanted view shifts.
/// Clamps progress to prevent spring overshoot artifacts from rendering sub-pixel values.
struct TrimmedCircle: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Clamp to prevent spring overshoot from rendering sub-pixel artifacts
        // Springs oscillate and can produce tiny values (0.001) that still render at the end of the animation
        let clamped = max(0, min(progress, 1))
        let safeProgress = clamped < 0.002 ? 0 : clamped

        return Circle()
            .trim(from: 0, to: safeProgress)
            .path(in: rect)
    }
}

/// Triangle shape pointing up
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#if DEBUG

// MARK: - Preview Helpers

/// Mock persistor for previews
final class PreviewStartupPreferencesPersistor: StartupPreferencesPersistor {
    var customHomePageURL: String = ""
    var restorePreviousSession: Bool = false
    var launchToCustomHomePage: Bool = false
    var startupWindowType: StartupWindowType = .window
    init(restorePreviousSession: Bool = true) {
        self.restorePreviousSession = restorePreviousSession
    }
}

/// Helper to create StartupPreferences for previews
func makePreviewStartupPreferences(restorePreviousSession: Bool) -> StartupPreferences {
    StartupPreferences(
        persistor: PreviewStartupPreferencesPersistor(restorePreviousSession: restorePreviousSession),
        appearancePreferences: .mock
    )
}

/// Reusable color palette selector for previews
struct ColorPaletteSelector: View {
    @Binding var colorPalette: ColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "Color Theme:")
                .font(.headline)
            HStack(spacing: 6) {
                Button {
                    colorPalette = .default
                } label: {
                    Text(verbatim: colorPalette == .default ? "Default ✓" : "Default")
                }
                Button {
                    colorPalette = .green
                } label: {
                    Text(verbatim: colorPalette == .green ? "Green ✓" : "Green")
                }
                Button {
                    colorPalette = .rose
                } label: {
                    Text(verbatim: colorPalette == .rose ? "Rose ✓" : "Rose")
                }
                Button {
                    colorPalette = .coolGray
                } label: {
                    Text(verbatim: colorPalette == .coolGray ? "Cool Gray ✓" : "Cool Gray")
                }
            }
            HStack(spacing: 6) {
                Button {
                    colorPalette = .slateBlue
                } label: {
                    Text(verbatim: colorPalette == .slateBlue ? "Slate Blue ✓" : "Slate Blue")
                }
                Button {
                    colorPalette = .orange
                } label: {
                    Text(verbatim: colorPalette == .orange ? "Orange ✓" : "Orange")
                }
                Button {
                    colorPalette = .desert
                } label: {
                    Text(verbatim: colorPalette == .desert ? "Desert ✓" : "Desert")
                }
                Button {
                    colorPalette = .violet
                } label: {
                    Text(verbatim: colorPalette == .violet ? "Violet ✓" : "Violet")
                }
            }
        }
    }
}

/// Interactive preview container with color and progress controls
@available(macOS 14.0, *)
struct InteractivePreview: View {
    @Binding var colorPalette: ColorPalette
    let makeViewModel: (ColorPalette) -> WarnBeforeQuitViewModel

    @State private var slowMotion = false
    @State private var viewModel: WarnBeforeQuitViewModel?
    @State private var stateSwitchTask: Task<Void, Error>?

    var body: some View {
        VStack(spacing: 20) {
            if let viewModel = viewModel {
                WarnBeforeQuitView(viewModel: viewModel)
            }

            VStack(spacing: 12) {
                ColorPaletteSelector(colorPalette: $colorPalette)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "View Animations:")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Button {
                            guard let vm = viewModel else { return }
                            Task { @MainActor in
                                if !vm.shouldHide {
                                    // Toggle to force animation re-trigger
                                    vm.shouldHide = true
                                    try? await Task.sleep(interval: 0.3)
                                }
                                vm.shouldHide = false
                            }
                        } label: {
                            Text(verbatim: "Show")
                        }

                        Button {
                            guard let vm = viewModel else { return }
                            Task { @MainActor in
                                if vm.shouldHide {
                                    // Toggle to force animation re-trigger
                                    vm.shouldHide = false
                                    try? await Task.sleep(interval: 0.3)
                                }
                                vm.shouldHide = true
                            }
                        } label: {
                            Text(verbatim: "Hide")
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "Progress Animations:")
                        .font(.headline)

                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Button {
                                guard let vm = viewModel else { return }
                                // If not idle, force to idle first
                                if vm.progressState != .idle {
                                    vm.transitionToIdle()
                                }
                                stateSwitchTask?.cancel()
                                stateSwitchTask = Task {
                                    try await Task.sleep(interval: 0.05)
                                    let duration = 0.6
                                    vm.startProgress(duration: duration)
                                    // Wait for animation to complete, then transition to complete state
                                    try await Task.sleep(interval: duration)
                                    vm.completeProgress()
                                }
                            } label: {
                                Text(verbatim: "Start progress")
                            }

                            Button {
                                guard let vm = viewModel else { return }
                                // If not idle, force to idle first
                                if vm.progressState != .idle {
                                    vm.transitionToIdle()
                                }
                                stateSwitchTask?.cancel()
                                stateSwitchTask = Task {
                                    try await Task.sleep(interval: 0.05)
                                    vm.startProgress(duration: 0.3, targetValue: 0.2)
                                }
                            } label: {
                                Text(verbatim: "Progress: 20%")
                            }

                            Button {
                                guard let vm = viewModel else { return }
                                vm.resetProgress()
                                // Transition to idle after reset animation completes
                                stateSwitchTask?.cancel()
                                stateSwitchTask = Task {
                                    // Spring with response 0.3 and damping 0.7 settles in ~1 second
                                    try await Task.sleep(interval: 1.0)
                                    vm.transitionToIdle()
                                }
                            } label: {
                                Text(verbatim: "reset")
                            }
                        }
                    }

                    Toggle(isOn: $slowMotion) {
                        Text(verbatim: "Slow Motion (5x)")
                    }
                        .font(.caption)
                }

            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(40)
        .onAppear {
            DesignSystemPalette.current = colorPalette
            let vm = makeViewModel(colorPalette)
            // Center the close action balloon in the preview
            if vm.action == .close {
                // Position anchor to center the balloon body
                vm.balloonAnchorPosition = CGPoint(x: 120, y: 50)
            }
            viewModel = vm
            AnimatedCircleProgress.slowMotionMultiplier = slowMotion ? 5.0 : 1.0
        }
        .onChange(of: colorPalette) { newPalette in
            DesignSystemPalette.current = newPalette
            let vm = makeViewModel(newPalette)
            // Center the close action balloon in the preview
            if vm.action == .close {
                vm.balloonAnchorPosition = CGPoint(x: 120, y: 50)
            }
            viewModel = vm
            AnimatedCircleProgress.slowMotionMultiplier = slowMotion ? 5.0 : 1.0
        }
        .onChange(of: slowMotion) { newValue in
            AnimatedCircleProgress.slowMotionMultiplier = newValue ? 5.0 : 1.0
        }
    }

}

// MARK: - Previews

@available(macOS 14.0, *)
#Preview("Quit - With Subtitle") {
    @Previewable @State var colorPalette: ColorPalette = .default

    InteractivePreview(colorPalette: $colorPalette) { _ in
        WarnBeforeQuitViewModel(
            action: .quit,
            startupPreferences: makePreviewStartupPreferences(restorePreviousSession: true)
        )
    }
}

@available(macOS 14.0, *)
#Preview("Quit - No Subtitle") {
    @Previewable @State var colorPalette: ColorPalette = .default

    InteractivePreview(colorPalette: $colorPalette) { _ in
        WarnBeforeQuitViewModel(
            action: .quit,
            startupPreferences: makePreviewStartupPreferences(restorePreviousSession: false)
        )
    }
}

@available(macOS 14.0, *)
#Preview("Close Pinned Tab") {
    @Previewable @State var colorPalette: ColorPalette = .default

    InteractivePreview(colorPalette: $colorPalette) { _ in
        WarnBeforeQuitViewModel(action: .close, startupPreferences: nil)
    }
}

#endif
