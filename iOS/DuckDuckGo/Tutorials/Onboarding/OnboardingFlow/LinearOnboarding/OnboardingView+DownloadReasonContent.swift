//
//  OnboardingView+DownloadReasonContent.swift
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

import DuckUI
import Lottie
import Onboarding
import SwiftUI
import UIComponents
import DesignResourcesKit
import DesignResourcesKitIcons

extension OnboardingView {

    /// Grid: https://www.figma.com/design/vsuCJP9OGykRkk1iZIU0ek/Mobile-Onboarding---Segmented?node-id=89-87784
    /// List: https://www.figma.com/design/icdZo7pS4cAWaoVf4byU9t/Add-VPN-to-list-of-download-reasons?node-id=5170-28324
    struct DownloadReasonContent: View {
        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        @State private var shouldStartTyping = false
        @State private var showContent = false
        @State private var selectedDownloadReason: OnboardingDownloadReasonContent.Option?
        @Binding var isVisible: Bool
        private let content: OnboardingDownloadReasonContent
        private let action: (OnboardingDownloadReasonContent.Option) -> Void

        init(
            content: OnboardingDownloadReasonContent,
            isVisible: Binding<Bool> = .constant(false),
            action: @escaping (OnboardingDownloadReasonContent.Option) -> Void
        ) {
            self.content = content
            self._isVisible = isVisible
            self.action = action
        }

        var body: some View {
            LinearDialogContentContainer(
                metrics: .init(
                    outerSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    textSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    contentSpacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing,
                    actionsSpacing: onboardingTheme.linearOnboardingMetrics.actionsSpacing
                ),
                message: AnyView(
                    Text(content.message)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .font(onboardingTheme.typography.body)
                        .multilineTextAlignment(.center)
                ),
                content: AnyView(reasons),
                showContent: $showContent,
                title: {
                    TypingText(
                        content.title,
                        startAnimating: $shouldStartTyping,
                        onTypingFinished: { [reduceMotion] in
                            if reduceMotion {
                                showContent = true
                            } else {
                                withAnimation { showContent = true }
                            }
                        }
                    )
                    .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                    .font(onboardingTheme.typography.title)
                    .multilineTextAlignment(.center)
                },
                actions: {
                    Button(action: handleNextButtonAction) {
                        Text(content.primaryCTA)
                    }
                    .disabled(selectedDownloadReason == nil)
                    .buttonStyle(onboardingTheme.primaryButtonStyle.style)
                }
            )
            .onBubbleVisibilityChanged(isVisible: $isVisible, shouldStartTyping: $shouldStartTyping, showContent: $showContent)
        }

        @ViewBuilder
        private var reasons: some View {
            switch content.layout {
            case .grid:
                DownloadReasonGrid(items: content.options, selectedItem: selectedDownloadReason) { selectedDownloadReason = $0 }
            case .list:
                DownloadReasonList(items: content.options, selectedItem: selectedDownloadReason) { selectedDownloadReason = $0 }
            }
        }

        func handleNextButtonAction() {
            guard let selectedDownloadReason else { return }
            action(selectedDownloadReason)
        }
    }

}

/// Reports the tallest tile so every tile can be pinned to that height, keeping rows uniform
/// regardless of how many lines each title wraps to (e.g. on narrow screens like iPhone SE).
private struct DownloadReasonItemHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DownloadReasonGrid: View {

    private enum Metrics {
        static let itemSpacing: CGFloat = 8
    }

    private let items: [OnboardingDownloadReasonContent.Option]
    private let selectedItem: OnboardingDownloadReasonContent.Option?
    private let rowAndColumns: [[OnboardingDownloadReasonContent.Option]]
    private let onSelect: (OnboardingDownloadReasonContent.Option) -> Void

    @State private var itemHeight: CGFloat?

