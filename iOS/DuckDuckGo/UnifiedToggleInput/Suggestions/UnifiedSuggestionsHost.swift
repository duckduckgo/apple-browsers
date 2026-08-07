//
//  UnifiedSuggestionsHost.swift
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
import SwiftUI
import UIKit

/// Hosts the SwiftUI `UnifiedSuggestionsView` for any UTI surface (Duck.ai, Search). Parameterized
/// by `UnifiedSuggestionsHostConfig` so the host is surface-agnostic. The empty-state logo and fire
/// screen render inside the view; the host no longer touches `DaxLogoManager`.
@MainActor
final class UnifiedSuggestionsHost {

    var onContentChanged: (() -> Void)?

    private let config: UnifiedSuggestionsHostConfig
    private let listViewModel: SuggestionsListViewModel
    private let viewModel: UnifiedSuggestionsViewModel
    /// Tap-ahead arrow direction follows the UTI's live position, so it's mutable (not just the
    /// config's install-time value, which is stale once the bar position is finalized).
    private var isAddressBarAtBottom: Bool
    private var hostingController: UIHostingController<UnifiedSuggestionsView>?
    private var escapeHatchTopInset: CGFloat = 0
    private var contentInsets: UIEdgeInsets = .zero
    private var cancellables = Set<AnyCancellable>()
    /// Built once on first `.favorites` render; NTP has a heavy init, so don't rebuild per body pass.
    private var cachedFavoritesController: NewTabPageViewController?

    /// Single-host path only: the duck.ai surface's source/VM, attached lazily and detached on
    /// disappear (mirrors the legacy per-host lifecycle). Nil on the old single-surface path.
    private var duckAISurface: UnifiedSuggestionsDuckAISurface?

    private func memoizedFavoritesController() -> NewTabPageViewController? {
        if let cachedFavoritesController { return cachedFavoritesController }
        cachedFavoritesController = config.favoritesProvider()
        return cachedFavoritesController
    }

    func updateOpenedAfterIdle(_ openedAfterIdle: Bool) {
        cachedFavoritesController?.setOpenedAfterIdle(openedAfterIdle)
    }

    init(config: UnifiedSuggestionsHostConfig) {
        self.config = config
        self.isAddressBarAtBottom = config.isAddressBarAtBottom
        self.listViewModel = SuggestionsListViewModel(source: config.source)
        self.viewModel = UnifiedSuggestionsViewModel(
            inputsPublisher: config.inputsPublisher,
            listViewModel: listViewModel
        )
    }

    // MARK: - Container-facing surface

    func start<P: Publisher>(in containerView: UIView,
                             parentViewController: UIViewController,
                             textPublisher: P) where P.Output == String, P.Failure == Never {
        guard hostingController == nil else { return }

        config.source.start(textPublisher: textPublisher.eraseToAnyPublisher())

        listViewModel.onSelect = { [weak self] id in self?.config.onSelectRow(id) }
        listViewModel.onTapAhead = { [weak self] id in self?.config.onTapAheadRow(id) }
        listViewModel.onDelete = { [weak self] id in self?.config.onDeleteRow(id) }

        viewModel.$content
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.onContentChanged?() }
            .store(in: &cancellables)

