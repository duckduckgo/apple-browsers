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

struct WarnBeforeQuitView: View {

    // MARK: - Layout Constants

    enum Constants {
        static let shadowPadding: CGFloat = 120  // 60px padding on each side
        static let arrowHeight: CGFloat = 7
        static let arrowWidth: CGFloat = 16
        static let arrowOffset: CGFloat = 40  // From left edge
        static let tabGapOffset: CGFloat = 4  // Gap between notification and tab (combined with internal spacing = 8px)
        static let quitPanelTopOffset: CGFloat = 56  // Distance from top of window for quit panel
    }

    /// Returns the content size for the notification based on action type
    static func contentSize(for action: ConfirmationAction) -> CGSize {
        action == .close ? CGSize(width: 480, height: 86) : CGSize(width: 550, height: 100)
    }

    /// Returns the full window size including arrow and shadow padding
    static func windowSize(for action: ConfirmationAction) -> CGSize {
        let content = contentSize(for: action)
        let height = content.height + (action == .close ? Constants.arrowHeight : 0)
        return CGSize(
            width: content.width + Constants.shadowPadding,
            height: height + Constants.shadowPadding
        )
    }

    @ObservedObject var viewModel: WarnBeforeQuitViewModel
    @State private var isButtonHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark ?
            Color(designSystemColor: .surfaceBackdrop) :
            Color(designSystemColor: .surfaceTertiary)
    }

    // Sizing for close action (compact variant)
    private var isCloseAction: Bool { viewModel.action == .close }
    private var progressSize: CGFloat { isCloseAction ? 50 : 58 }
    private var circleSize: CGFloat { isCloseAction ? 44 : 52 }
    private var shortcutFontSize: CGFloat { isCloseAction ? 13 : 15 }
    private var titleFontSize: CGFloat { isCloseAction ? 15 : 17 }
    private var buttonPaddingH: CGFloat { isCloseAction ? 14 : 16 }
    private var buttonPaddingV: CGFloat { isCloseAction ? 8 : 9 }
    private var buttonFontSize: CGFloat { 13 }
    private var spacing: CGFloat { isCloseAction ? 20 : 24 }
    private var windowSize: CGSize { isCloseAction ? CGSize(width: 480, height: 86) : CGSize(width: 550, height: 100) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            mainContent
                .offset(y: isCloseAction ? Constants.arrowHeight : 0)

            // Arrow pointing up for close pinned tab action
            if viewModel.action == .close {
                Triangle()
                    .fill(backgroundColor)
                    .frame(width: Constants.arrowWidth, height: Constants.arrowHeight)
                    .offset(x: Constants.arrowOffset, y: 0)
            }
        }
        .compositingGroup()
        .shadow(color: Color(designSystemColor: .shadowPrimary), radius: 40, x: 0, y: 20)
        .shadow(color: Color(designSystemColor: .shadowSecondary), radius: 12, x: 0, y: 4)
        .frame(width: windowSize.width, height: windowSize.height + (isCloseAction ? Constants.arrowHeight : 0))
        .padding(Constants.shadowPadding / 2)
        .clipped()
    }

    private var mainContent: some View {
        HStack(spacing: spacing) {
            // Circular progress indicator
            ZStack {
                // Progress arc with enhanced glow - drawn FIRST (bottom layer)
                Circle()
                    .trim(from: 0, to: viewModel.progress)
                    .stroke(
                        Color(designSystemColor: .accentPrimary),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: progressSize, height: progressSize)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color(designSystemColor: .accentPrimary).opacity(0.8), radius: 2, x: 0, y: 0)
                    .shadow(color: Color(designSystemColor: .accentPrimary).opacity(0.5), radius: 6, x: 0, y: 0)
                    .shadow(color: Color(designSystemColor: .accentPrimary).opacity(0.3), radius: 12, x: 0, y: 0)
                    .animation(.linear(duration: 0.05), value: viewModel.progress)

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

            Spacer()

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
            .onHover { hovering in
                isButtonHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            // Fires on mouseDown event to trigger the `onDontAskAgain` callback
            // before the popup is dismissed by the click event
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        viewModel.dontAskAgainTapped()
                    }
            )
        }
        .padding(.top, 24)
        .padding(.bottom, 24)
        .padding(.leading, 32)
        .padding(.trailing, 32)
        .frame(width: windowSize.width, height: windowSize.height)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(backgroundColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .onHover { isHovering in
            viewModel.hoverChanged(isHovering)
        }
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
    let appearancePersistor = AppearancePreferencesPersistorMock()
    let appearancePrefs = AppearancePreferences(
        persistor: appearancePersistor,
        privacyConfigurationManager: nil,
        featureFlagger: nil
    )

    return StartupPreferences(
        persistor: PreviewStartupPreferencesPersistor(restorePreviousSession: restorePreviousSession),
        appearancePreferences: appearancePrefs
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
    @Binding var progress: CGFloat
    let makeViewModel: (ColorPalette, CGFloat) -> WarnBeforeQuitViewModel

    var body: some View {
        VStack(spacing: 20) {
            WarnBeforeQuitView(viewModel: {
                DesignSystemPalette.current = colorPalette
                return makeViewModel(colorPalette, progress)
            }())

            VStack(spacing: 12) {
                ColorPaletteSelector(colorPalette: $colorPalette)

                Divider()

                HStack {
                    Text(verbatim: "Progress:")
                        .font(.headline)
                    Slider(value: $progress, in: 0...1)
                    Text(verbatim: "\(Int(progress * 100))%")
                        .monospacedDigit()
                        .frame(width: 45)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(40)
    }
}

// MARK: - Previews

@available(macOS 14.0, *)
#Preview("Quit - With Subtitle") {
    @Previewable @State var colorPalette: ColorPalette = .default
    @Previewable @State var progress: CGFloat = 0.6

    InteractivePreview(colorPalette: $colorPalette, progress: $progress) { _, progress in
        let vm = WarnBeforeQuitViewModel(
            action: .quit,
            startupPreferences: makePreviewStartupPreferences(restorePreviousSession: true)
        )
        vm.updateProgress(progress)
        return vm
    }
}

@available(macOS 14.0, *)
#Preview("Quit - No Subtitle") {
    @Previewable @State var colorPalette: ColorPalette = .default
    @Previewable @State var progress: CGFloat = 0.6

    InteractivePreview(colorPalette: $colorPalette, progress: $progress) { _, progress in
        let vm = WarnBeforeQuitViewModel(
            action: .quit,
            startupPreferences: makePreviewStartupPreferences(restorePreviousSession: false)
        )
        vm.updateProgress(progress)
        return vm
    }
}

@available(macOS 14.0, *)
#Preview("Close Pinned Tab") {
    @Previewable @State var colorPalette: ColorPalette = .default
    @Previewable @State var progress: CGFloat = 0.3

    InteractivePreview(colorPalette: $colorPalette, progress: $progress) { _, progress in
        let vm = WarnBeforeQuitViewModel(action: .close, startupPreferences: nil)
        vm.updateProgress(progress)
        return vm
    }
}

#endif
