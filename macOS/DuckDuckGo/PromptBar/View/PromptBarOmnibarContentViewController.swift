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
/// backdrop instead of inside a browser window.
@MainActor
final class PromptBarOmnibarContentViewController: NSViewController {

    private enum Constants {
        static let cornerRadius: CGFloat = 16
        static let promptTopInset: CGFloat = 8
        /// Mirrors `MainView`'s text container insets.
        static let promptLeadingInset: CGFloat = 10
        static let promptTrailingInset: CGFloat = 78
        static let promptToControlsSpacing: CGFloat = 8
        /// The controls row's buttons hang off the suggestions view's top edge, which sits 4pt above
        /// the container's bottom: 28pt button + 8pt tool inset + that 4pt.
        static let controlsRowHeight: CGFloat = 40
        /// Placeholder for the initial frame, replaced by the first real measurement.
        static let nominalCollapsedHeight: CGFloat = 80
        static let backdropMaterial: NSVisualEffectView.Material = .hudWindow
    }

    private let omnibarController: AIChatOmnibarController
    private let containerViewController: AIChatOmnibarContainerViewController
    private let textViewController: AIChatOmnibarTextContainerViewController
    private let draftStore: EphemeralPromptDraftStore
    private let promptSubmitter: PromptBarPromptSubmitting

    /// The text controller's own view is a `MouseOverView` and swallows clicks, so wrap it to let the
    /// bottom strip through to the tool buttons behind. `MainView` does the same.
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
        // Final width from the outset: measuring before Auto Layout has established it makes the
        // prompt wrap short and over-report its height, and the panel then shrinks a line at a time
        // as layout catches up.
        view = NSView(frame: NSRect(x: 0, y: 0,
                                    width: PromptBarPlacement.preferredWidth,
                                    height: Constants.nominalCollapsedHeight))
        view.wantsLayer = true
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

    private func applyPassthroughHeight() {
        let passthroughHeight = containerViewController.totalPassthroughHeight
        promptPassthroughView.passthroughBottomHeight = passthroughHeight
        textViewController.setPassthroughBottomHeight(passthroughHeight)
    }

    // MARK: - Auxiliary UI

    /// A tool menu or the attachment picker taking key away must not dismiss the bar. Menus track on
    /// a nested run loop, so these arrive before the panel's own `didResignKey`.
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
        // AppKit won't hand key back to a non-activating panel, and without key there's no later
        // `didResignKey` to dismiss on — the bar would be stuck open.
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

    /// Attachments don't count: this reports the text field alone.
    var hasPromptText: Bool {
        !draftStore.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var preferredWindowContentSize: NSSize {
        // Wrapping depends on the final width, so resolve pending layout before measuring.
        if isViewLoaded {
            view.layoutSubtreeIfNeeded()
        }

        // `promptContentHeight`, not `calculateDesiredPanelHeight()`: the latter folds in a bottom
        // band for hosts that overlap their controls into it, which this one doesn't.
        let height = Constants.promptTopInset
            + textViewController.promptContentHeight
            + Constants.promptToControlsSpacing
            + Constants.controlsRowHeight
            + containerViewController.suggestionsHeight
            + containerViewController.additionalContentHeight

        return NSSize(width: PromptBarPlacement.preferredWidth, height: height)
    }

    func prepareForPresentation() {
        // So the presenter's own read of `preferredWindowContentSize` measures a laid-out prompt.
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
        // Read the screen before dismissal tears the window down, and dismiss before handing off: a
        // browser window raised under the still-key panel stays behind it.
        let screen = view.window?.screen
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
        // Unreachable while `.promptBar` has no suggestions; dismiss rather than sit open if it gains them.
        onSubmit?()
    }
}
