//
//  UnifiedSuggestionsView.swift
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
import UIKit

/// The single unified suggestions surface for both Search and Duck.ai. Switches on the
/// resolver's content state: list rows / favorites / logo. One view, model decides the rest.
struct UnifiedSuggestionsView: View {

    @ObservedObject var viewModel: UnifiedSuggestionsViewModel
    let isAddressBarAtBottom: Bool
    let favoritesPresentation: FocusedFavoritesPresentation
    var usesScrollableEscapeHatch = true
    var usesRedesignedNewTabPageLayout = false
    var showsRedesignedSearchModules = false
    var mode: TextEntryMode = .search
    var escapeHatch: EscapeHatchModel?
    var syncPromo: AnyView?

    var body: some View {
        ZStack(alignment: .bottom) {
            if usesScrollableEscapeHatch {
                logoLayer
            }
            contentArea
            if !usesScrollableEscapeHatch {
                logoLayer
            }
            fireLayer
        }
        // UIKit already bounds this host with its keyboard layout guide. Keep container
        // safe areas and the input-bar inset, without a second SwiftUI keyboard adjustment.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// On a fire tab every non-typing state is the full fire screen — favorites/recents/logo never show
    /// there (matching the legacy behaviour, where the opaque fire screen covered them). Only the typing
    /// suggestion list shows; otherwise this opaque layer covers the content beneath. Always shown on a
    /// fire tab (incl. landscape) — suppressing it would expose the favorites/recents the resolver still
    /// produces underneath.
    @ViewBuilder
    private var fireLayer: some View {
        if viewModel.isFireTab {
            let showsFire = !isTypingList
            FireModeEmptyStateView(type: .tab, contentTopInset: viewModel.contentTopInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(designSystemColor: .background))
                .opacity(showsFire ? 1 : 0)
                .allowsHitTesting(showsFire)
        }
    }

    /// The active typing states (the search / duck.ai suggestion lists); recents and empty states aren't.
    private var isTypingList: Bool {
        if case .list(let kind) = viewModel.content { return kind == .search || kind == .duckAI }
        return false
    }

    private var contentArea: some View {
        // The list stays mounted in every state so SwiftUI never recreates it (a fresh `List`
        // flashes its default background before `.scrollContentBackground(.hidden)` applies).
        // Favorites renders on top; the list is hidden + non-interactive beneath it.
        ZStack {
            listLayer
            if usesRedesignedNewTabPageLayout {
                RedesignedFocusedSearchModulesView(favoritesModel: favoritesPresentation.viewController?.favoritesModel,
                                                   messagesModel: favoritesPresentation.viewController?.messagesModel,
                                                   showsSearchModules: !usesScrollableEscapeHatch || showsRedesignedSearchModules,
                                                   recentChats: usesScrollableEscapeHatch && mode == .aiChat ? viewModel.listViewModel(for: .recents) : nil,
                                                   escapeHatch: escapeHatch,
                                                   syncPromo: usesScrollableEscapeHatch ? syncPromo : nil,
                                                   isAddressBarAtBottom: isAddressBarAtBottom,
                                                   contentTopInset: viewModel.contentTopInset,
                                                   usesScrollableEscapeHatch: usesScrollableEscapeHatch)
                    .background(usesScrollableEscapeHatch ? Color.clear : Color(designSystemColor: .background))
                    // Keep expansion and scroll state while typing or switching modes. Only one
                    // favorites hierarchy is mounted for the selected layout.
                    .opacity(showsEmbeddedContent ? 1 : 0)
                    .animation(nil, value: showsEmbeddedContent)
                    .allowsHitTesting(showsEmbeddedContent)
                    .accessibilityHidden(!showsEmbeddedContent)
                    .transition(.identity)
                    .modifier(FocusedContentDismissFade(isFadingOut: viewModel.isFadingOut))
            } else {
                SuggestionsFavoritesView(presentation: favoritesPresentation, isVisible: showsEmbeddedContent)
                    .transition(.identity)
                    .modifier(FocusedContentDismissFade(isFadingOut: usesScrollableEscapeHatch && viewModel.isFadingOut))
            }
        }
    }

    private var isShowingList: Bool {
        guard !showsEmbeddedContent else { return false }
        if case .list = viewModel.content { return true }
        return false
    }

    /// The kind the mounted list is currently bound to; defaults to `.search` when idle so the
    /// list holds a stable (empty) view-model rather than being torn down.
    private var activeListKind: SuggestionsListSourceKind {
        if case .list(let kind) = viewModel.content { return kind }
        return .search
    }

    private var listLayer: some View {
        FocusedSuggestionsView(viewModel: viewModel.listViewModel(for: activeListKind),
                               isAddressBarAtBottom: isAddressBarAtBottom,
                               isVisible: isShowingList,
                               isFadingOut: viewModel.isFadingOut,
                               animatesAppearance: !usesScrollableEscapeHatch || usesRedesignedNewTabPageLayout)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: viewModel.contentTopInset)
            }
    }

    private var showsEmbeddedContent: Bool {
        UnifiedSuggestionsContentResolver.showsEmbeddedContent(
            usesScrollableEscapeHatch: usesScrollableEscapeHatch,
            usesRedesignedNewTabPageLayout: usesRedesignedNewTabPageLayout,
            showsRedesignedSearchModules: showsRedesignedSearchModules,
            isFireTab: viewModel.isFireTab,
            content: viewModel.content)
    }

    private var isShowingLogo: Bool {
        viewModel.isShowingLogo
    }

    /// The Dax↔Duck.ai empty-state logo, morphing via bound `logoProgress`. Pinned to the exact
    /// screen-relative anchor `NewTabPageDaxLogoView` uses, so the focused and NTP logos share one
    /// resting position+size — focus/defocus is a pixel-identical crossfade (no slide), and it's stable
    /// across Search↔Duck.ai toggles and the keyboard (screen-relative, not bar/keyboard-relative).
    private var logoLayer: some View {
        GeometryReader { proxy in
            // Preserve input-bar and keyboard clearance when no escape hatch is shown.
            let frame = proxy.frame(in: .global)
            let nativeViewport = viewModel.logoViewportFrame
            let viewport = nativeViewport ?? frame
            let targetCenterY = Self.logoCenterY(
                restingAt: UIScreen.main.bounds.midY - Metrics.logoScreenCenterOffset,
                topChromeBottom: viewport.minY + viewModel.chromeInsetTop,
                barTop: viewport.maxY)
            let offsetY = targetCenterY - frame.midY
            let logo = FocusedDaxLogoView(progress: viewModel.logoModel.progress,
                                         morph: viewModel.logoModel.morphs,
                                         animationSpeed: viewModel.logoModel.morphSpeed)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            let animation: Animation? = UIApplication.shared.applicationState == .active ? .easeInOut(duration: 0.2) : nil
            Group {
                if nativeViewport != nil {
                    // Animate real clearance changes; compensate transient host movement immediately.
                    logo.offset(y: targetCenterY)
                        .animation(animation, value: targetCenterY)
                        .offset(y: -frame.midY)
                        .animation(nil, value: frame.midY)
                } else {
                    logo.offset(y: offsetY)
                        .animation(animation, value: targetCenterY)
                }
            }
                // Show/hide is instant (matches the favorites overlay) so the logo doesn't linger over
                // favorites/lists during a toggle. Logo→logo keeps it shown, so this never cuts a morph.
                // Suppressed on fire tabs (fire screen takes the slot) and in landscape (no room — matches
                // the unfocused NTP / legacy gate).
                .opacity(isShowingLogo && !viewModel.isFireTab && !viewModel.isLandscape ? 1 : 0)
                .animation(nil, value: isShowingLogo)
                // On dismiss it fades out (the NTP content takes over) — a separate opacity so the
                // toggle's instant show/hide above is unaffected.
                .modifier(FocusedContentDismissFade(isFadingOut: viewModel.isFadingOut))
                .allowsHitTesting(false)
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Clamps the resting center between the top chrome and the keyboard/input bar.
    /// If both margins do not fit, use the center of the available space.
    private static func logoCenterY(restingAt restCenterY: CGFloat,
                                    topChromeBottom: CGFloat,
                                    barTop: CGFloat) -> CGFloat {
        let halfHeight = Metrics.logoHeight / 2
        let barLimit = barTop - Metrics.bottomBarGap - halfHeight
        let chromeFloor = topChromeBottom + Metrics.topChromeGap + halfHeight
        guard chromeFloor <= barLimit else { return (topChromeBottom + barTop) / 2 }
        return min(max(restCenterY, chromeFloor), barLimit)
    }

    private enum Metrics {
        /// Mirrors `NewTabPageDaxLogoView`'s screen-center offset so the focused Search logo lands exactly
        /// where the NTP logo sits — keep in sync with that view.
        static let logoScreenCenterOffset: CGFloat = 55
        /// Min gap kept below the top chrome before the logo is pushed down. Tune.
        static let topChromeGap: CGFloat = 16
        /// Min gap kept above the bottom bar before the logo is pushed up. Larger than the top gap — the
        /// bottom bar is tall, so the logo needs more breathing room to sit balanced above it. Tune.
        static let bottomBarGap: CGFloat = 56
        /// Mirrors `FocusedDaxLogoView`'s height — used to find the logo's top for the overlap check.
        static let logoHeight: CGFloat = 162
    }
}
