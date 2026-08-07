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
/// resolver's content state: list rows / favorites / logo. One view, model decides the rest.
struct UnifiedSuggestionsView: View {

    @ObservedObject var viewModel: UnifiedSuggestionsViewModel
    let isAddressBarAtBottom: Bool
    /// Built lazily by the host for the `.favorites` state; nil when favorites aren't supported (Duck.ai).
    let favoritesProvider: () -> NewTabPageViewController?

    var body: some View {
        // The chrome (escape hatch + sync-promo) is pinned to the bar by the container (it rides the
        // bar's UIKit animation in the same layout pass), so it's not in this host. The logo overlays
        // the content, anchored to the keyboard (the host's fixed bottom) so neither the bar-driven top
        // inset nor a Search↔Duck.ai toggle moves it.
        ZStack(alignment: .bottom) {
            contentArea
            logoLayer
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

    private var contentArea: some View {
        // The list stays mounted in every state so SwiftUI never recreates it (a fresh `List`
        // flashes its default background before `.scrollContentBackground(.hidden)` applies).
        // Favorites renders on top; the list is hidden + non-interactive beneath it.
        ZStack {
            listLayer
            overlayLayer
        }
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

    private var listLayer: some View {
        SuggestionsListView(viewModel: viewModel.listViewModel(for: activeListKind),
                            isAddressBarAtBottom: isAddressBarAtBottom)
            .opacity(isShowingList ? 1 : 0)
            // Fade *in* on a mode change, but snap *out* — otherwise the recents list lingers over the
            // Search favorites/logo (which snap in instantly) when toggling away from Duck.ai.
            .animation(isShowingList ? .easeInOut(duration: 0.2) : nil, value: isShowingList)
            // Fade out with the collapse (like the logo) so a list→favorites dismiss hands off to the
            // NTP favorites instead of snapping away when the host is hidden.
            .modifier(DismissFade(isFadingOut: viewModel.isFadingOut))
            .allowsHitTesting(isShowingList)
    }

    private var isShowingFavorites: Bool {
        if case .favorites = viewModel.content { return true }
        return false
    }

    /// Favorites stays mounted like the list and toggles a plain `.opacity` — NOT an insert/remove
    /// `.transition` (which snaps when interrupted by rapid Search↔Duck.ai toggling). Its opacity is
    /// instant (`.animation(nil)`): the incoming list fades in, but favorites must not linger visibly
    /// over Duck.ai while the crossfade runs.
    @ViewBuilder
    private var overlayLayer: some View {
        if let controller = favoritesProvider() {
            // Extend under the top safe area so the frame stays static; the top inset is delivered to
            // the nested NTP's own scroll view as a content inset (animatable), not as a frame move.
            SuggestionsFavoritesView(controller: controller)
                .ignoresSafeArea(.container, edges: .top)
                .opacity(isShowingFavorites ? 1 : 0)
                .animation(nil, value: isShowingFavorites)
                .allowsHitTesting(isShowingFavorites)
        }
    }

    private var isShowingLogo: Bool {
        if case .logo = viewModel.content { return true }
        return false
    }

    /// The Dax↔Duck.ai empty-state logo, morphing via bound `logoProgress`. Pinned to the exact
    /// screen-relative anchor `NewTabPageDaxLogoView` uses, so the focused and NTP logos share one
    /// resting position+size — focus/defocus is a pixel-identical crossfade (no slide), and it's stable
    /// across Search↔Duck.ai toggles and the keyboard (screen-relative, not bar/keyboard-relative).
    private var logoLayer: some View {
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
                topChromeBottom: frame.minY + viewModel.chromeInsetTop,
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
                .opacity(isShowingLogo && !viewModel.isFireTab && !viewModel.isLandscape ? 1 : 0)
                .animation(nil, value: isShowingLogo)
                // On dismiss it fades out (the NTP content takes over) — a separate opacity so the
                // toggle's instant show/hide above is unaffected.
                .modifier(DismissFade(isFadingOut: viewModel.isFadingOut))
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
    }
}

/// Fades transient content (logo, suggestion list) out as the host collapses back to the NTP, so it
/// hands off to the NTP content instead of snapping away. Favorites are excluded — they hand off via
/// the embedded-copy reveal, not a fade.
///
/// One-directional: only the fade-*out* (false→true) animates. The reset (true→false, on the next
/// focus) snaps, so the logo reappears instantly instead of replaying a fade-in.
private struct DismissFade: ViewModifier {
    let isFadingOut: Bool
    func body(content: Content) -> some View {
        content
            .opacity(isFadingOut ? 0 : 1)
            .animation(isFadingOut ? .easeInOut(duration: 0.2) : nil, value: isFadingOut)
    }
}