    init(items: [OnboardingDownloadReasonContent.Option], selectedItem: OnboardingDownloadReasonContent.Option?, columns: Int = 2, onSelect: @escaping (OnboardingDownloadReasonContent.Option) -> Void) {
        self.items = items
        self.selectedItem = selectedItem
        rowAndColumns = items.chunked(into: columns)
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(alignment: .center, spacing: Metrics.itemSpacing) {
            ForEach(rowAndColumns, id: \.self) { row in
                HStack(spacing: Metrics.itemSpacing) {
                    ForEach(row, id: \.self) { reason in
                        DownloadReasonButton(asset: reason.asset, title: reason.title, isSelected: reason == selectedItem, height: itemHeight) {
                            onSelect(reason)
                        }
                    }
                }
            }
        }
        .compositingGroup() // Flatten the whole grid so the container's fade can't bleed shadows through fills
        .onPreferenceChange(DownloadReasonItemHeightPreferenceKey.self) { height in
            itemHeight = height > 0 ? height : nil
        }
    }

}

private extension DownloadReasonGrid {

    struct DownloadReasonButton: View {

        private enum Metrics {
            static let contentVerticalSpacing: CGFloat = 0
            static let contentHorizontalPadding: CGFloat = 16
            static let contentTopPadding: CGFloat = 12
            static let contentBottomPadding: CGFloat = 20
            static let cornerRadius: CGFloat = 24
            static let imageSize = CGSize(width: 64, height: 64)
            // Shadow
            static let innerShadowColor: Color = .black.opacity(0.06)
            static let innerShadowRadius: CGFloat = 2
            static let innerShadowOffset = CGPoint(x: 0, y: 1)
            static let outerShadowColor: Color = .black.opacity(0.16)
            static let outerShadowRadius: CGFloat = 0.5
            static let outerShadowOffset = CGPoint(x: 0, y: 0.25)
            // Stroke
            static let strokeInset: CGFloat = 0.5
            static let strokeWidth: CGFloat = 1
        }

        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        @State private var isPlaying = false

        let asset: OnboardingDownloadReasonContent.Asset
        let title: String
        let isSelected: Bool
        /// Uniform tile height supplied by the grid (the tallest tile). `nil` on the first pass, before measuring.
        let height: CGFloat?
        let action: () -> Void

        var body: some View {
            VStack(alignment: .center, spacing: Metrics.contentVerticalSpacing) {
                // The pictogram rests on its last frame (a fully-drawn icon), then replays
                // from the start each time the tile is tapped. Reduce Motion keeps it frozen.
                DownloadReasonAsset(asset: asset, playbackMode: playbackMode, onAnimationFinished: { isPlaying = false })
                    .frame(width: Metrics.imageSize.width, height: Metrics.imageSize.height)

                Text(title)
                    .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                    .font(onboardingTheme.typography.contextual.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Metrics.contentHorizontalPadding)
            .padding(.top, Metrics.contentTopPadding)
            .padding(.bottom, Metrics.contentBottomPadding)
            .frame(maxWidth: .infinity, alignment: .top)
            // Measure the tile's natural height. We set them all to the highest value to avoid tiles with different heights.
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: DownloadReasonItemHeightPreferenceKey.self, value: proxy.size.height)
                }
            )
            .frame(height: height, alignment: .top)
            .background(isSelected ? OnboardingRebrandColor.accentAltPrimary : onboardingTheme.colorPalette.bubbleBackground)
            .cornerRadius(Metrics.cornerRadius)
            .shadow(color: Metrics.innerShadowColor, radius: Metrics.innerShadowRadius, x: Metrics.innerShadowOffset.x, y: Metrics.innerShadowOffset.y)
            .shadow(color: Metrics.outerShadowColor, radius: Metrics.outerShadowRadius, x: Metrics.outerShadowOffset.x, y: Metrics.outerShadowOffset.y)
            .overlay(overlay)
            .onTapGesture {
                // Fires on touch-up inside; cancels if the touch becomes a scroll.
                if !reduceMotion {
                    isPlaying = true
                }
                action()
            }
        }

        private var playbackMode: LottiePlaybackMode {
            guard !reduceMotion else { return .paused(at: .progress(1)) }
            return isPlaying
                ? .playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce))
                : .paused(at: .progress(1))
        }

        @ViewBuilder
        private var overlay: some View {
            // A selected button is always outlined with the theme's border color. An unselected
            // button is outlined only in dark mode, with a subtle white edge; in light mode it
            // has no border.
            let borderColor: Color? = if isSelected {
                onboardingTheme.colorPalette.optionsListBorderColor
            } else if colorScheme == .dark {
                .white.opacity(0.12)
            } else {
                nil
            }

            if let borderColor {
                RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                    .inset(by: Metrics.strokeInset)
                    .stroke(borderColor, lineWidth: Metrics.strokeWidth)
            }
        }
    }

}

