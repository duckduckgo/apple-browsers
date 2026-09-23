//
//  AIChatContextualUTIHost.swift
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

import AIChat
import Combine
import UIKit
import os.log

/// Owns a `UnifiedToggleInputCoordinator` configured for the contextual chat surface.
@MainActor
final class AIChatContextualUTIHost: UnifiedToggleInputDelegate, AIChatContextualFloatingInputHosting {

    private let coordinator: UnifiedToggleInputCoordinator
    let chipViewModel: UnifiedToggleInputPageContextChipViewModel
    private let hasActiveChat: () -> Bool
    private weak var contextualChatViewController: AIChatContextualWebViewController?
    private weak var currentUserScript: AIChatUserScript?
    private weak var pendingUserScriptToBind: AIChatUserScript?
    private var isBoundToUserScript = false
    private var hasDeliveredFirstPrompt = false

    /// The input's bottom while it follows the keyboard, and the fixed pin that replaces it once frozen.
    private var keyboardBottomConstraint: NSLayoutConstraint?
    private var frozenBottomConstraint: NSLayoutConstraint?
    private let startsPreSubmit: Bool
    private var hasKeyboardAppeared = false
    /// Launch-time snapshot: re-reading the feature costs a privacy-config evaluation each time.
    private let usesFloatingInput: Bool
    private var cancellables = Set<AnyCancellable>()
    private let duckAIWideEventInstrumentation: DuckAIWideEventInstrumentation
    private let duckAIWideEventFlowScope = DuckAIWideEventFlowScope.contextual(UUID())

    var onAttachRequested: (() -> Void)?
    var onRemoveRequested: (() -> Void)?
    /// The user accepted the offer to attach the page they navigated to.
    var onSuggestionAccepted: (() -> Void)?
    var onSuggestionDismissed: (() -> Void)?
    var onPromptSubmitted: (() -> Void)?
    /// Fires on every prompt delivery so the session state can mark context delivered and re-render the chip.
    var onPromptDelivered: (() -> Void)?
    var onDuckAIPromptSubmitted: ((AIChatEntryPointSource?) -> Void)?
    var onAIVoiceChatRequested: (() -> Void)?
    var onEditModeChange: ((Bool) -> Void)?
    var onExpandedChange: ((Bool) -> Void)?
    var isInputExpanded: Bool {
        coordinator.viewController.isInputExpanded
    }

    // MARK: - Suggestions strip (owned by the host, shown above the input card)

    private let suggestionsController: AIChatContextualInputViewController
    /// True once the strip has shown for the current mount: the first batch appears instantly (riding the
    /// input's entrance), later ones fade. Reset when the strip leaves a surface.
    private var hasShownStartActions = false
    /// The last actions handed to the strip, so a view-state emission that leaves them unchanged doesn't
    /// rebuild every chip's visual-effect view.
    private var lastStartActions: (suggestions: [ContextualSuggestedPrompt], quickActions: [AIChatContextualQuickAction], isLoading: Bool)?
    /// The surface the strip is currently mounted in, so it can be detached before it moves to another.
    private weak var suggestionsParent: UIViewController?
    /// Fires when the user taps a suggestion chip.
    var onSuggestionSelected: ((ContextualSuggestedPrompt) -> Void)?
    /// Fires when the user taps a quick-action chip (the floating surface offers these alongside suggestions).
    var onQuickActionSelected: ((AIChatContextualQuickAction) -> Void)?

    private lazy var suggestionsContainer: ChipHitTestingView = {
        let view = ChipHitTestingView()
        view.backgroundColor = .clear
        view.alpha = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        view.containsChip = { [weak self] point in
            guard let self else { return false }
            return self.suggestionsController.containsStartAction(at: point, from: self.suggestionsContainer)
        }
        return view
    }()

    /// Scrims the content above the input while the strip is up, so the suggestions read against a bright
    /// transcript. Only the sheet enables it; the floating surface already dims the whole page.
    private var suggestionsDimEnabled = false
    private lazy var suggestionsDimView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.alpha = 0
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Raised by the input's microphone, which dictates into the field rather than opening voice chat.
    var onVoiceSearchRequested: (() -> Void)?

