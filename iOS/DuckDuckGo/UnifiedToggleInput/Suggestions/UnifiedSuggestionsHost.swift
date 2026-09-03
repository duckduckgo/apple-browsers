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
import DesignResourcesKit
import SwiftUI
import UIKit

private final class UnifiedSuggestionsHostingController: UIHostingController<UnifiedSuggestionsView> {

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard let listScrollView = firstScrollView(in: view) else { return }
        // `.scrollContentBackground(.hidden)` leaves the native List backing view with its system
        // background. Keep that layer semantic when SwiftUI reconfigures the List during a mode switch.
        listScrollView.backgroundColor = UIColor(designSystemColor: .background)

        if #available(iOS 16, *) { return }
        guard let tableView = listScrollView as? UITableView else { return }
        // Match AutocompleteView's legacy insetGrouped top compensation.
        var contentInset = tableView.contentInset
        guard contentInset.top != -28 else { return }
        contentInset.top = -28
        tableView.contentInset = contentInset
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let scrollView = firstScrollView(in: subview) { return scrollView }
        }
        return nil
    }
}

/// Hosts the SwiftUI `UnifiedSuggestionsView` for any UTI surface (Duck.ai, Search). Parameterized
/// by `UnifiedSuggestionsHostConfig` so the host is surface-agnostic. The empty-state logo and fire
/// screen render inside the view.
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
    private var logoHostingController: UIHostingController<UnifiedSuggestionsLogoView>?
    private var escapeHatch: EscapeHatchModel?
    private var contentInsets: UIEdgeInsets = .zero
    private var usesHostingTopInsetForDismissal = false
    private var cancellables = Set<AnyCancellable>()

    /// Single-host path only: the duck.ai surface's source/VM, attached lazily and detached on
    /// disappear (mirrors the legacy per-host lifecycle). Nil on the old single-surface path.
    private var duckAISurface: UnifiedSuggestionsDuckAISurface?

    func setEscapeHatch(_ model: EscapeHatchModel?) {
        guard escapeHatch !== model else { return }
        escapeHatch = model
        rebuildRootView()
    }

    func refreshMessages() {
        config.messagesModel.refresh()
    }

    func setSyncPromo(_ promo: AnyView?) {
        viewModel.setSyncPromo(promo)
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
                             logoContainerView: UIView,
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
            isFloatingUIEnabled: config.isFloatingUIEnabled,
            dismissKeyboardOnRestingContentScroll: config.dismissKeyboardOnRestingContentScroll,
            escapeHatch: escapeHatch,
            favoritesViewModel: config.favoritesViewModel,
            messagesModel: config.messagesModel)
        let hosting = UnifiedSuggestionsHostingController(rootView: view)
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

        let logo = UIHostingController(rootView: UnifiedSuggestionsLogoView(viewModel: viewModel,
                                                                            escapeHatch: escapeHatch))
        logo.view.backgroundColor = .clear
        logo.view.isUserInteractionEnabled = false
        logo.view.translatesAutoresizingMaskIntoConstraints = false
        parentViewController.addChild(logo)
        logoContainerView.addSubview(logo.view)
        NSLayoutConstraint.activate([
            logo.view.leadingAnchor.constraint(equalTo: logoContainerView.leadingAnchor),
            logo.view.trailingAnchor.constraint(equalTo: logoContainerView.trailingAnchor),
            logo.view.topAnchor.constraint(equalTo: logoContainerView.topAnchor),
            logo.view.bottomAnchor.constraint(equalTo: logoContainerView.keyboardLayoutGuide.topAnchor)
        ])
        logo.didMove(toParent: parentViewController)
        logoHostingController = logo
    }

    var isShowingLogo: Bool {
        viewModel.isShowingLogo
            && !viewModel.isFireTab
            && !viewModel.isLandscape
    }
    var isShowingFavorites: Bool { viewModel.isShowingFavorites }

    var isShowingRecentChatsWithoutEscapeHatch: Bool {
        guard escapeHatch == nil else { return false }
        if case .list(.recents) = viewModel.content { return true }
        return false
    }

    /// Fire tabs render the fire empty state instead of the Dax logo for the empty (`.logo`) state.
    func setIsFireTab(_ value: Bool) {
        guard viewModel.isFireTab != value else { return }
        viewModel.setFireTab(value)
        applyCombinedInsets()
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
        if usesHostingTopInsetForDismissal {
            usesHostingTopInsetForDismissal = false
            applyCombinedInsets()
        }
        viewModel.prepareForActivation()
    }

    func prepareForDismissAnimation() {
        guard #available(iOS 17, *), !viewModel.isFireTab, !usesHostingTopInsetForDismissal else { return }
        usesHostingTopInsetForDismissal = true
        applyCombinedInsets()
    }

    /// Updates the tap-ahead arrow direction to match the UTI's current position.
    func setIsAddressBarAtBottom(_ value: Bool) {
        guard isAddressBarAtBottom != value else { return }
        isAddressBarAtBottom = value
        rebuildRootView()
    }

    /// Insets the List content without shrinking its viewport, allowing rows to scroll beneath the top UTI.
    func setContentInsets(_ insets: UIEdgeInsets) {
        guard contentInsets != insets else { return }
        contentInsets = insets
        applyCombinedInsets()
    }

    private func applyCombinedInsets() {
        let hostingTopInset: CGFloat
        if #available(iOS 17, *) {
            // Keep a self-sizing List's adjustedContentInset stable while its rows change.
            let usesHostingTopInset = viewModel.isFireTab || usesHostingTopInsetForDismissal
            hostingTopInset = usesHostingTopInset ? contentInsets.top : 0
            let scrollContentInsetTop = usesHostingTopInset ? 0 : contentInsets.top
            if viewModel.scrollContentInsetTop != scrollContentInsetTop {
                viewModel.scrollContentInsetTop = scrollContentInsetTop
            }
        } else {
            hostingTopInset = contentInsets.top
        }
        let hostingInsets = UIEdgeInsets(
            top: hostingTopInset,
            left: contentInsets.left,
            bottom: contentInsets.bottom,
            right: contentInsets.right
        )
        let logoInsets = UIEdgeInsets(
            top: 0,
            left: contentInsets.left,
            bottom: contentInsets.bottom,
            right: contentInsets.right
        )
        if let hostingController, hostingController.additionalSafeAreaInsets != hostingInsets {
            hostingController.additionalSafeAreaInsets = hostingInsets
            hostingController.view.layoutIfNeeded()
        }
        if let logoHostingController, logoHostingController.additionalSafeAreaInsets != logoInsets {
            logoHostingController.additionalSafeAreaInsets = logoInsets
            logoHostingController.view.layoutIfNeeded()
        }
    }

    func setLogoChromeInsetTop(_ top: CGFloat) {
        guard viewModel.chromeInsetTop != top else { return }
        viewModel.chromeInsetTop = top
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
        logoHostingController?.willMove(toParent: nil)
        logoHostingController?.view.removeFromSuperview()
        logoHostingController?.removeFromParent()
        logoHostingController = nil
    }

    // MARK: - Private

    private func rebuildRootView() {
        guard let hosting = hostingController else { return }
        hosting.rootView = UnifiedSuggestionsView(
            viewModel: viewModel,
            isAddressBarAtBottom: isAddressBarAtBottom,
            isFloatingUIEnabled: config.isFloatingUIEnabled,
            dismissKeyboardOnRestingContentScroll: config.dismissKeyboardOnRestingContentScroll,
            escapeHatch: escapeHatch,
            favoritesViewModel: config.favoritesViewModel,
            messagesModel: config.messagesModel)
        logoHostingController?.rootView = UnifiedSuggestionsLogoView(viewModel: viewModel,
                                                                     escapeHatch: escapeHatch)
    }
}
