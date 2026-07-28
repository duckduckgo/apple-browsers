//
//  PromptBarOmnibarContentViewController.swift
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
import AppKit

/// The Prompt Bar's content: the address bar's own Duck.ai prompt views, hosted over a vibrancy
/// backdrop instead of inside a browser window. Both view controllers are used unmodified — what
/// differs between the two surfaces is declared in `DuckAIPromptSurface`.
@MainActor
final class PromptBarOmnibarContentViewController: NSViewController {

    private enum Constants {
        static let cornerRadius: CGFloat = 16
        /// Spotlight-like surfaces read better with a little air above the first line. The address bar
        /// gets this from the navigation bar's own padding; the panel has no chrome above the text.
        static let promptTopInset: CGFloat = 8
        /// Mirrors `AddressBarStyleProviding.aiChatOmnibarTextContainerLeadingPadding`.
        static let promptLeadingInset: CGFloat = 10
        /// Room for the submit and voice buttons the container draws at the trailing edge, matching
        /// `MainView`'s text container inset.
        static let promptTrailingInset: CGFloat = 78
        /// Clear air between the last line of the prompt and the controls row. Has to be explicit:
        /// the container pins the controls to its own bottom edge, so nothing else separates them.
        /// The container's `additionalContentHeight` contributes a further 5pt of top padding.
        static let promptToControlsSpacing: CGFloat = 8
        /// The controls row as the container lays it out. Its buttons hang off the suggestions view's
        /// top edge, which itself sits 4pt above the container's bottom — so the strip is the 28pt
        /// button plus an 8pt tool inset plus that 4pt, and the suggestions view's own height is
        /// accounted for separately.
        static let controlsRowHeight: CGFloat = 40
        /// Placeholder height for the initial frame, replaced by the first real measurement.
        static let nominalCollapsedHeight: CGFloat = 80
        static let backdropMaterial: NSVisualEffectView.Material = .hudWindow
    }

    private let omnibarController: AIChatOmnibarController
    private let containerViewController: AIChatOmnibarContainerViewController
    private let textViewController: AIChatOmnibarTextContainerViewController
    private let draftStore: EphemeralPromptDraftStore
    private let promptSubmitter: PromptBarPromptSubmitting

    /// Wraps the text view controller so clicks in the bottom strip reach the tool buttons behind it.
    /// The text controller's own view is a `MouseOverView`, which swallows them. `MainView` solves this
    /// the same way, except there the passthrough view is the container the text VC is added into.
    private let promptPassthroughView = PassthroughView()

    private var isMenuTracking = false
    private var lastPublishedContentHeight: CGFloat?

    var onPreferredWindowContentSizeChanged: ((NSSize) -> Void)?
    var onSubmit: (() -> Void)?

    init(omnibarController: AIChatOmnibarController,
         containerViewController: AIChatOmnibarContainerViewController,
         textViewController: AIChatOmnibarTextContainerViewController,
         draftStore: EphemeralPromptDraftStore,
         promptSubmitter: PromptBarPromptSubmitting) {
        self.omnibarController = omnibarController
        self.containerViewController = containerViewController
        self.textViewController = textViewController
        self.draftStore = draftStore
        self.promptSubmitter = promptSubmitter

        super.init(nibName: nil, bundle: nil)

        omnibarController.delegate = self
        textViewController.containerViewController = containerViewController
    }

    required init?(coder: NSCoder) {
        fatalError("PromptBarOmnibarContentViewController: Bad initializer")
    }

    override func loadView() {
        // The final width from the outset: the prompt's line wrapping — and so every height we
        // measure — is a function of it. Measuring before Auto Layout has established the real width
        // makes the text wrap short, over-reporting its height, and the panel then shrinks a line at
        // a time as layout catches up. Height is nominal; the first measurement replaces it.
        view = NSView(frame: NSRect(x: 0, y: 0,
                                    width: PromptBarPlacement.preferredWidth,
                                    height: Constants.nominalCollapsedHeight))
        view.wantsLayer = true
        // Clips the vibrancy and both child views to the panel's rounded shape; the window's own
        // shadow wraps the result.
        view.layer?.cornerRadius = Constants.cornerRadius
        view.layer?.masksToBounds = true

        setUpUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        subscribeToMenuTracking()
        wireHeightUpdates()
    }