    var attachedContextURL: URL? {
        chipViewModel.attachedContext.flatMap { URL(string: $0.contextData.url) }
    }

    init(
        originatingURLPublisher: AnyPublisher<URL?, Never>,
        initialAttachedContext: AIChatPageContext?,
        initialAttachmentDeliveryState: PageContextAttachmentDeliveryState = .delivered,
        hasActiveChat: @escaping () -> Bool,
        isAutoAttachEnabled: @escaping () -> Bool,
        isCurrentPageAttachable: @escaping () -> Bool = { true },
        isFireTab: Bool,
        lastUsedModelProvider: DuckAiLastUsedModelProviding? = nil,
        unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding = UnifiedToggleInputFeature(),
        floatingInputFeature: AIChatContextualFloatingInputFeatureProviding = AIChatContextualFloatingInputFeature(),
        start: ContextualInputStart = .expandedOnExistingChat,
        usageLimitsStore: DuckAiUsageLimitsStore? = nil,
        suggestionsController: AIChatContextualInputViewController
    ) {
        self.suggestionsController = suggestionsController
        let isFloatingInputAvailable = floatingInputFeature.isAvailable
        self.hasActiveChat = hasActiveChat
        self.startsPreSubmit = start.isPreSubmit
        self.usesFloatingInput = isFloatingInputAvailable
        self.hasDeliveredFirstPrompt = !start.isPreSubmit
        let wideEventInstrumentation = DefaultDuckAIWideEventInstrumentation(
            wideEvent: AppDependencyProvider.shared.wideEvent
        )
        self.duckAIWideEventInstrumentation = wideEventInstrumentation
        self.coordinator = UnifiedToggleInputCoordinator(
            host: .contextualChat,
            isToggleEnabled: false,
            isFireTab: isFireTab,
            lastUsedModelProvider: lastUsedModelProvider,
            duckAIWideEventInstrumentation: wideEventInstrumentation,
            duckAIWideEventFlowScope: duckAIWideEventFlowScope,
            contextualStart: start,
            attachmentPasteEnabled: unifiedToggleInputFeature.isAttachmentPasteEnabled,
            placesAttachmentsAboveInput: isFloatingInputAvailable,
            usageLimitsStore: usageLimitsStore
        )
        self.chipViewModel = UnifiedToggleInputPageContextChipViewModel(
            originatingURLPublisher: originatingURLPublisher,
            initialAttachedContext: initialAttachedContext,
            initialAttachmentDeliveryState: initialAttachmentDeliveryState,
            isAutoAttachEnabled: isAutoAttachEnabled
        )
        coordinator.delegate = self
        coordinator.onPageContextAttachRequested = { [weak chipViewModel] in
            chipViewModel?.tapToAttach()
        }
        coordinator.isPageContextAttachable = isCurrentPageAttachable
        coordinator.hasPendingPageContextProvider = { [weak chipViewModel] in
            chipViewModel?.pendingAttachedContextData != nil
        }
        coordinator.updateImageButtonVisibility()
        coordinator.viewController.bindPageContextChip(to: chipViewModel)
        coordinator.viewController.onExpansionChange = { [weak self] expanded in
            self?.onExpandedChange?(expanded)
            self?.updateStartActionsForExpansion(expanded)
        }
        suggestionsController.delegate = self
        chipViewModel.onAttachActionRequested = { [weak self] in
            self?.onAttachRequested?()
        }
        chipViewModel.onRemoveActionRequested = { [weak self] in
            self?.onRemoveRequested?()
        }
        chipViewModel.onSuggestionAccepted = { [weak self] in
            self?.onSuggestionAccepted?()
        }
        chipViewModel.onSuggestionDismissed = { [weak self] in
            self?.onSuggestionDismissed?()
        }

        Logger.contextualUTI.debug("UTIHost init — carryOver=\(initialAttachedContext != nil, privacy: .public) auto=\(isAutoAttachEnabled(), privacy: .public)")

        coordinator.intentPublisher
            .sink { [weak self] _ in
                self?.applyCurrentRenderState()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in
                self?.collapseForKeyboardDismissal()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] _ in
                self?.hasKeyboardAppeared = true
            }
            .store(in: &cancellables)
    }

    /// Only a keyboard that was really shown can be lost: a hardware keyboard hides on every keystroke.
    private func collapseForKeyboardDismissal() {
        guard hasKeyboardAppeared else { return }
        hasKeyboardAppeared = false
        // Backgrounding takes the keyboard too, and offscreen hosts were never above one.
        guard UIApplication.shared.applicationState == .active,
              !coordinator.isPresentingAttachmentModal,
              coordinator.isInputOnScreen,
              !coordinator.isContextualChatCollapsed else { return }
        deactivateInput()
    }

    /// Re-evaluates the attach button/menu for the current page (e.g. page-context attachability after navigation).
    func refreshPageContextAttachability() {
        coordinator.updateImageButtonVisibility()
    }

    func setAttachedContext(_ context: AIChatPageContext, deliveryState: PageContextAttachmentDeliveryState = .pendingSubmit) {
        chipViewModel.setAttached(context, deliveryState: deliveryState)
    }

    func clearAttachedContext() {
        chipViewModel.clearAttached()
    }

    func setSuggestedContext(_ context: AIChatPageContext) {
        chipViewModel.setSuggested(context)
    }

    func clearSuggestedContext() {
        chipViewModel.clearSuggested()
    }

    /// One chip per attached selection, alongside the page-context chip. An empty list removes them all.
    func setSelectionChips(_ items: [(id: String, title: String, favicon: UIImage?)], onRemove: @escaping (String) -> Void) {
        coordinator.viewController.setSelectionContextChips(items, onRemove: onRemove)
    }

    /// Images and files currently in the input.
    var attachmentCount: Int {
        coordinator.attachmentCount
    }

    /// Fires when the input's attachments change.
    var onAttachmentsChanged: (() -> Void)? {
        get { coordinator.onAttachmentsChanged }
        set { coordinator.onAttachmentsChanged = newValue }
    }

    func presentRejectionBanner(_ message: String) {
        coordinator.presentRejectionBanner(message)
    }

    func clearRejectionBanner() {
        coordinator.clearRejectionBanner()
    }

    /// Routes UTI-submitted prompts through the contextual chat's JS message channel (same as the FE).
    /// Also wires the user script's page-context provider so every prompt payload carries whatever
    /// the chip says is currently attached — no duplicate state, single source of truth.
    func bindToUserScript(_ userScript: AIChatUserScript) {
        Logger.contextualUTI.info("Binding coordinator to AIChatUserScript")
        currentUserScript = userScript
        userScript.attachedPageContextProvider = { [weak self] in
            self?.chipViewModel.pendingAttachedContextData
        }
        userScript.onPromptSubmitted = { [weak self] in
            self?.handlePromptSubmittedFromUserScript()
        }

        if startsPreSubmit, !hasDeliveredFirstPrompt {
            pendingUserScriptToBind = userScript
            return
        }

        bindCoordinator(to: userScript)
    }

    func observeChatUpdates(_ publisher: AnyPublisher<String, Never>) {
        coordinator.observeChatUpdates(publisher)
    }

    /// Called when a prompt carrying page context is delivered; routes to the session state via `onPromptDelivered`.
    func notifyPromptDelivered() {
        onPromptDelivered?()
    }

    func setContextualChatViewController(_ contextualChatViewController: AIChatContextualWebViewController) {
        self.contextualChatViewController = contextualChatViewController
    }

    func installInWebView(_ contextualChatViewController: AIChatContextualWebViewController) {
        setContextualChatViewController(contextualChatViewController)
        coordinator.attachmentPresentingViewController = contextualChatViewController

        let viewController = coordinator.viewController
        guard viewController.parent !== contextualChatViewController else {
            return
        }

        UIView.performWithoutAnimation {
            contextualChatViewController.addChild(viewController)
            contextualChatViewController.view.addSubview(viewController.view)
            viewController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                viewController.view.leadingAnchor.constraint(equalTo: contextualChatViewController.view.leadingAnchor),
                viewController.view.trailingAnchor.constraint(equalTo: contextualChatViewController.view.trailingAnchor),
                viewController.view.bottomAnchor.constraint(equalTo: contextualChatViewController.view.keyboardLayoutGuide.topAnchor),
            ])
            contextualChatViewController.anchorWebViewBottom(to: viewController.view.topAnchor)
            viewController.didMove(toParent: contextualChatViewController)
            applyHostedExpansion(activatesInput: true)
            applyCurrentRenderState()
            contextualChatViewController.view.layoutIfNeeded()
        }
        Logger.contextualUTI.info("Installed at bottom of contextual web chat")
    }

    @discardableResult
    func mount(in parent: UIViewController) -> UIView {
        coordinator.attachmentPresentingViewController = parent

        let viewController = coordinator.viewController
        guard viewController.parent !== parent else {
            return viewController.view
        }

        // A dismissal animating out may still hold the input, and a child can only have one parent.
        detachInput()

        // Install + lay out without animation. Otherwise the half-sheet's slide-up animation
        // captures the UTI's first layout pass and interpolates from a zero-frame at (0,0),
        // making the bar fly in from the top-left.
        UIView.performWithoutAnimation {
            parent.addChild(viewController)
            parent.view.addSubview(viewController.view)
            viewController.view.translatesAutoresizingMaskIntoConstraints = false
            let bottom: NSLayoutConstraint
            if #available(iOS 16.0, *) {
                bottom = viewController.view.bottomAnchor.constraint(equalTo: parent.view.keyboardLayoutGuide.topAnchor)
            } else {
                // iOS 15 never drives the keyboard guide, so Auto Layout moves the guide to the input
                // instead of the input to the keyboard. Pin to the bottom and follow the keyboard by hand.
                bottom = viewController.view.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor)
                followKeyboardManually(parent: parent, pin: bottom)
            }
            keyboardBottomConstraint = bottom
            NSLayoutConstraint.activate([
                viewController.view.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
                viewController.view.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
                bottom,
            ])
            viewController.didMove(toParent: parent)
            applyHostedExpansion(activatesInput: false)
            applyCurrentRenderState()
            parent.view.layoutIfNeeded()
        }
        Logger.contextualUTI.info("Mounted above the keyboard")
        return viewController.view
    }

    private var legacyKeyboardPinCancellables = Set<AnyCancellable>()

    /// Keeps `pin` at the keyboard's overlap with `parent`, animated on the keyboard's own curve.
    private func followKeyboardManually(parent: UIViewController, pin: NSLayoutConstraint) {
        legacyKeyboardPinCancellables.removeAll()
        let update: (Notification) -> Void = { [weak parent] notification in
            // A freeze or a detach replaces this pin, and laying out the old one mid-dismissal fights the slide.
            guard pin.isActive, let parentView = parent?.viewIfLoaded else { return }
            let end = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
            let overlap = max(0, parentView.bounds.maxY - parentView.convert(end, from: nil).minY)
            pin.constant = -overlap
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0
            UIView.animate(withDuration: duration) { parentView.layoutIfNeeded() }
        }
        for name in [UIResponder.keyboardWillShowNotification,
                     UIResponder.keyboardWillChangeFrameNotification,
                     UIResponder.keyboardWillHideNotification] {
            NotificationCenter.default.publisher(for: name)
                .sink(receiveValue: update)
                .store(in: &legacyKeyboardPinCancellables)
        }
    }

    /// Mounting must not decide focus: the surface that opened this UTI already did.
    private func applyHostedExpansion(activatesInput: Bool) {
        if coordinator.isContextualChatCollapsed {
            coordinator.showCollapsed()
        } else {
            coordinator.showExpanded(activatesInput: activatesInput)
        }
    }

    /// Edges of the visible input card, for aligning content sitting around the bar.
    var inputCardTopAnchor: NSLayoutYAxisAnchor { coordinator.viewController.inputCardTopAnchor }
    var inputCardLeadingAnchor: NSLayoutXAxisAnchor { coordinator.viewController.inputCardLeadingAnchor }
    var inputCardTrailingAnchor: NSLayoutXAxisAnchor { coordinator.viewController.inputCardTrailingAnchor }

    // MARK: - Suggestions strip

    /// Mounts the suggestions strip above the input card in `parent`. Taps in the gaps pass through. The strip
    /// is shared across surfaces, so mounting it here first detaches it from wherever it was — the same way the
    /// input bar moves between surfaces.
    func embedSuggestions(in parent: UIViewController, dimmed: Bool) {
        guard suggestionsParent !== parent else { return }
        detachSuggestionsContainer()
        suggestionsParent = parent
        suggestionsDimEnabled = dimmed
        parent.addChild(suggestionsController)
        suggestionsController.view.translatesAutoresizingMaskIntoConstraints = false
        suggestionsController.clearStartActionsHorizontalInset()
        suggestionsContainer.addSubview(suggestionsController.view)
        if dimmed {
            // A full-screen scrim behind everything, layered below the input card so the card and the strip
            // float on top of it — one continuous dim rather than a band that ends in a hard line above the
            // input.
            let inputView = coordinator.viewController.view
            if let inputView, inputView.superview === parent.view {
                parent.view.insertSubview(suggestionsDimView, belowSubview: inputView)
            } else {
                parent.view.addSubview(suggestionsDimView)
            }
            NSLayoutConstraint.activate([
                suggestionsDimView.topAnchor.constraint(equalTo: parent.view.topAnchor),
                suggestionsDimView.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
                suggestionsDimView.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
                suggestionsDimView.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor),
            ])
        }
        parent.view.addSubview(suggestionsContainer)
        NSLayoutConstraint.activate([
            suggestionsContainer.topAnchor.constraint(greaterThanOrEqualTo: parent.view.safeAreaLayoutGuide.topAnchor),
            suggestionsContainer.leadingAnchor.constraint(equalTo: inputCardLeadingAnchor),
            suggestionsContainer.trailingAnchor.constraint(equalTo: inputCardTrailingAnchor),
            suggestionsContainer.bottomAnchor.constraint(equalTo: inputCardTopAnchor),
            suggestionsController.view.topAnchor.constraint(equalTo: suggestionsContainer.topAnchor),
            suggestionsController.view.leadingAnchor.constraint(equalTo: suggestionsContainer.leadingAnchor),
            suggestionsController.view.trailingAnchor.constraint(equalTo: suggestionsContainer.trailingAnchor),
            suggestionsController.view.bottomAnchor.constraint(equalTo: suggestionsContainer.bottomAnchor),
        ])
        suggestionsController.didMove(toParent: parent)
    }

    /// Detaches the strip from `parent`, but only if it still holds it: a surface animating out finishes after
    /// the next one may already have taken it.
    func detachSuggestions(from parent: UIViewController) {
        guard suggestionsParent === parent else { return }
        detachSuggestionsContainer()
    }

    private func detachSuggestionsContainer() {
        // Reused across mounts, so a slide leaves a transform on it; handed back clean.
        suggestionsContainer.transform = .identity
        suggestionsContainer.removeFromSuperview()
        if suggestionsDimEnabled {
            suggestionsDimView.alpha = 0
            suggestionsDimView.removeFromSuperview()
        }
        suggestionsDimEnabled = false
        suggestionsParent = nil
        // The next surface's first batch should appear instantly again.
        hasShownStartActions = false
        lastStartActions = nil
        guard suggestionsController.parent != nil else { return }
        suggestionsController.willMove(toParent: nil)
        suggestionsController.view.removeFromSuperview()
        suggestionsController.removeFromParent()
    }

    /// Updates the start actions shown in the strip, driving the same show/clear lifecycle both surfaces used
    /// when each owned its own chips. The sheet passes suggestions only; the floating surface also passes
    /// quick actions.
    func setStartActions(suggestions: [ContextualSuggestedPrompt],
                         quickActions: [AIChatContextualQuickAction],
                         isLoading: Bool) {
        let unchanged = lastStartActions.map {
            $0.suggestions == suggestions && $0.quickActions == quickActions && $0.isLoading == isLoading
        } ?? false
        guard !unchanged else { return }
        lastStartActions = (suggestions, quickActions, isLoading)

        guard !isLoading else {
            // Loader alone while suggestions resolve. Passing the actions through here would flash the
            // placeholder chip beside it, then replace it.
            suggestionsController.updateStartActions(suggestions: [], quickActions: [])
            suggestionsController.updateSuggestionsLoading(true)
            return
        }
        guard !suggestions.isEmpty || !quickActions.isEmpty else {
            suggestionsController.updateSuggestionsLoading(false)
            clearStartActionsFadingOut()
            return
        }
        suggestionsController.updateStartActions(suggestions: suggestions, quickActions: quickActions)
        suggestionsController.updateSuggestionsLoading(false)
        showStartActionsIfNeeded()
    }

    /// The strip's container view, so a hosting surface (the floating input) can move it with the input.
    var suggestionsContainerView: UIView { suggestionsContainer }

    /// Collapsing the input hides the strip without clearing it, so it returns when the input expands again.
    private func updateStartActionsForExpansion(_ expanded: Bool) {
        if expanded {
            showStartActionsIfNeeded()
        } else {
            fadeStartActions(to: 0)
        }
    }

    /// Actions arrive asynchronously with the page context, so this waits for the first batch with content
    /// rather than showing at mount. They ride the input's entrance the first time and fade in thereafter.
    private func showStartActionsIfNeeded() {
        guard suggestionsController.startActionCount > 0, isInputExpanded else { return }
        guard !hasShownStartActions else {
            fadeStartActions(to: 1)
            return
        }
        hasShownStartActions = true
        suggestionsContainer.alpha = 1
        if suggestionsDimEnabled { suggestionsDimView.alpha = ContextualSurfaceScrim.alpha }
        suggestionsController.showStartActions()
    }

    /// Clears only once invisible: removing them collapses the stack into the input's own animation.
    private func clearStartActionsFadingOut() {
        fadeStartActions(to: 0) { [weak self] in
            self?.suggestionsController.updateStartActions(suggestions: [], quickActions: [])
        }
    }

    private func fadeStartActions(to alpha: CGFloat, completion: (() -> Void)? = nil) {
        guard suggestionsContainer.alpha != alpha else {
            completion?()
            return
        }
        let dimAlpha: CGFloat = suggestionsDimEnabled ? (alpha > 0 ? ContextualSurfaceScrim.alpha : 0) : 0
        UIView.animate(withDuration: 0.2, animations: {
            self.suggestionsContainer.alpha = alpha
            if self.suggestionsDimEnabled { self.suggestionsDimView.alpha = dimAlpha }
        }, completion: { finished in
            // An interrupted fade was overtaken; its clear would empty the row coming back.
            guard finished else { return }
            completion?()
        })
    }

    /// Pins the input where it currently sits, so a keyboard that moves or changes height afterwards cannot
    /// drag it. For a surface animating itself out: its own motion is then the only thing moving it.
    func freezeInputPosition() {
        let view = coordinator.viewController.view
        guard let parentView = view?.superview,
              let view,
              keyboardBottomConstraint?.isActive == true else { return }

        // From `center` and `bounds` rather than `frame`, which carries any transform the animation applies.
        let restingBottom = view.center.y + view.bounds.height / 2
        keyboardBottomConstraint?.isActive = false
        let frozen = view.bottomAnchor.constraint(equalTo: parentView.bottomAnchor,
                                                 constant: restingBottom - parentView.bounds.maxY)
        frozen.isActive = true
        frozenBottomConstraint = frozen
    }

    /// Surfaces borrow this one input from each other, so having mounted it is no guarantee of holding it.
    func isMounted(in parent: UIViewController) -> Bool {
        coordinator.viewController.parent === parent
    }

    /// Detaches the input so it can be mounted elsewhere, but only if `parent` still holds it: a surface
    /// animating out finishes after the next one may already have mounted it.
    func unmount(from parent: UIViewController) {
        guard isMounted(in: parent) else { return }
        detachInput()
    }

    private func detachInput() {
        // Ahead of the mounted check, so a surface that lost its parent some other way still leaves these
        // behind. Rebuilt by the next mount, against whatever parent that is.
        legacyKeyboardPinCancellables.removeAll()
        frozenBottomConstraint?.isActive = false
        frozenBottomConstraint = nil
        keyboardBottomConstraint = nil

        let viewController = coordinator.viewController
        guard viewController.parent != nil else { return }
        // Handed back clean: this view is reused across mounts, and a slide leaves a transform on it.
        viewController.view.transform = .identity
        viewController.willMove(toParent: nil)
        viewController.view.removeFromSuperview()
        viewController.removeFromParent()
    }

    func activateInput() {
        coordinator.showExpanded()
    }

    /// Collapses to the plain pill, dropping first responder; without that pill, only resigns.
    func deactivateInput() {
        guard usesFloatingInput else {
            coordinator.viewController.deactivateInput()
            return
        }
        coordinator.showCollapsed()
    }

    var isInputFirstResponder: Bool {
        coordinator.viewController.isInputFirstResponder
    }

    var isInputCollapsed: Bool {
        coordinator.isContextualChatCollapsed
    }

    /// A finished transcript belongs in the input, focused so the user can edit or send it.
    func applyDictatedQuery(_ query: String) {
        setText(query)
        activateInput()
    }

    func setVoiceSearchAvailable(_ available: Bool) {
        coordinator.updateVoiceSearchAvailability(available)
    }

    /// Drops a dictated query into the field for the user to review before sending.
    func setText(_ text: String) {
        coordinator.setText(text)
    }

    func endEditMode() {
        coordinator.endEditMode()
    }

    func submitQuickActionPrompt(_ prompt: String) {
        coordinator.submitProgrammatic(text: prompt)
    }

    func prepareForNewChat() {
        // Back on the start state, so the next prompt is a first prompt again and reports itself.
        hasDeliveredFirstPrompt = false
        clearAttachedContext()
        if startsPreSubmit, let currentUserScript {
            coordinator.unbind()
            isBoundToUserScript = false
            pendingUserScriptToBind = currentUserScript
        }
        coordinator.startNewChat()
        coordinator.showExpanded(activatesInput: false)
        applyCurrentRenderState()
    }

    private func applyCurrentRenderState() {
        coordinator.viewController.apply(coordinator.computeRenderState().viewConfig, animated: false)
        contextualChatViewController?.view.layoutIfNeeded()
    }

    private func bindCoordinator(to userScript: AIChatUserScript) {
        isBoundToUserScript = true
        let chatID = userScript.webView?.url?.duckAIChatID
        coordinator.bindToTab(userScript, hasExistingChat: hasActiveChat() || chatID != nil)
        if let chatID {
            coordinator.restoreLastUsedModel(forChatID: chatID)
        }
    }

    private func commitDeferredBindIfNeeded() {
        guard !isBoundToUserScript, let pendingUserScriptToBind else { return }
        self.pendingUserScriptToBind = nil
        bindCoordinator(to: pendingUserScriptToBind)
    }

    private func handlePromptSubmittedFromUserScript() {
        reportFirstPromptSubmission()
        onPromptDelivered?()
    }

    /// True for the first report only: the input and the frontend both report the same submission.
    private func claimFirstPromptSubmission() -> Bool {
        guard !hasDeliveredFirstPrompt else { return false }
        hasDeliveredFirstPrompt = true
        return true
    }

    private func reportFirstPromptSubmission() {
        guard claimFirstPromptSubmission() else { return }
        onPromptSubmitted?()
        commitDeferredBindIfNeeded()
    }

    func unifiedToggleInputDidSubmitPromptToBoundChat() {
        reportFirstPromptSubmission()
    }

    func unifiedToggleInputDidSubmitDuckAIPrompt(origin: AIChatEntryPointSource?) {
        onDuckAIPromptSubmitted?(origin)
    }

    func unifiedToggleInputDidSubmitPrompt(_ prompt: String,
                                           modelId: String?,
                                           tools: [AIChatRAGTool]?,
                                           reasoningEffort: AIChatReasoningEffort?,
                                           images: [AIChatNativePrompt.NativePromptImage]?,
                                           files: [AIChatNativePrompt.NativePromptFile]?) {
        guard claimFirstPromptSubmission() else { return }
        onPromptSubmitted?()
        contextualChatViewController?.submitPrompt(prompt,
                                                   images: images,
                                                   files: files,
                                                   modelId: modelId,
                                                   tools: tools,
                                                   pageContext: chipViewModel.pendingAttachedContextData,
                                                   reasoningEffort: reasoningEffort)
        commitDeferredBindIfNeeded()
        onPromptDelivered?()
    }

    func unifiedToggleInputDidSubmitQuery(_ query: String) {}
    func unifiedToggleInputDidRequestVoiceSearch() {
        onVoiceSearchRequested?()
    }
    func unifiedToggleInputDidRequestAIVoiceChat() {
        onAIVoiceChatRequested?()
    }
    func unifiedToggleInputDidRequestAIChat(prefilledText: String) {}
    func unifiedToggleInputDidChangeHeight() {}
    func unifiedToggleInputDidCommitMode(_ mode: TextEntryMode) {}
    func unifiedToggleInputDidRequestFire() {}
    func unifiedToggleInputDidRequestAppMenu() {}
    func unifiedToggleInputDidChangeEditMode(_ isEditing: Bool) {
        onEditModeChange?(isEditing)
    }
}

