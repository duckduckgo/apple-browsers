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
import os.log

/// Hosts the SwiftUI `UnifiedSuggestionsView` for any UTI surface (Duck.ai, Search). Parameterized
/// by `UnifiedSuggestionsHostConfig` so the host is surface-agnostic. The empty-state logo and fire
/// screen render inside the view.
@MainActor
final class UnifiedSuggestionsHost {

    var onContentChanged: (() -> Void)?

    private let config: UnifiedSuggestionsHostConfig
    private let usesScrollableEscapeHatch: Bool
    private let listViewModel: SuggestionsListViewModel
    private let viewModel: UnifiedSuggestionsViewModel
    /// Tap-ahead arrow direction follows the UTI's live position, so it's mutable (not just the
    /// config's install-time value, which is stale once the bar position is finalized).
    private var isAddressBarAtBottom: Bool
    private var hostingController: UIHostingController<UnifiedSuggestionsView>?
    private var escapeHatchTopInset: CGFloat = 0
    private var escapeHatch: EscapeHatchModel?
    private var focusedMode: TextEntryMode = .search
    private var syncPromo: AnyView?
    private var contentInsets: UIEdgeInsets = .zero
    private var embeddedHatchInset: CGFloat = 0
    private var cancellables = Set<AnyCancellable>()
    let favoritesPresentation: FocusedFavoritesPresentation
    private var redesignedSearchPresentation: RedesignedFocusedSearchPresentation?
    private var redesignedPresentationCancellable: AnyCancellable?
    private var showsRedesignedSearchModules = false

    /// Single-host path only: the duck.ai surface's source/VM, attached lazily and detached on
    /// disappear (mirrors the legacy per-host lifecycle). Nil on the old single-surface path.
    private var duckAISurface: UnifiedSuggestionsDuckAISurface?

    var isShowingRedesignedSearchModules: Bool { showsRedesignedSearchModules }

    func setEscapeHatch(_ model: EscapeHatchModel?) {
        guard escapeHatch !== model else { return }
        escapeHatch = model
        rebuildRootView()
    }

    func updateOpenedAfterIdle(_ openedAfterIdle: Bool) {
        favoritesPresentation.updateOpenedAfterIdle(openedAfterIdle)
    }

    func setFocusedContent(mode: TextEntryMode, escapeHatch: EscapeHatchModel?, syncPromo: AnyView?) {
        focusedMode = mode
        if usesScrollableEscapeHatch {
            self.escapeHatch = escapeHatch
        }
        self.syncPromo = syncPromo
        if redesignedSearchPresentation == nil, usesScrollableEscapeHatch {
            favoritesPresentation.viewController?.setFocusedContent(LegacyFocusedNewTabPageContent(
                recentChats: mode == .aiChat ? viewModel.listViewModel(for: .recents) : nil,
                syncPromo: syncPromo,
                isAddressBarAtBottom: isAddressBarAtBottom), escapeHatch: escapeHatch)
        } else {
            if redesignedSearchPresentation == nil {
                favoritesPresentation.viewController?.setFocusedContent(nil)
            }
            rebuildRootView()
        }
        let hatchPadding = redesignedSearchPresentation == nil ? 0 : EscapeHatchView.materialPadding * 2
        embeddedHatchInset = !usesScrollableEscapeHatch || escapeHatch == nil ? 0 : 10 + TabSwitcherPill.compactSize + hatchPadding
        applyCombinedInsets()
    }

    func scrollLegacyContentToTop(duration: TimeInterval) {
        guard usesScrollableEscapeHatch, redesignedSearchPresentation == nil else { return }
        favoritesPresentation.viewController?.scrollToTop(duration: duration)
    }

    init(config: UnifiedSuggestionsHostConfig, usesScrollableEscapeHatch: Bool = true) {
        self.config = config
        self.usesScrollableEscapeHatch = usesScrollableEscapeHatch
        self.favoritesPresentation = FocusedFavoritesPresentation(makeViewController: config.favoritesProvider)
        self.isAddressBarAtBottom = config.isAddressBarAtBottom
        self.listViewModel = SuggestionsListViewModel(source: config.source)
        self.viewModel = UnifiedSuggestionsViewModel(
            inputsPublisher: config.inputsPublisher,
            listViewModel: listViewModel
        )
        viewModel.onDuckAISuggestionsShown = { AutocompleteSuggestionsPixels().fireDuckAIShownPixel() }
    }

