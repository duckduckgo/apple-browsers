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

/// The single unified suggestions surface for both Search and Duck.ai. Switches on the
/// resolver's content state: list rows / favorites. The logo uses a separate stable sibling host.
struct UnifiedSuggestionsView: View {

    @ObservedObject var viewModel: UnifiedSuggestionsViewModel
    let isAddressBarAtBottom: Bool
    let isFloatingUIEnabled: Bool
    let dismissKeyboardOnRestingContentScroll: Bool
    let escapeHatch: EscapeHatchModel?
    @ObservedObject var favoritesViewModel: FavoritesViewModel
    @ObservedObject var messagesModel: NewTabPageMessagesModel

    var body: some View {
        // One mounted list owns every focused state. Its first row keeps the Escape Hatch alive while
        // Search favorites/RMF and Duck.ai promo/recents change beneath it.
        ZStack(alignment: .bottom) {
            listLayer
            fireLayer
        }
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
            FireModeEmptyStateView(type: .tab)
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

    private var isShowingList: Bool {
        if case .list = viewModel.content { return true }
        return false
    }

    /// The kind the mounted list is currently bound to; defaults to `.search` when idle so the
    /// list holds a stable (empty) view-model rather than being torn down.
    private var activeListKind: SuggestionsListSourceKind {
        if case .list(let kind) = viewModel.content { return kind }
        return .search
    }

    private var usesWholeListDismissFade: Bool {
        isShowingList
    }

    private var listLayer: some View {
        SuggestionsListView(viewModel: viewModel.listViewModel(for: activeListKind),
                            isAddressBarAtBottom: isAddressBarAtBottom,
                            showsAmbientMessageShadow: !isFloatingUIEnabled || isAddressBarAtBottom,
                            scrollContentInsetTop: viewModel.scrollContentInsetTop,
                            escapeHatch: escapeHatch,
                            syncPromo: activeListKind == .recents ? viewModel.syncPromo : nil,
                            favoritesViewModel: favoritesViewModel,
                            homeMessageViewModels: messagesModel.homeMessageViewModels,
                            showsRestingContent: !isTypingList,
                            showsFavorites: viewModel.isShowingFavorites,
                            showsSuggestionRows: isShowingList,
                            dismissKeyboardOnScroll: isShowingList || dismissKeyboardOnRestingContentScroll,
                            usesWholeListDismissFade: usesWholeListDismissFade,
                            animationModel: viewModel.animationModel)
            // Space outside the List moves its clipping edge above the toolbar while scrolling.
            .padding(.bottom, FloatingUILayoutPolicy.focusedFavoritesBottomSpacing(
                isFloatingUIEnabled: isFloatingUIEnabled,
                isAddressBarAtBottom: isAddressBarAtBottom,
                isLandscape: viewModel.isLandscape,
                isShowingFavorites: viewModel.isShowingFavorites))
            // Fade complete lists so native cell surfaces and separators cannot outlive their
            // SwiftUI row content during dismissal.
            .modifier(DismissFade(animationModel: viewModel.animationModel,
                                  isEnabled: usesWholeListDismissFade))
            // The floating-bottom host already consumes the system top safe area. Ignore its transient
            // relayout pulse here so List does not turn it into an animated content-offset correction.
            .ignoresSafeArea(.container, edges: isFloatingUIEnabled && isAddressBarAtBottom ? .top : [])
            .accessibilityHidden(viewModel.isFireTab && !isTypingList)
    }
}

/// Keeps the empty-state logo in a stable hosting tree while the scrollable host follows the UTI.
struct UnifiedSuggestionsLogoView: View {

    @ObservedObject var viewModel: UnifiedSuggestionsViewModel
    let escapeHatch: EscapeHatchModel?