    private func setUpUI() {
        let backdrop = NSVisualEffectView()
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.material = Constants.backdropMaterial
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.isEmphasized = true
        view.addSubview(backdrop)

        addChild(containerViewController)
        let containerView = containerViewController.view
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        addChild(textViewController)
        let promptView = textViewController.view
        promptView.translatesAutoresizingMaskIntoConstraints = false
        promptPassthroughView.translatesAutoresizingMaskIntoConstraints = false
        promptPassthroughView.addSubview(promptView)
        view.addSubview(promptPassthroughView)

        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            promptView.topAnchor.constraint(equalTo: promptPassthroughView.topAnchor),
            promptView.leadingAnchor.constraint(equalTo: promptPassthroughView.leadingAnchor),
            promptView.trailingAnchor.constraint(equalTo: promptPassthroughView.trailingAnchor),
            promptView.bottomAnchor.constraint(equalTo: promptPassthroughView.bottomAnchor),

            promptPassthroughView.topAnchor.constraint(equalTo: view.topAnchor, constant: Constants.promptTopInset),
            promptPassthroughView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.promptLeadingInset),
            promptPassthroughView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.promptTrailingInset),
            promptPassthroughView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Height

    private func wireHeightUpdates() {
        textViewController.heightDidChange = { [weak self] _ in
            self?.publishPreferredContentSize()
        }
        containerViewController.onSuggestionsHeightChanged = { [weak self] _ in
            self?.publishPreferredContentSize()
        }
        containerViewController.onPassthroughHeightNeedsUpdate = { [weak self] in
            self?.publishPreferredContentSize()
        }
    }

    private func publishPreferredContentSize() {
        applyPassthroughHeight()

        let size = preferredWindowContentSize
        // A resize re-lays out the prompt, which fires `heightDidChange` again. Without this the two
        // feed each other and the panel visibly settles over several frames.
        guard size.height != lastPublishedContentHeight else { return }
        lastPublishedContentHeight = size.height
        onPreferredWindowContentSizeChanged?(size)
    }

    /// Tells the prompt view to let clicks through in the bottom strip the container's tool row,
    /// attachments and suggestions occupy. Same plumbing as `MainViewController`.
    private func applyPassthroughHeight() {
        let passthroughHeight = containerViewController.totalPassthroughHeight
        promptPassthroughView.passthroughBottomHeight = passthroughHeight
        textViewController.setPassthroughBottomHeight(passthroughHeight)
    }

    // MARK: - Auxiliary UI

    /// A tool menu or the attachment picker taking key away must not dismiss the bar. Menus track on a
    /// nested run loop, so the notification arrives before the panel's own `didResignKey`.
    private func subscribeToMenuTracking() {
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(menuDidBeginTracking),
                                              name: NSMenu.didBeginTrackingNotification,
                                              object: nil)
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(menuDidEndTracking),
                                              name: NSMenu.didEndTrackingNotification,
                                              object: nil)
    }

    @objc private func menuDidBeginTracking() {
        isMenuTracking = true
    }

    @objc private func menuDidEndTracking() {
        isMenuTracking = false
        // AppKit doesn't hand key back to a non-activating panel on its own, and without key there's
        // no later `didResignKey` to dismiss on — so the bar would be stuck open.
        reclaimKeyIfStillVisible()
    }

    private func reclaimKeyIfStillVisible() {
        guard let window = view.window, window.isVisible, window.attachedSheet == nil else { return }
        window.makeKey()
        textViewController.focusTextViewWithCursorAtEnd()
    }
}

// MARK: - PromptBarContentHosting

extension PromptBarOmnibarContentViewController: PromptBarContentHosting {

    var viewController: NSViewController { self }

    var isPresentingAuxiliaryUI: Bool {
        isMenuTracking || view.window?.attachedSheet != nil || NSApp.modalWindow != nil
    }

    var preferredWindowContentSize: NSSize {
        // Resolve pending layout first: the prompt's line wrapping depends on its final width, and
        // measuring before that width is established over-reports the height.
        if isViewLoaded {
            view.layoutSubtreeIfNeeded()
        }

        // Stacked top to bottom: top inset, the prompt text, clear air, the controls row. Using the
        // text's *content* height (not `calculateDesiredPanelHeight()`, which folds in a bottom band
        // for a host that overlaps its controls into it, as the address bar does) keeps the spacing
        // below the prompt constant no matter how many lines it grows to.
        let height = Constants.promptTopInset
            + textViewController.promptContentHeight
            + Constants.promptToControlsSpacing
            + Constants.controlsRowHeight
            + containerViewController.suggestionsHeight
            + containerViewController.additionalContentHeight

        return NSSize(width: PromptBarPlacement.preferredWidth, height: height)
    }

    func prepareForPresentation() {
        // Loading the view up front means the presenter's own read of `preferredWindowContentSize`
        // measures a laid-out prompt rather than one that hasn't been sized yet.
        _ = view
        omnibarController.onOmnibarActivated()
        textViewController.startEventMonitoring()
        applyPassthroughHeight()
    }

    func focusPromptEditor() {
        textViewController.focusTextViewWithCursorAtEnd()
    }

    func resetAfterDismissal() {
        textViewController.stopEventMonitoring()
        containerViewController.cleanup()
        draftStore.reset()
        // The next presentation starts from an empty prompt, so the height it publishes will differ
        // from the one the dismissed bar ended on.
        lastPublishedContentHeight = nil
    }
}

// MARK: - AIChatOmnibarControllerDelegate

extension PromptBarOmnibarContentViewController: AIChatOmnibarControllerDelegate {

    func aiChatOmnibarControllerDidSubmit(_ controller: AIChatOmnibarController) {
        onSubmit?()
    }

    func aiChatOmnibarController(_ controller: AIChatOmnibarController,
                                 requestsSubmissionOf query: String,
                                 payload: AIChatNativePrompt) {
        // Read the screen before dismissal tears the window down.
        let screen = view.window?.screen
        // Dismiss first: a browser window raised under the still-key panel stays behind it.
        onSubmit?()
        promptSubmitter.submit(query: query, payload: payload, preferringWindowOn: screen)
    }

    func aiChatOmnibarControllerRequestsVoiceSession(_ controller: AIChatOmnibarController) {
        let screen = view.window?.screen
        onSubmit?()
        promptSubmitter.openVoiceSession(preferringWindowOn: screen)
    }

    func aiChatOmnibarController(_ controller: AIChatOmnibarController, didRequestNavigationToURL url: URL) {
        let screen = view.window?.screen
        onSubmit?()
        promptSubmitter.open(url: url, preferringWindowOn: screen)
    }

    func aiChatOmnibarController(_ controller: AIChatOmnibarController, didSelectSuggestion suggestion: AIChatSuggestion) {
        // Unreachable: `.promptBar` doesn't support suggestions. Dismiss rather than sit open if it
        // ever does.
        onSubmit?()
    }
}