    // MARK: - Container-facing surface

    func start<P: Publisher>(in containerView: UIView,
                             parentViewController: UIViewController,
                             isFloatingUIEnabled: Bool = false,
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
            favoritesPresentation: favoritesPresentation,
            usesScrollableEscapeHatch: usesScrollableEscapeHatch,
            usesRedesignedNewTabPageLayout: redesignedSearchPresentation != nil,
            showsRedesignedSearchModules: showsRedesignedSearchModules,
            mode: focusedMode,
            escapeHatch: escapeHatch,
            syncPromo: syncPromo)
        let hosting = UnifiedSuggestionsHostingController(rootView: view)
        hosting.isFloatingUIEnabled = isFloatingUIEnabled
        if #available(iOS 16.4, *) {
            // UIKit already bounds this host with the keyboard guide. Keep only container insets.
            hosting.safeAreaRegions = [.container]
        }
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

    func setUsesRedesignedNewTabPageLayout(_ enabled: Bool) {
        guard enabled != (redesignedSearchPresentation != nil) else { return }
        redesignedPresentationCancellable = nil
        if enabled {
            favoritesPresentation.viewController?.setFocusedContent(nil)
            embeddedHatchInset = 0
            let presentation = RedesignedFocusedSearchPresentation(
                inputsPublisher: config.inputsPublisher,
                dismissPublisher: viewModel.$dismissBehavior.eraseToAnyPublisher(),
                fireTabPublisher: viewModel.$isFireTab.eraseToAnyPublisher())
            redesignedSearchPresentation = presentation
            redesignedPresentationCancellable = presentation.$showsSearchModules
                .sink { [weak self] showsSearchModules in
                    // Use the emitted value: @Published sends before the stored value changes.
                    guard let self else { return }
                    self.showsRedesignedSearchModules = showsSearchModules
                    self.rebuildRootView()
                    self.onContentChanged?()
                }
        } else {
            redesignedSearchPresentation = nil
            showsRedesignedSearchModules = false
            rebuildRootView()
        }
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
    func prepareForActivation(favoritesExpansionState: FavoritesExpansionState? = nil) {
        scrollLegacyContentToTop(duration: 0)
        if let favoritesExpansionState,
           let model = favoritesPresentation.viewController?.favoritesModel,
           model.expansionState !== favoritesExpansionState {
            // This host survives tab changes. Bind to the selected tab without animating from the previous tab's state.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                model.expansionState = favoritesExpansionState
            }
        }
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
        viewModel.chromeInsetTop = top + embeddedHatchInset
        logScrollDiagnostics("insets.before")
        let update = {
            self.hostingController?.additionalSafeAreaInsets = UIEdgeInsets(
                top: top,
                left: self.contentInsets.left,
                bottom: self.contentInsets.bottom,
                right: self.contentInsets.right
            )
            // Flush the same controller's safe-area change inside the input's height animation.
            self.hostingController?.view.layoutIfNeeded()
        }
        if usesScrollableEscapeHatch, redesignedSearchPresentation == nil, let controller = favoritesPresentation.viewController {
            controller.preservingFocusedScrollPosition(while: update)
        } else {
            update()
        }
        logScrollDiagnostics("insets.after")
        DispatchQueue.main.async { [weak self] in
            self?.logScrollDiagnostics("insets.nextRunLoop")
        }
    }

    func logScrollDiagnostics(_ event: String) {
        let hostIdentity = String(describing: ObjectIdentifier(self))
        let modelIdentity = escapeHatch.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
        let content = String(describing: viewModel.content)
        let requested = String(describing: contentInsets)
        Logger.unifiedInputState.debug("[EHScrollDiag] event=\(event, privacy: .public) host=\(hostIdentity, privacy: .public) mode=\(String(describing: self.focusedMode), privacy: .public) scrolling=\(self.usesScrollableEscapeHatch, privacy: .public) redesign=\(self.redesignedSearchPresentation != nil, privacy: .public) modules=\(self.showsRedesignedSearchModules, privacy: .public) content=\(content, privacy: .public) hatch=\(modelIdentity, privacy: .public) returnCard=\(self.escapeHatch?.isReturnToTabCardVisible ?? false, privacy: .public) requested=\(requested, privacy: .public) extraTop=\(self.escapeHatchTopInset, privacy: .public) embeddedHatch=\(self.embeddedHatchInset, privacy: .public)")
        guard let view = hostingController?.viewIfLoaded else { return }
        let frame = String(describing: view.convert(view.bounds, to: nil))
        let safeArea = String(describing: view.safeAreaInsets)
        Logger.unifiedInputState.debug("[EHScrollDiag] event=\(event, privacy: .public) host=\(hostIdentity, privacy: .public) frame=\(frame, privacy: .public) safeArea=\(safeArea, privacy: .public) alpha=\(view.alpha, privacy: .public) hidden=\(view.isHidden, privacy: .public) window=\(view.window != nil, privacy: .public)")
        Logger.logEscapeHatchScrollViews(in: view, event: event)
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
        if usesScrollableEscapeHatch {
            onContentChanged?()
        }
    }

    /// Releases the duck.ai source/VM only (search persists), mirroring today's lazy lifecycle.
    func detachDuckAISurface() {
        duckAISurface?.source.tearDown()
        duckAISurface = nil
        viewModel.setDuckAIListViewModel(nil)
        rebuildRootView()
    }

    func tearDown() {
        redesignedPresentationCancellable = nil
        redesignedSearchPresentation = nil
        cancellables.removeAll()
        onContentChanged = nil
        config.source.tearDown()
        duckAISurface?.source.tearDown()
        duckAISurface = nil
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        hostingController = nil
        viewModel.logoViewportFrame = nil
    }

    // MARK: - Private

    private func rebuildRootView() {
        guard let hosting = hostingController else { return }
        hosting.rootView = UnifiedSuggestionsView(
            viewModel: viewModel,
            isAddressBarAtBottom: isAddressBarAtBottom,
            favoritesPresentation: favoritesPresentation,
            usesScrollableEscapeHatch: usesScrollableEscapeHatch,
            usesRedesignedNewTabPageLayout: redesignedSearchPresentation != nil,
            showsRedesignedSearchModules: showsRedesignedSearchModules,
            mode: focusedMode,
            escapeHatch: escapeHatch,
            syncPromo: syncPromo)
        NotificationCenter.default.post(name: RemoteMessageImpressionReporter.remoteMessageSurfaceDidChange, object: hosting)
    }
}