    var body: some View {
        GeometryReader { proxy in
            // Rests at the NTP logo's exact screen anchor (so focus/defocus is a crossfade from the NTP
            // position, and the morph happens in place on a toggle), but kept a minimum gap from the
            // chrome on *both* sides so the chrome never covers it:
            //  • pushed DOWN if the top chrome (hatch) comes within `minChromeGap` of the logo's top
            //    (top-bar Duck.ai); the chrome bottom is `minY + chromeInsetTop`, known as the bar animates.
            //  • pushed UP if the bar's top edge comes within `minChromeGap` of the logo's bottom
            //    (bottom-bar omnibar); the bar top is `maxY` — the content-area bottom rides the bar-height
            //    safe-area inset, so it tracks the bar in the same pass.
            // With room on both sides the pushes clamp to 0 and the logo stays at the NTP anchor.
            let frame = proxy.frame(in: .global)
            let targetCenterY = Self.logoCenterY(
                restingAt: UIScreen.main.bounds.midY - Metrics.logoScreenCenterOffset,
                topChromeBottom: frame.minY + viewModel.chromeInsetTop + escapeHatchLogoZoneHeight,
                barTop: frame.maxY)
            FocusedDaxLogoView(progress: viewModel.logoModel.progress,
                               morph: viewModel.logoModel.morphs,
                               animationSpeed: viewModel.logoModel.morphSpeed)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: targetCenterY - frame.midY)
                // Match the bar's toggle animation (0.2s easeInOut) so the logo settles with it, not after.
                .animation(.easeInOut(duration: 0.2), value: targetCenterY)
                // Show/hide is instant (matches the favorites overlay) so the logo doesn't linger over
                // favorites/lists during a toggle. Logo→logo keeps it shown, so this never cuts a morph.
                // Suppressed on fire tabs (fire screen takes the slot) and in landscape (no room — matches
                // the unfocused NTP / legacy gate).
                .opacity(viewModel.isShowingLogo && !viewModel.isFireTab && !viewModel.isLandscape ? 1 : 0)
                .animation(nil, value: viewModel.isShowingLogo)
                // On dismiss it fades out (the NTP content takes over) — a separate opacity so the
                // toggle's instant show/hide above is unaffected.
                .modifier(DismissFade(animationModel: viewModel.animationModel))
                .allowsHitTesting(false)
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    /// The logo's screen-center Y: it rests at `restCenterY` (the NTP anchor) but is clamped into the band
    /// between the chrome — pulled up to keep `bottomBarGap` above the bar/keyboard top edge (`barTop`), and
    /// held at least `topChromeGap` below the top chrome (`topChromeBottom`, e.g. the hatch). On a short
    /// screen where the band can't fit the logo plus both gaps, it centers the logo between the two chrome
    /// edges instead — clearing the keyboard and the hatch as evenly as possible rather than slipping under
    /// either (the wordmark must not hide behind the keyboard).
    private static func logoCenterY(restingAt restCenterY: CGFloat,
                                    topChromeBottom: CGFloat,
                                    barTop: CGFloat) -> CGFloat {
        let halfHeight = Metrics.logoHeight / 2
        let barLimit = barTop - Metrics.bottomBarGap - halfHeight
        let hatchFloor = topChromeBottom + Metrics.topChromeGap + halfHeight
        guard hatchFloor <= barLimit else { return (topChromeBottom + barTop) / 2 }
        return min(max(restCenterY, hatchFloor), barLimit)
    }

    private enum Metrics {
        /// Mirrors `NewTabPageDaxLogoView`'s screen-center offset so the focused Search logo lands exactly
        /// where the NTP logo sits — keep in sync with that view.
        static let logoScreenCenterOffset: CGFloat = 55
        /// Min gap kept below the top chrome (hatch) before the logo is pushed down. Tune.
        static let topChromeGap: CGFloat = 16
        /// Min gap kept above the bottom bar before the logo is pushed up. Larger than the top gap — the
        /// bottom bar is tall, so the logo needs more breathing room to sit balanced above it. Tune.
        static let bottomBarGap: CGFloat = 56
        /// Mirrors `FocusedDaxLogoView`'s height — used to find the logo's top for the overlap check.
        static let logoHeight: CGFloat = 162
        /// Mirrors the legacy focused-logo offset, keeping the logo below a scrollable Escape Hatch.
        static let escapeHatchLogoZoneHeight: CGFloat = 70
    }

    private var escapeHatchLogoZoneHeight: CGFloat {
        escapeHatch == nil ? 0 : Metrics.escapeHatchLogoZoneHeight
    }
}

/// Fades focused content out as the host collapses back to the NTP, so it hands off instead of snapping away.
///
/// One-directional: only the fade-*out* (false→true) animates. The reset (true→false, on the next
/// focus) snaps, so the logo reappears instantly instead of replaying a fade-in.
struct DismissFade: ViewModifier {
    @ObservedObject var animationModel: UnifiedSuggestionsAnimationModel
    var isEnabled = true

    func body(content: Content) -> some View {
        let isDismissing = isEnabled && animationModel.isDismissing
        content
            .opacity(isDismissing ? 0 : 1)
            .animation(isDismissing ? .easeInOut(duration: 0.2) : nil,
                       value: isDismissing)
    }
}
