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
import UIKit

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

    struct LogoModeChange: Equatable {
        struct Source: Equatable {
            let frame: CGRect
            let progress: CGFloat
        }

        let mode: TextEntryMode
        var source: Source?
        var isFadingOut = false
    }

    @Published private(set) var content: UnifiedSuggestionsContentKind = .logo
    /// True when the last content change was a mode switch away from a logo on screen, which fades out
    /// before the incoming content appears.
    @Published private(set) var waitsForLogoFadeOut = false
    /// The empty-state logo's presentation (mark / morph / speed). All its transitions are pure, so
    /// the morph rules are tested in `FocusedLogoModelTests`.
    @Published private(set) var logoModel = FocusedLogoModel()
    @Published private(set) var logoModeChange: LogoModeChange?
    @Published private(set) var isPreparingLogoModeChange = false
    var onLogoFadeOutCompleted: (() -> Void)?
    var usesRedesignedNewTabPageLayout = false
    /// How the content collapses back to the omnibar. Cleared on the next focus.
    @Published private(set) var dismissBehavior: DismissBehavior = .none
    /// On a fire tab the empty state is the fire screen, not the Dax logo. Set by the container via
    /// `setFireTab` (which no-ops on an unchanged value, so repeated per-focus sets don't invalidate
    /// the view body).
    @Published private(set) var isFireTab = false
    /// iPhone landscape suppresses the empty state entirely because there is not enough room.
    @Published private(set) var isLandscape = false
    @Published private(set) var escapeHatchPlacement: FocusedContentPlacement = .hidden
    @Published private(set) var embeddedEscapeHatchGeometry: EmbeddedEscapeHatchGeometry?
    var embeddedEscapeHatchFrame: CGRect? { embeddedEscapeHatchGeometry?.frame }
    var embeddedEscapeHatchDestinationFrame: CGRect? {
        embeddedEscapeHatchGeometry?.destinationFrame(contentTopInset: contentTopInset)
    }
    /// The displayed logo's frame while it sits beside the escape hatch, so the hatch can blur it when scrolled over it.
    @Published var backdropLogoFrame: CGRect?
    @Published var isLogoRevealDeferred = false
    /// Chrome bottom (bar + reserved hatch) below the host top, pushed by the container as the bar
    /// animates. The logo keeps a minimum distance from it — known *during* the resize, so the logo
    /// moves in the same pass, and only when the chrome is actually close (never in Search).
    @Published var chromeInsetTop: CGFloat = 0 { didSet { updateLogoModeChange() } }
    @Published var contentTopInset: CGFloat = 0 { didSet { updateLogoModeChange() } }
    /// Floating chrome clearance comes from UIKit's keyboard-bounded host, independently of
    /// SwiftUI's transient coordinate origins during the omnibar handoff.
    @Published var logoViewportFrame: CGRect? { didSet { updateLogoModeChange() } }
    @Published var logoHostFrame: CGRect? { didSet { updateLogoModeChange() } }
    /// The search-surface list VM. On the single-host path the duck.ai surface adds its own
    /// (see `duckAIListViewModel`); the view picks between them by content kind.
    let listViewModel: SuggestionsListViewModel
    /// Present only on the single-host path once the duck.ai surface is attached. `.list(.duckAI)`
    /// and `.list(.recents)` render this; `.list(.search)` renders `listViewModel`.
    private(set) var duckAIListViewModel: SuggestionsListViewModel?
    /// Stable empty list for `.list(.duckAI|.recents)` when no duck.ai surface is attached
    /// (suggestions disabled / pre-attach) — keeps the list mounted without showing Search rows.
    private let emptyListViewModel = SuggestionsListViewModel(source: EmptySuggestionsSource())

    /// Called once per focus, the first time the Duck.ai list is on screen with rows in it.
    var onDuckAISuggestionsShown: (() -> Void)?

    private var cancellable: AnyCancellable?
    private var duckAISectionsCancellable: AnyCancellable?
    private var hasReportedDuckAISuggestionsShown = false
    private var previousMode: TextEntryMode?
    private var logoModeChangeCancellable: AnyCancellable?
    private var logoModeChangeGeneration = 0
    /// Cleared on each focus; the first resolve after that snaps the logo to its mode instead of
    /// morphing, so a refocus never replays a stale Duck.ai→search morph from the prior session.
    private var hasResolvedSinceActivation = false

    init(inputsPublisher: AnyPublisher<UnifiedSuggestionsInputs, Never>,
         listViewModel: SuggestionsListViewModel,
         duckAIListViewModel: SuggestionsListViewModel? = nil) {
        self.listViewModel = listViewModel
        self.duckAIListViewModel = duckAIListViewModel
        observeDuckAISections(of: duckAIListViewModel)
        cancellable = inputsPublisher
            .sink { [weak self] inputs in
                guard let self else { return }
                // Freeze while the host is collapsing (fade-out OR morph-home): a mid-collapse input
                // (text clear, mode change) would otherwise swap `content`/the logo out from under the
                // handoff — a fading list flipping to a spurious logo, or morph-home drifting off `.logo`.
                // Unfreezes on the next focus.
                guard self.dismissBehavior == .none else { return }
                let resolved = UnifiedSuggestionsContentResolver.resolve(inputs, previous: self.content)
                let isModeSwitch = self.hasResolvedSinceActivation && inputs.mode != self.previousMode
                if !isModeSwitch, !self.isPreparingLogoModeChange, self.logoModeChange?.mode == inputs.mode, resolved != self.content {
                    self.cancelLogoModeChange()
                }
                if isModeSwitch { self.prepareLogoModeChange(to: inputs.mode) }
                // A logo hidden beside the hatch for lack of room has no mark on screen to morph from.
                let wasLogoVisible = self.isLogoOnScreen
                self.logoModel.update(wasLogo: wasLogoVisible,
                                      isLogo: resolved == .logo,
                                      isDuckAI: inputs.mode == .aiChat,
                                      isFirstSinceActivation: !self.hasResolvedSinceActivation)
                // A focus in another mode than the last session is not a switch the user watches, so it snaps.
                self.hasResolvedSinceActivation = true
                self.apply(resolved, modeChanged: isModeSwitch, wasLogoVisible: wasLogoVisible)
                self.previousMode = inputs.mode
                self.updateLogoModeChange()
                self.reportDuckAISuggestionsShownIfNeeded(hasDuckAIRows: self.duckAIListViewModel?.sections.isEmpty == false)
            }
    }

    private var isShowingDuckAIList: Bool {
        content == .list(.duckAI) || content == .list(.recents)
    }

    private func reportDuckAISuggestionsShownIfNeeded(hasDuckAIRows: Bool) {
        guard !hasReportedDuckAISuggestionsShown, dismissBehavior == .none, isShowingDuckAIList, hasDuckAIRows else { return }
        hasReportedDuckAISuggestionsShown = true
        onDuckAISuggestionsShown?()
    }

    private func observeDuckAISections(of viewModel: SuggestionsListViewModel?) {
        duckAISectionsCancellable = viewModel?.$sections
            .sink { [weak self] sections in
                self?.reportDuckAISuggestionsShownIfNeeded(hasDuckAIRows: !sections.isEmpty)
            }
    }

    /// Crossfades only when a mode switch changes the content *type* (e.g. favorites↔recents,
    /// list↔logo). List↔list keeps the mounted list, and same-mode changes (typing, deletions)
    /// stay snappy.
    private func apply(_ newContent: UnifiedSuggestionsContentKind, modeChanged: Bool, wasLogoVisible: Bool = false) {
        guard newContent != content else { return }
        let crossfades = modeChanged && !Self.sameCategory(content, newContent)
        waitsForLogoFadeOut = crossfades && wasLogoVisible && !usesRedesignedNewTabPageLayout
        if crossfades {
            withAnimation(FocusedContentFade.fadeIn) { content = newContent }
        } else {
            content = newContent
        }
    }

    func logoLayout(in viewport: CGRect) -> FocusedLogoLayout {
        FocusedLogoLayout(viewport: viewport, chromeInsetTop: chromeInsetTop, placement: escapeHatchPlacement,
                          hatchFrame: embeddedEscapeHatchFrame, destinationHatchFrame: embeddedEscapeHatchDestinationFrame,
                          restingCenterY: UIScreen.main.bounds.midY - FocusedLogoLayout.screenCenterOffset)
    }

    func prepareLogoModeChange(to mode: TextEntryMode) {
        guard hasResolvedSinceActivation, mode != previousMode, logoModeChange?.mode != mode else { return }
        let source: LogoModeChange.Source?
        if let change = logoModeChange, change.isFadingOut {
            source = change.source
        } else if isLogoOnScreen, !isLogoRevealDeferred, !isFireTab, !isLandscape,
                  let frame = backdropLogoFrame ?? (logoViewportFrame ?? logoHostFrame).map({ logoLayout(in: $0).frame }) {
            source = .init(frame: frame, progress: logoModel.progress)
        } else {
            source = nil
        }
        logoModeChangeGeneration += 1
        logoModeChangeCancellable = nil
        let completion = onLogoFadeOutCompleted
        onLogoFadeOutCompleted = nil
        completion?()
        logoModeChange = LogoModeChange(mode: mode, source: source)
        let generation = logoModeChangeGeneration
        logoModeChangeCancellable = Just(()).delay(for: .seconds(0.25), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard self?.logoModeChangeGeneration == generation, self?.logoModeChange?.isFadingOut == false else { return }
                self?.logoModeChange?.source = nil
            }
    }

    func performLogoModeChange(to mode: TextEntryMode, _ changes: () -> Void) {
        prepareLogoModeChange(to: mode)
        isPreparingLogoModeChange = true
        changes()
        updateLogoModeChange(finishingPreparation: true)
    }

    private func updateLogoModeChange(finishingPreparation: Bool = false) {
        guard !isPreparingLogoModeChange || finishingPreparation else { return }
        defer {
            if finishingPreparation && isPreparingLogoModeChange { isPreparingLogoModeChange = false }
        }
        guard !usesRedesignedNewTabPageLayout,
              let change = logoModeChange, change.source != nil, !change.isFadingOut else { return }
        let fits = (logoViewportFrame ?? logoHostFrame).map { viewport in
            let layout = logoLayout(in: viewport)
            return layout.hatchLayout == nil || layout.hatchLayout?.visibleFrame != nil
        } ?? true
        guard !isShowingLogo || !fits else { return }
        let updates = {
            self.logoModeChange?.isFadingOut = true
            self.waitsForLogoFadeOut = true
            if finishingPreparation { self.isPreparingLogoModeChange = false }
        }
        guard onLogoFadeOutCompleted != nil else {
            updates()
            return
        }
        let generation = logoModeChangeGeneration
        let completion: () -> Void = { [weak self] in self?.finishLogoFadeOut(generation: generation) }
        if #available(iOS 17, *) {
            withAnimation(FocusedContentFade.fadeOut, completionCriteria: .logicallyComplete, updates) { completion() }
        } else {
            updates()
        }
    }

    func startLogoFadeOut() {
        if #available(iOS 17, *), onLogoFadeOutCompleted != nil { return }
        guard logoModeChange?.isFadingOut == true, logoModeChange?.source != nil else { return }
        let generation = logoModeChangeGeneration
        logoModeChangeCancellable = Just(()).delay(for: .seconds(FocusedContentFade.duration), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.finishLogoFadeOut(generation: generation)
            }
    }

    private func finishLogoFadeOut(generation: Int) {
        guard generation == logoModeChangeGeneration else { return }
        let completion = onLogoFadeOutCompleted
        onLogoFadeOutCompleted = nil
        logoModeChangeCancellable = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            logoModeChange?.source = nil
            logoModeChange?.isFadingOut = false
            waitsForLogoFadeOut = false
        }
        completion?()
    }

    func cancelLogoModeChange() {
        logoModeChangeGeneration += 1
        logoModeChangeCancellable = nil
        let completion = onLogoFadeOutCompleted
        onLogoFadeOutCompleted = nil
        logoModeChange = nil
        waitsForLogoFadeOut = false
        completion?()
    }

    private static func sameCategory(_ lhs: UnifiedSuggestionsContentKind, _ rhs: UnifiedSuggestionsContentKind) -> Bool {
        switch (lhs, rhs) {
        case (.list, .list), (.favorites, .favorites), (.logo, .logo): return true
        default: return false
        }
    }

    var isShowingLogo: Bool { content == .logo }

    /// Beside a hatch, a logo is on screen only while it has a backdrop frame; without a hatch it always is.
    var isLogoOnScreen: Bool {
        (logoModeChange?.isFadingOut == true && logoModeChange?.source != nil)
            || (content == .logo && (escapeHatchPlacement == .hidden || backdropLogoFrame != nil))
    }

    var isShowingFavorites: Bool {
        if case .favorites = content { return true }
        return false
    }

    /// True while the focused content is fading out (drives `FocusedContentDismissFade`).
    var isFadingOut: Bool { dismissBehavior == .fadeOut }

    /// List/logo→favorites (or recents) collapse: fade the focused content out.
    func beginDismissFade() {
        cancelLogoModeChange()
        dismissBehavior = .fadeOut
    }

    /// Logo→logo collapse: morph the focused logo back to the Dax mark and keep it visible (no fade).
    /// `collapseDuration` is the bar's collapse time — the morph is sped up to finish within it.
    func morphLogoHomeForDismiss(matching collapseDuration: TimeInterval) {
        cancelLogoModeChange()
        dismissBehavior = .morphHome
        logoModel.morphToDax(matching: collapseDuration)
    }

    /// Resets the dismiss state on each focus so the next session starts clean. The reset snaps
    /// (`FocusedContentDismissFade` only animates the fade-out), so it never replays a fade-in as the logo reappears.
    func prepareForActivation() {
        cancelLogoModeChange()
        dismissBehavior = .none
        hasResolvedSinceActivation = false
        hasReportedDuckAISuggestionsShown = false
    }

    /// No-ops on an unchanged value so repeated per-focus sets don't invalidate the view body.
    func setFireTab(_ value: Bool) {
        guard isFireTab != value else { return }
        isFireTab = value
    }

    /// No-ops on an unchanged value (see `setFireTab`).
    func setLandscape(_ value: Bool) {
        guard isLandscape != value else { return }
        isLandscape = value
    }

    func setEscapeHatchPlacement(_ value: FocusedContentPlacement) {
        guard escapeHatchPlacement != value else { return }
        escapeHatchPlacement = value
        setEmbeddedEscapeHatchGeometry(nil)
    }

    func setEmbeddedEscapeHatchGeometry(_ geometry: EmbeddedEscapeHatchGeometry?) {
        guard geometry == nil || escapeHatchPlacement == .embedded else { return }
        let geometry = geometry.flatMap { $0.frame.isEmpty ? nil : $0 }
        guard embeddedEscapeHatchGeometry != geometry else { return }
        embeddedEscapeHatchGeometry = geometry
        updateLogoModeChange()
    }

    func setDuckAIListViewModel(_ viewModel: SuggestionsListViewModel?) {
        duckAIListViewModel = viewModel
        observeDuckAISections(of: viewModel)
    }

    /// Resolves the list VM for a `.list` content kind. Duck.ai kinds fall back to a stable empty
    /// list (never the Search VM) when no duck.ai surface is attached, so Search rows never render
    /// in Duck.ai mode.
    func listViewModel(for kind: SuggestionsListSourceKind) -> SuggestionsListViewModel {
        switch kind {
        case .search:
            return listViewModel
        case .recents where content != .list(.recents):
            return emptyListViewModel
        case .duckAI, .recents:
            return duckAIListViewModel ?? emptyListViewModel
        }
    }
}