/// The redesigned modules use the favorites controller's models without mounting that controller.
/// Report visibility from their actual host, so hierarchy and modal checks still apply.
private final class UnifiedSuggestionsHostingController: UIHostingController<UnifiedSuggestionsView>, RemoteMessagePresenting {

    var isFloatingUIEnabled = false

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if rootView.usesScrollableEscapeHatch, rootView.usesRedesignedNewTabPageLayout {
            enableVerticalBounce(in: view)
        }
        guard isFloatingUIEnabled, view.window != nil, let containerView = view.superview else { return }
        // These are the native anchors used to constrain the host. The logo ignores the top
        // container safe area, but still reserves the bottom input-bar inset.
        var viewport = containerView.convert(containerView.bounds, to: nil)
        let keyboardTop = containerView.convert(containerView.keyboardLayoutGuide.layoutFrame, to: nil).minY
        viewport.size.height = max(0, keyboardTop - viewport.minY - view.safeAreaInsets.bottom)
        guard rootView.viewModel.logoViewportFrame != viewport else { return }
        rootView.viewModel.logoViewportFrame = viewport
    }

    private func enableVerticalBounce(in view: UIView) {
        if let scrollView = view as? UIScrollView {
            scrollView.alwaysBounceVertical = true
            return
        }
        view.subviews.forEach { enableVerticalBounce(in: $0) }
    }

    func hasVisibleRemoteMessage(withID messageID: String) -> Bool {
        rootView.usesRedesignedNewTabPageLayout &&
        rootView.showsRedesignedSearchModules &&
        !rootView.viewModel.isFireTab &&
        !rootView.viewModel.isFadingOut &&
        rootView.favoritesPresentation.hasAppearedRemoteMessage(withID: messageID)
    }
}