private enum DownloadReasonListMetrics {
    static let rowSpacing: CGFloat = 12
    static let listHorizontalPadding: CGFloat = 4
    static let contentSpacing: CGFloat = 16
    static let iconSpacing: CGFloat = 12
    static let iconSize: CGFloat = 24
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 12
    static let cornerRadius: CGFloat = 16
    static let borderWidth: CGFloat = 1
    static let borderLightColor = Color.black.opacity(0.12)
    static let borderDarkColor = Color.white.opacity(0.12)
    static let accentColor = Color(singleUseColor: .rebranding(.accentPrimary))
}

private struct DownloadReasonList: View {

    let items: [OnboardingDownloadReasonContent.Option]
    let selectedItem: OnboardingDownloadReasonContent.Option?
    let onSelect: (OnboardingDownloadReasonContent.Option) -> Void

    var body: some View {
        VStack(spacing: DownloadReasonListMetrics.rowSpacing) {
            ForEach(items, id: \.self) { item in
                DownloadReasonRow(asset: item.asset, title: item.title, isSelected: item == selectedItem) {
                    onSelect(item)
                }
            }
        }
        .padding(.horizontal, DownloadReasonListMetrics.listHorizontalPadding)
    }

}

private struct DownloadReasonRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.onboardingTheme) private var onboardingTheme

    let asset: OnboardingDownloadReasonContent.Asset
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DownloadReasonListMetrics.contentSpacing) {
                HStack(spacing: DownloadReasonListMetrics.iconSpacing) {
                    DownloadReasonAsset(asset: asset)
                        .frame(width: DownloadReasonListMetrics.iconSize, height: DownloadReasonListMetrics.iconSize)

                    Text(title)
                        .font(onboardingTheme.typography.contextual.body)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                OnboardingRebranding.RadioIndicator(isSelected: isSelected, accentColor: DownloadReasonListMetrics.accentColor)
            }
            .padding(.horizontal, DownloadReasonListMetrics.horizontalPadding)
            .padding(.vertical, DownloadReasonListMetrics.verticalPadding)
            .frame(maxWidth: .infinity)
            .background(isSelected ? OnboardingRebrandColor.accentAltGlowPrimary : .clear)
            .clipShape(RoundedRectangle(cornerRadius: DownloadReasonListMetrics.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DownloadReasonListMetrics.cornerRadius)
                    .strokeBorder(borderColor, lineWidth: DownloadReasonListMetrics.borderWidth)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var borderColor: Color {
        if isSelected {
            DownloadReasonListMetrics.accentColor
        } else {
            colorScheme == .light ? DownloadReasonListMetrics.borderLightColor : DownloadReasonListMetrics.borderDarkColor
        }
    }

}

// MARK: - Asset

/// Renders a reason's animation or icon. Icons ignore the playback mode.
private struct DownloadReasonAsset: View {
    let asset: OnboardingDownloadReasonContent.Asset
    var playbackMode: LottiePlaybackMode = .paused(at: .progress(1))
    var onAnimationFinished: () -> Void = {}

    var body: some View {
        switch asset {
        case let .animation(animation):
            Lottie.LottieView {
                try await DotLottieFile.asset(named: animation.rawValue)
            }
            .playbackMode(playbackMode)
            .animationDidFinish { _ in onAnimationFinished() }
            .resizable()
        case let .icon(icon):
            Image(uiImage: icon.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

private extension OnboardingDownloadReasonContent.Icon {

    var image: UIImage {
        switch self {
        case .search: DesignSystemImages.Color.Size24.findSearch
        case .aiChat: DesignSystemImages.Color.Size24.aiChat
        case .adsBlocked: DesignSystemImages.Color.Size24.adsBlocked
        case .block: DesignSystemImages.Color.Size24.block
        case .vpn: DesignSystemImages.Color.Size24.vpn
        }
    }

}
