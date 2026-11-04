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
    private var cancellables = Set<AnyCancellable>()
    private var logoKeyboardCancellable: AnyCancellable?
    private var keyboardSettleTime: CFTimeInterval = 0
    /// True while a mode switch or an expand runs, so its inset changes move the content with Core Animation.
    private var slidesContentWithCoreAnimation = false
    private var isChangingInputMode = false
    private var isLogoHeldForForeground = false
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

    func setFocusedContent(mode: TextEntryMode, escapeHatchPlacement: FocusedContentPlacement, escapeHatch: EscapeHatchModel?, syncPromo: AnyView?) {
        focusedMode = mode
        viewModel.setEscapeHatchPlacement(escapeHatchPlacement)
        if usesScrollableEscapeHatch {
            self.escapeHatch = escapeHatch
        }
        self.syncPromo = syncPromo
        guard !isChangingInputMode else { return }
        updateFocusedContent()
    }

    private func updateFocusedContent() {
        if redesignedSearchPresentation == nil, usesScrollableEscapeHatch {
            favoritesPresentation.viewController?.setFocusedContent(LegacyFocusedNewTabPageContent(
                recentChats: focusedMode == .aiChat ? viewModel.listViewModel(for: .recents) : nil,
                syncPromo: syncPromo,
                isAddressBarAtBottom: isAddressBarAtBottom,
                onEscapeHatchGeometryChange: { [weak viewModel] in viewModel?.setEmbeddedEscapeHatchGeometry($0) },
                waitsForLogoFadeOut: { [weak viewModel] in viewModel?.waitsForLogoFadeOut ?? false }), escapeHatch: escapeHatch)
        } else {
            if redesignedSearchPresentation == nil {
                favoritesPresentation.viewController?.setFocusedContent(nil)
            }
            rebuildRootView()
        }
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
        hosting.onKeyboardLowering = { [weak self] in self?.deferLogoRevealUntilKeyboardSettles() }
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
        // The legacy focused hatch lives in the NTP hierarchy and blurs only what it covers.
        viewModel.$backdropLogoFrame
            .removeDuplicates()
            .sink { [weak self] in self?.favoritesPresentation.viewController?.setFocusedLogoFrame($0) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .filter { notification in
                let info = notification.userInfo
                guard let begin = (info?[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue)?.cgRectValue,
                      let end = (info?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return false }
                return end.minY > begin.minY
            }
            .sink { [weak self] in
                self?.deferLogoRevealUntilKeyboardSettles(duration: $0.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0)
            }
            .store(in: &cancellables)
        // Leaving the app lowers the keyboard and returning raises it again, so a logo without room
        // beside the keyboard would show in between. Hold it back until the keyboard is up again.
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .filter { [weak self] _ in
                guard let self else { return false }
                return usesScrollableEscapeHatch && hostingController?.view.window != nil && viewModel.backdropLogoFrame == nil
                    && UIResponder.currentFirstResponder() != nil
            }
            .sink { [weak self] _ in
                self?.logoKeyboardCancellable = nil
                self?.viewModel.isLogoRevealDeferred = true
                self?.isLogoHeldForForeground = true
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .filter { [weak self] _ in self?.isLogoHeldForForeground == true }
            .sink { [weak self] _ in
                self?.isLogoHeldForForeground = false
                self?.deferLogoRevealUntilKeyboardRises()
            }
            .store(in: &cancellables)
    }

    /// A hidden logo beside the hatch appears only once a lowering keyboard settles, never sliding in with it.
    /// A rising keyboard only takes room away, so it never reveals the logo and needs no wait.
    /// A logo that is already shown keeps the existing fit checks, which hide it when room runs out.
    /// The did-hide notifications can arrive while the keyboard is still animating, so the reveal also waits out its duration.
    private func deferLogoRevealUntilKeyboardSettles(duration: TimeInterval = 0) {
        keyboardSettleTime = max(keyboardSettleTime, CACurrentMediaTime() + duration)
        guard viewModel.escapeHatchPlacement != .hidden, viewModel.backdropLogoFrame == nil, !viewModel.isLogoRevealDeferred else { return }
        viewModel.isLogoRevealDeferred = true
        logoKeyboardCancellable = NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification),
                   NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification))
            .first()
            .flatMap { [weak self] _ in
                Just(()).delay(for: .seconds(max(0, (self?.keyboardSettleTime ?? 0) - CACurrentMediaTime())), scheduler: DispatchQueue.main)
            }
            .sink { [weak self] _ in self?.finishDeferredLogoReveal() }
    }

    func setUsesRedesignedNewTabPageLayout(_ enabled: Bool) {
        guard enabled != (redesignedSearchPresentation != nil) else { return }
        viewModel.cancelLogoModeChange()
        viewModel.usesRedesignedNewTabPageLayout = enabled
        viewModel.setEmbeddedEscapeHatchGeometry(nil)
        redesignedPresentationCancellable = nil
        if enabled {
            favoritesPresentation.viewController?.setFocusedContent(nil)
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

    /// Inset changes made in `changes` move the content with Core Animation, in step with the bar.
    func slideContentWithCoreAnimation(_ changes: () -> Void) {
        let wasSliding = slidesContentWithCoreAnimation
        slidesContentWithCoreAnimation = true
        defer { slidesContentWithCoreAnimation = wasSliding }
        changes()
    }

    func performInputModeChange(to mode: TextEntryMode, _ changes: () -> Void) {
        viewModel.performLogoModeChange(to: mode) {
            isChangingInputMode = true
            slideContentWithCoreAnimation { performInputModeChangeDeferringLogo(changes) }
            isChangingInputMode = false
        }
        updateFocusedContent()
    }

    private func performInputModeChangeDeferringLogo(_ changes: () -> Void) {
        // A logo on screen stays to morph; one hidden for lack of room stays hidden while the bar resizes.
        guard usesScrollableEscapeHatch, viewModel.escapeHatchPlacement != .hidden, !viewModel.isLogoOnScreen else {
            changes()
            return
        }
        // The input view forwards its text view's focus, so any first responder here is the input.
        let wasEditing = UIResponder.currentFirstResponder() != nil
        viewModel.isLogoRevealDeferred = true
        // Floating and split iPad keyboards report only frame changes, so those release the logo too.
        logoKeyboardCancellable = NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification),
                   NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)
                .filter { _ in UIResponder.currentFirstResponder() == nil })
            .first()
            .sink { [weak self] _ in self?.finishDeferredLogoReveal() }
        changes()
        if #available(iOS 17.0, *), !wasEditing, UIResponder.currentFirstResponder() != nil {
            let inputContext: UITextInputContext? = .current()
            if let inputContext,
               !inputContext.isHardwareKeyboardInputExpected,
               !inputContext.isPencilInputExpected,
               !inputContext.isDictationInputExpected {
                return
            }
        }
        // The bar settles at the new mode's height after its 0.2s resize, so check the room once it has.
        logoKeyboardCancellable = Just(()).delay(for: .seconds(0.25), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.finishDeferredLogoReveal() }
    }

    /// A focus raises the keyboard after the content shows, so a logo that only has room without it would
    /// flash before the keyboard hides it. The keyboard guide already holds the keyboard's end frame here,
    /// so it cannot tell a rising keyboard from a risen one: without a keyboard on the way, the fallback reveals it.
    private func deferLogoRevealUntilKeyboardRises() {
        guard usesScrollableEscapeHatch else { return }
        viewModel.isLogoRevealDeferred = true
        logoKeyboardCancellable = NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification))
            .map { _ in () }
            .merge(with: Just(()).delay(for: .seconds(Self.keyboardRiseFallback), scheduler: DispatchQueue.main))
            .first()
            .sink { [weak self] _ in self?.finishDeferredLogoReveal() }
    }

    /// Longer than the keyboard takes to rise.
    private static let keyboardRiseFallback: TimeInterval = 0.6

    private func finishDeferredLogoReveal() {
        hostingController?.view.window?.layoutIfNeeded()
        hostingController?.view.layoutIfNeeded()
        viewModel.isLogoRevealDeferred = false
        logoKeyboardCancellable = nil
    }

    /// Fire tabs render the fire empty state instead of the Dax logo for the empty (`.logo`) state.
    func setIsFireTab(_ value: Bool) {
        viewModel.setFireTab(value)
    }

    /// iPhone landscape suppresses the empty state (no room) — matches the unfocused NTP.
    func setLandscape(_ value: Bool) {
        viewModel.setLandscape(value)
    }

    /// List/logo→favorites collapse: fade the focused content out as the NTP content takes over.
    /// A logo handed over from the NTP is already on screen, so it does not wait for the keyboard:
    /// the fit checks hide it if the keyboard leaves no room.
    func showLogoForHandoff() {
        logoKeyboardCancellable = nil
        // The activation deferred it within the same update, so it shows as it was instead of fading in.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            viewModel.isLogoRevealDeferred = false
        }
    }

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
        logoKeyboardCancellable = nil
        viewModel.isLogoRevealDeferred = false
        isLogoHeldForForeground = false
        deferLogoRevealUntilKeyboardRises()
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
        viewModel.chromeInsetTop = top
        let contentTopInset = usesScrollableEscapeHatch ? top : 0
        let duration = UIView.inheritedAnimationDuration
        let delta = contentTopInset - viewModel.contentTopInset
        let coreAnimatedContentView = coreAnimatedContentView(moving: delta, duration: duration)
        let animation: Animation? = coreAnimatedContentView == nil && duration > 0 && !UIAccessibility.isReduceMotionEnabled
            ? .easeInOut(duration: duration) : nil
        withAnimation(animation) {
            if viewModel.contentTopInset != contentTopInset {
                viewModel.contentTopInset = contentTopInset
            }
            if redesignedSearchPresentation == nil {
                favoritesPresentation.viewController?.setFocusedContentTopInset(contentTopInset)
            }
        }
        // Nested SwiftUI hosts can apply a changing UIKit top inset twice. Keep the input clearance in their content.
        hostingController?.additionalSafeAreaInsets = UIEdgeInsets(
            top: usesScrollableEscapeHatch ? 0 : top,
            left: contentInsets.left,
            bottom: contentInsets.bottom,
            right: contentInsets.right
        )
        hostingController?.view.layoutIfNeeded()
        if let coreAnimatedContentView {
            coreAnimatedContentView.layoutIfNeeded()
            Self.slide(coreAnimatedContentView.layer, from: -delta, duration: duration)
        }
    }

    /// SwiftUI animations advance on the main thread, which a mode switch or an expand keeps busy while it
    /// builds the bar and raises the keyboard, so the content would fall behind the bar and slip under it.
    /// The content takes its new inset at once and slides there with Core Animation instead, on the render
    /// server like the bar.
    private func coreAnimatedContentView(moving delta: CGFloat, duration: TimeInterval) -> UIView? {
        guard slidesContentWithCoreAnimation, usesScrollableEscapeHatch, delta != 0, duration > 0,
              !UIAccessibility.isReduceMotionEnabled else { return nil }
        // A Fire tab shows the Fire screen of this host and never the logo.
        if viewModel.isFireTab { return hostingController?.view }
        if redesignedSearchPresentation == nil {
            // The legacy content lives in its own view, apart from the logo.
            guard let view = favoritesPresentation.viewController?.viewIfLoaded, view.window != nil else { return nil }
            return view
        }
        // The logo shares this host and would slide too, so only while it is off screen.
        guard viewModel.escapeHatchPlacement == .embedded, viewModel.backdropLogoFrame == nil else { return nil }
        return hostingController?.view
    }

    /// Additive, so the several inset changes of one switch add up the way the bar's own animations do.
    private static func slide(_ layer: CALayer, from offset: CGFloat, duration: TimeInterval) {
        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = offset
        animation.toValue = 0
        animation.isAdditive = true
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: nil)
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
        viewModel.cancelLogoModeChange()
        logoKeyboardCancellable = nil
        viewModel.isLogoRevealDeferred = false
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
        viewModel.logoHostFrame = nil
        viewModel.setEmbeddedEscapeHatchGeometry(nil)
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
    /// Fires when the keyboard starts lowering, which can precede its notifications during an interactive dismiss.
    var onKeyboardLowering: (() -> Void)?
    private var keyboardOverlap: CGFloat?
    private var isRotating = false

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // A rotation resizes the keyboard guide without moving the keyboard or posting its notifications.
        isRotating = true
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.isRotating = false
            self?.keyboardOverlap = nil
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Checked before SwiftUI lays out the new size, so the wait starts before the logo counts as shown.
        if view.window != nil, !isRotating, let containerView = view.superview {
            // Measured above the safe area, so a rotation with the keyboard hidden is not a keyboard move.
            let overlap = max(0, containerView.keyboardLayoutGuide.layoutFrame.height - containerView.safeAreaInsets.bottom)
            if let keyboardOverlap, overlap < keyboardOverlap { onKeyboardLowering?() }
            keyboardOverlap = overlap
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.window != nil, let containerView = view.superview else { return }
        if !isFloatingUIEnabled {
            var viewport = view.convert(view.bounds, to: nil)
            viewport.size.height = max(0, viewport.height - view.safeAreaInsets.bottom)
            if rootView.viewModel.logoHostFrame != viewport { rootView.viewModel.logoHostFrame = viewport }
            return
        }
        // These are the native anchors used to constrain the host. The logo ignores the top
        // container safe area, but still reserves the bottom input-bar inset.
        var viewport = containerView.convert(containerView.bounds, to: nil)
        let keyboardTop = containerView.convert(containerView.keyboardLayoutGuide.layoutFrame, to: nil).minY
        viewport.size.height = max(0, keyboardTop - viewport.minY - view.safeAreaInsets.bottom)
        guard rootView.viewModel.logoViewportFrame != viewport else { return }
        rootView.viewModel.logoViewportFrame = viewport
    }

    func hasVisibleRemoteMessage(withID messageID: String) -> Bool {
        rootView.usesRedesignedNewTabPageLayout &&
        rootView.showsRedesignedSearchModules &&
        !rootView.viewModel.isFireTab &&
        !rootView.viewModel.isFadingOut &&
        rootView.favoritesPresentation.hasAppearedRemoteMessage(withID: messageID)
    }
}