// MARK: - Duck.ai Wide Event

extension AIChatContextualUTIHost {

    func sheetDismissed() {
        duckAIWideEventInstrumentation.sheetDismissedDuringGeneration(scope: duckAIWideEventFlowScope)
    }

    func promptDeliveryUpdated(wasQueued: Bool?, didSendBridgeMessage: Bool?) {
        duckAIWideEventInstrumentation.promptDeliveryUpdated(scope: duckAIWideEventFlowScope, wasQueued: wasQueued, didSendBridgeMessage: didSendBridgeMessage)
    }

    func frontendSubmissionAcknowledged() {
        duckAIWideEventInstrumentation.frontendSubmissionAcknowledged(scope: duckAIWideEventFlowScope)
    }

    func pageLoadFailed(error: Error) {
        duckAIWideEventInstrumentation.pageLoadFailed(scope: duckAIWideEventFlowScope, error: error)
    }

    /// Called when the contextual sheet's native input submits the initial prompt of a chat,
    /// which bypasses the UTI. Routes the wide-event start through the shared UTI coordinator
    /// so the in-flight flow receives the JS status updates that follow.
    func initialNativePromptSubmitted(hasPageContext: Bool) {
        coordinator.recordExternalPromptSubmitted(
            entryPoint: .contextualChat,
            inputMode: .keyboard,
            isFirstPrompt: true,
            hasPageContext: hasPageContext
        )
    }
}

// MARK: - AIChatContextualInputViewControllerDelegate (suggestions strip)

extension AIChatContextualUTIHost: AIChatContextualInputViewControllerDelegate {
    func contextualInputViewController(_ viewController: AIChatContextualInputViewController, didSelectSuggestion suggestion: ContextualSuggestedPrompt) {
        onSuggestionSelected?(suggestion)
    }

    func contextualInputViewController(_ viewController: AIChatContextualInputViewController, didSubmitPrompt prompt: String) {}
    func contextualInputViewController(_ viewController: AIChatContextualInputViewController, didSelectQuickAction action: AIChatContextualQuickAction) {
        onQuickActionSelected?(action)
    }
    func contextualInputViewControllerDidTapVoice(_ viewController: AIChatContextualInputViewController) {}
    func contextualInputViewControllerDidRemoveContextChip(_ viewController: AIChatContextualInputViewController) {}
}