        let view = UnifiedSuggestionsView(
            viewModel: viewModel,
            isAddressBarAtBottom: isAddressBarAtBottom,
            favoritesProvider: { [weak self] in self?.memoizedFavoritesController() })
        let hosting = UIHostingController(rootView: view)
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        parentViewController.addChild(hosting)
        containerView.addSubview(hosting.view)
        // The SwiftUI List needs a definite height or it collapses; pin the bottom to the
        // keyboard guide (mirrors the legacy DuckAISuggestionsViewController table pinning).
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: containerView.keyboardLayoutGuide.topAnchor)
        ])
        hosting.didMove(toParent: parentViewController)
        hostingController = hosting
    }

    var isShowingLogo: Bool { viewModel.isShowingLogo }
    var isShowingFavorites: Bool { viewModel.isShowingFavorites }

    /// Fire tabs render the fire empty state instead of the Dax logo for the empty (`.logo`) state.
    func setIsFireTab(_ value: Bool) {
        viewModel.setFireTab(value)
    }

    /// iPhone landscape suppresses the empty state (no room) — matches the unfocused NTP.
    func setLandscape(_ value: Bool) {
        viewModel.setLandscape(value)
    }

    /// List/logo→favorites collapse: fade the focused content out as the NTP content takes over.
    func beginDismissFade() {
        viewModel.beginDismissFade()
    }

    /// Logo→logo collapse: morph the focused logo to the Dax mark and keep it visible (no fade),
    /// sped up to finish within the bar's `collapseDuration`.
    func morphLogoHomeForDismiss(matching collapseDuration: TimeInterval) {
        viewModel.morphLogoHomeForDismiss(matching: collapseDuration)
    }

    /// Resets the dismiss/morph state on each focus.
    func prepareForActivation() {
        viewModel.prepareForActivation()
    }

    func setAdditionalTopInset(_ inset: CGFloat) {
        escapeHatchTopInset = inset
        applyCombinedInsets()
    }


    /// Updates the tap-ahead arrow direction to match the UTI's current position.
    func setIsAddressBarAtBottom(_ value: Bool) {
        guard isAddressBarAtBottom != value else { return }
        isAddressBarAtBottom = value
        rebuildRootView()
    }

    /// Single-host path: the content inset the container would otherwise set on the swipe-container
    /// parent VC. Combined with the escape-hatch inset since there's no intermediate container here.
    func setContentInsets(_ insets: UIEdgeInsets) {
        contentInsets = insets
        applyCombinedInsets()
    }

    private func applyCombinedInsets() {
        let top = escapeHatchTopInset + contentInsets.top
        viewModel.chromeInsetTop = top
        hostingController?.additionalSafeAreaInsets = UIEdgeInsets(
            top: top,
            left: contentInsets.left,
            bottom: contentInsets.bottom,
            right: contentInsets.right
        )
        // Flush the safe-area change on the controller whose insets changed (mirrors the legacy
        // container's layoutIfNeeded) so the content glides inside the UTI's height animation.
        hostingController?.view.layoutIfNeeded()
    }

    // MARK: - Duck.ai surface (single-host path)

    /// Attaches the duck.ai source + its own list VM so `.list(.duckAI|.recents)` rows render
    /// duck.ai data. Lazy: called when the duck.ai surface becomes available; safe to call once.
    func attachDuckAISurface(_ surface: UnifiedSuggestionsDuckAISurface,
                             textPublisher: AnyPublisher<String, Never>) {
        guard duckAISurface == nil else { return }
        duckAISurface = surface

        let listVM = SuggestionsListViewModel(source: surface.source)
        listVM.onSelect = { surface.onSelectRow($0) }
        listVM.onTapAhead = { surface.onTapAheadRow($0) }
        listVM.onDelete = { surface.onDeleteRow($0) }
        listVM.onFireDelete = { id, _ in surface.onFireDeleteRow(id) }
        viewModel.setDuckAIListViewModel(listVM)

        surface.source.start(textPublisher: textPublisher)
        rebuildRootView()
    }

    /// Releases the duck.ai source/VM only (search persists), mirroring today's lazy lifecycle.
    func detachDuckAISurface() {
        duckAISurface?.source.tearDown()
        duckAISurface = nil
        viewModel.setDuckAIListViewModel(nil)
        rebuildRootView()
    }

    func tearDown() {
        cancellables.removeAll()
        onContentChanged = nil
        config.source.tearDown()
        duckAISurface?.source.tearDown()
        duckAISurface = nil
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        hostingController = nil
    }

    // MARK: - Private

    private func rebuildRootView() {
        guard let hosting = hostingController else { return }
        hosting.rootView = UnifiedSuggestionsView(
            viewModel: viewModel,
            isAddressBarAtBottom: isAddressBarAtBottom,
            favoritesProvider: { [weak self] in self?.memoizedFavoritesController() })
    }
}
