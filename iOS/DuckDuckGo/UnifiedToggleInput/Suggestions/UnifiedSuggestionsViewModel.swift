//
//  UnifiedSuggestionsViewModel.swift
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

import Combine
import Foundation
import SwiftUI

/// Aggregates input facts, runs `UnifiedSuggestionsContentResolver`, and publishes the
/// presentation `content` for `UnifiedSuggestionsView`. Holds the active list view model.
@MainActor
final class UnifiedSuggestionsViewModel: ObservableObject {

    /// How the focused content leaves the screen on a collapse. A dismiss is *either* a fade-out
    /// *or* a logo morph-home — never both — so this single value makes the illegal combination
    /// unrepresentable.
    enum DismissBehavior: Equatable {
        case none
        /// Fade the transient content (logo / suggestion list) out as the NTP content takes over.
        case fadeOut
        /// Logo→logo: morph the logo back to the Dax mark and keep it visible (the morph itself lives
        /// in `logoModel`).
        case morphHome
    }

    @Published private(set) var content: UnifiedSuggestionsContentKind = .logo
    /// Reactive sync-promo visibility (driven by the container) so show/hide animates with the
    /// content crossfade instead of snapping via a root-view rebuild.
    @Published var showsSyncPromo = false
    /// The empty-state logo's presentation (mark / morph / speed). All its transitions are pure, so
    /// the morph rules are tested in `FocusedLogoModelTests`.
    @Published private(set) var logoModel = FocusedLogoModel()
    /// How the content collapses back to the omnibar. Cleared on the next focus.
    @Published private(set) var dismissBehavior: DismissBehavior = .none
    /// Chrome bottom (bar + reserved hatch) below the host top, pushed by the container as the bar
    /// animates. The logo keeps a minimum distance from it — known *during* the resize, so the logo
    /// moves in the same pass, and only when the chrome is actually close (never in Search).
    @Published var chromeInsetTop: CGFloat = 0
    /// The search-surface list VM. On the single-host path the duck.ai surface adds its own
    /// (see `duckAIListViewModel`); the view picks between them by content kind.
    let listViewModel: SuggestionsListViewModel
    /// Present only on the single-host path once the duck.ai surface is attached. `.list(.duckAI)`
    /// and `.list(.recents)` render this; `.list(.search)` renders `listViewModel`.
    private(set) var duckAIListViewModel: SuggestionsListViewModel?
    /// Stable empty list for `.list(.duckAI|.recents)` when no duck.ai surface is attached
    /// (suggestions disabled / pre-attach) — keeps the list mounted without showing Search rows.
    private let emptyListViewModel = SuggestionsListViewModel(source: EmptySuggestionsSource())

    private var cancellable: AnyCancellable?
    private var previousMode: TextEntryMode?
    /// Cleared on each focus; the first resolve after that snaps the logo to its mode instead of
    /// morphing, so a refocus never replays a stale Duck.ai→search morph from the prior session.
    private var hasResolvedSinceActivation = false

    init(inputsPublisher: AnyPublisher<UnifiedSuggestionsInputs, Never>,
         listViewModel: SuggestionsListViewModel,
         duckAIListViewModel: SuggestionsListViewModel? = nil) {
        self.listViewModel = listViewModel
        self.duckAIListViewModel = duckAIListViewModel
        cancellable = inputsPublisher
            .sink { [weak self] inputs in
                guard let self else { return }
                // While the host is fading out, freeze the resolved content: a mid-collapse text-clear
                // would otherwise flip the fading list to a spurious logo (briefly visible in the fade
                // tail). Unfreezes on the next focus.
                guard self.dismissBehavior != .fadeOut else { return }
                let resolved = UnifiedSuggestionsContentResolver.resolve(inputs, previous: self.content)
                // Morph-home pins the logo to the Dax mark for the collapse; all other resolves drive its
                // mark/morph (see `FocusedLogoModel`).
                if self.dismissBehavior != .morphHome {
                    self.logoModel.update(wasLogo: self.content == .logo,
                                          isLogo: resolved == .logo,
                                          isDuckAI: inputs.mode == .aiChat,
                                          isFirstSinceActivation: !self.hasResolvedSinceActivation)
                }
                self.hasResolvedSinceActivation = true
                self.apply(resolved, modeChanged: inputs.mode != self.previousMode)
                self.previousMode = inputs.mode
            }
    }

    /// Crossfades only when a mode switch changes the content *type* (e.g. favorites↔recents,
    /// list↔logo). List↔list keeps the mounted list, and same-mode changes (typing, deletions)
    /// stay snappy. When the sync promo is showing, snap instead — crossfading the recents under the
    /// collapsing promo card makes them flash over its space.
    private func apply(_ newContent: UnifiedSuggestionsContentKind, modeChanged: Bool) {
        guard newContent != content else { return }
        if modeChanged && !Self.sameCategory(content, newContent) && !showsSyncPromo {
            withAnimation(.easeInOut(duration: 0.2)) { content = newContent }
        } else {
            content = newContent
        }
    }

    private static func sameCategory(_ lhs: UnifiedSuggestionsContentKind, _ rhs: UnifiedSuggestionsContentKind) -> Bool {
        switch (lhs, rhs) {
        case (.list, .list), (.favorites, .favorites), (.logo, .logo): return true
        default: return false
        }
    }

    var isShowingLogo: Bool { content == .logo }

    var isShowingFavorites: Bool {
        if case .favorites = content { return true }
        return false
    }

    /// True while the focused content is fading out (drives `DismissFade`).
    var isFadingOut: Bool { dismissBehavior == .fadeOut }

    /// List/logo→favorites (or recents) collapse: fade the focused content out.
    func beginDismissFade() {
        dismissBehavior = .fadeOut
    }

    /// Logo→logo collapse: morph the focused logo back to the Dax mark and keep it visible (no fade).
    /// `collapseDuration` is the bar's collapse time — the morph is sped up to finish within it.
    func morphLogoHomeForDismiss(matching collapseDuration: TimeInterval) {
        dismissBehavior = .morphHome
        logoModel.morphToDax(matching: collapseDuration)
    }

    /// Resets the dismiss state on each focus so the next session starts clean. The reset snaps
    /// (`DismissFade` only animates the fade-out), so it never replays a fade-in as the logo reappears.
    func prepareForActivation() {
        dismissBehavior = .none
        hasResolvedSinceActivation = false
    }

    func setDuckAIListViewModel(_ viewModel: SuggestionsListViewModel?) {
        duckAIListViewModel = viewModel
    }

    /// Resolves the list VM for a `.list` content kind. Duck.ai kinds fall back to a stable empty
    /// list (never the Search VM) when no duck.ai surface is attached, so Search rows never render
    /// in Duck.ai mode.
    func listViewModel(for kind: SuggestionsListSourceKind) -> SuggestionsListViewModel {
        switch kind {
        case .search:
            return listViewModel
        case .duckAI, .recents:
            return duckAIListViewModel ?? emptyListViewModel
        }
    }
}
