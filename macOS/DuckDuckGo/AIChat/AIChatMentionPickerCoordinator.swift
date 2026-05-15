//
//  AIChatMentionPickerCoordinator.swift
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

import AppKit
import PixelKit

/// Owns the omnibar `@`-mention picker's panel + view controller and drives its lifecycle.
///
/// The container view controller (`AIChatOmnibarTextContainerViewController`) detects
/// `@`-mention tokens via `AIChatMentionTokenDetector` and pipes them in here:
///
/// - `presentIfNeeded(for:anchoredTo:in:)` opens the panel (lazy-creating it on first use)
///   and positions it just above the `@` character. Anchoring uses the text view's
///   `firstRect(forCharacterRange:actualRange:)` so the panel tracks wrapped text correctly.
/// - `dismiss()` closes the panel and detaches it from the omnibar window.
///
/// Filtering (M11), keyboard navigation (M12), and accept-splicing (M12) layer on top of
/// this coordinator — they don't change its position/lifecycle model.
final class AIChatMentionPickerCoordinator {

    private enum Anchor {
        /// Gap between the `@` character's bottom edge and the panel's top edge.
        /// The picker drops down under the `@` (the omnibar typically sits near the top
        /// of the screen, so there isn't reliable room above the input).
        static let verticalOffset: CGFloat = 4
        /// How far the panel is allowed to extend past the left edge of the parent window
        /// before we clamp it back. Prevents the panel disappearing off-screen on narrow
        /// windows.
        static let minimumLeadingMargin: CGFloat = 8
    }

    private let omnibarController: AIChatOmnibarController
    private var panel: AIChatMentionPickerPanel?
    private var viewController: AIChatMentionPickerViewController?
    private weak var attachedToWindow: NSWindow?
    /// The text view the active token was last anchored against. Captured at
    /// `presentIfNeeded` time so the accept / splice path mutates the same storage that
    /// triggered the open.
    private weak var anchoredTextView: NSTextView?
    /// The token range from the most recent `presentIfNeeded`. We re-derive it from the
    /// detector at splice time (the user may have typed more characters since the panel
    /// last refreshed), but we keep this around as a fallback.
    private var lastTokenRange: NSRange?
    private var windowObservers: [NSObjectProtocol] = []
    /// `true` once `accept(attachment:)` fires during the current open session — used to
    /// decide between `mention_tab_chosen`/`mention_tab_removed` (already fired by accept)
    /// and the `mention_picker_canceled` pixel (fired by `dismiss` only when no accept ran).
    /// Reset to `false` on each hidden→visible transition in `presentIfNeeded`.
    private var didAcceptDuringPresentation = false

    /// `true` once the panel is on screen and attached as a child of the omnibar window.
    var isPresented: Bool { panel?.isVisible == true }

    /// `true` when the picker is on screen AND has a real selection (i.e. not the
    /// empty-state row). The text container VC checks this in `doCommandBy:` to decide
    /// whether to swallow arrow / Enter / Esc keystrokes.
    var canHandleKeyCommands: Bool {
        guard isPresented, let vc = viewController else { return false }
        return !vc.isShowingEmptyState
    }

    init(omnibarController: AIChatOmnibarController) {
        self.omnibarController = omnibarController
    }

    deinit {
        // Drop the notification-center registrations synchronously — they don't touch UI.
        // The panel itself is owned by its parent window (via `addChildWindow`); when the
        // parent window closes, AppKit tears the child down. We deliberately avoid calling
        // `dismiss()` here because it's `@MainActor` and would require an extra Task hop
        // that captures `self` after deinit has started.
        let center = NotificationCenter.default
        windowObservers.forEach { center.removeObserver($0) }
    }

    /// Shows the picker for the given mention token, anchored to the `@` character in the
    /// supplied text view. Idempotent — calling again with an updated token just repositions
    /// and refreshes the row contents.
    @MainActor
    func presentIfNeeded(for token: AIChatMentionToken, anchoredTo textView: NSTextView, in window: NSWindow) {
        // Detect a fresh "the picker is becoming visible now" transition so the shown pixel
        // fires once per open/close cycle rather than every refresh-on-keystroke. Capture
        // BEFORE `ensurePanel` because that lazy-create makes a non-visible panel either way.
        let wasPresented = panel?.isVisible == true

        let viewController = ensureViewController()
        let panel = ensurePanel(hosting: viewController)

        // Refresh the rows. The filter (M11) applies `token.query` over title+url with
        // a scoring rule that prefers title matches; when the query is empty (just typed `@`)
        // the full open-tabs list comes back unchanged.
        let attachedIds = Set(omnibarController.activeTabAttachments.map(\.id))
        let currentTabId = omnibarController.currentTabUUID
        let openTabs = omnibarController.openTabsForOmnibarPicker()
        let filtered = AIChatMentionPickerFilter.filter(openTabs, query: token.query, currentTabId: currentTabId)
        viewController.setTabs(
            filtered,
            currentTabId: currentTabId,
            attachedTabIds: attachedIds
        )
        viewController.onAccept = { [weak self] attachment in
            self?.accept(attachment: attachment)
        }
        anchoredTextView = textView
        lastTokenRange = token.range

        // Attach to the omnibar window once. If the parent window changed (e.g. omnibar
        // re-presented in a different window), detach first.
        if let existingParent = attachedToWindow, existingParent !== window {
            existingParent.removeChildWindow(panel)
            attachedToWindow = nil
        }
        if attachedToWindow == nil {
            window.addChildWindow(panel, ordered: .above)
            attachedToWindow = window
            installWindowObservers(window: window, textView: textView)
        }

        // Size + reposition every time, so the panel tracks new content and current caret.
        let size = viewController.fittingContentSize
        panel.setContentSize(size)
        repositionPanel(textView: textView, tokenRange: token.range)

        panel.orderFront(nil)

        if !wasPresented {
            // Fresh open: reset the per-session accept flag and fire the shown pixel.
            // Subsequent calls to `presentIfNeeded` within the same session (re-position on
            // each keystroke) intentionally don't re-fire.
            didAcceptDuringPresentation = false
            PixelKit.fire(
                AIChatPixel.aiChatAddressBarMentionPickerShown,
                frequency: .dailyAndCount,
                includeAppVersionParameter: true
            )
        }
    }

    /// Hides the panel and detaches it from the omnibar window.
    @MainActor
    func dismiss() {
        guard let panel else { return }
        // Capture pre-dismiss state so the canceled pixel only fires for a real
        // hidden→visible→hidden cycle that wrapped no accept. A no-op dismiss (panel never
        // shown, or accept just fired) must not count as a cancel.
        let wasPresented = panel.isVisible
        let shouldFireCanceled = wasPresented && !didAcceptDuringPresentation

        if let parent = attachedToWindow {
            parent.removeChildWindow(panel)
        }
        attachedToWindow = nil
        removeWindowObservers()
        panel.orderOut(nil)
        lastTokenRange = nil
        anchoredTextView = nil

        if shouldFireCanceled {
            PixelKit.fire(
                AIChatPixel.aiChatAddressBarMentionPickerCanceled,
                frequency: .dailyAndCount,
                includeAppVersionParameter: true
            )
        }
    }

    // MARK: - Keyboard navigation

    /// Moves the highlight one row down (wraps from last to first).
    @MainActor
    func moveHighlightDown() {
        viewController?.moveHighlightDown()
    }

    /// Moves the highlight one row up (wraps from first to last).
    @MainActor
    func moveHighlightUp() {
        viewController?.moveHighlightUp()
    }

    /// Called when the user presses Enter while the picker is open.
    ///
    /// - Returns: `true` if the picker consumed the Enter (i.e. it had a real row
    ///   highlighted, accepted it, and dismissed). `false` means the picker isn't able to
    ///   accept anything (empty-state mode or no highlight) and the caller should fall
    ///   through to its normal Enter handling (e.g. the omnibar's submit).
    @MainActor
    func acceptHighlighted() -> Bool {
        guard let vc = viewController, !vc.isShowingEmptyState else { return false }
        guard let tab = vc.highlightedTab else { return false }
        accept(attachment: tab)
        return true
    }

    /// Core accept logic shared between click-on-row (via the VC's `onAccept` callback)
    /// and Enter-on-highlight (via `acceptHighlighted`). Splices the `@token` substring
    /// out of the anchored text view and toggles the corresponding tab attachment, then
    /// dismisses the picker.
    @MainActor
    private func accept(attachment: AIChatTabAttachment) {
        // Read attached state BEFORE the toggle so we know which pixel describes the
        // user's action (chosen vs removed) — the toggle flips it, so post-toggle the
        // signal would be inverted.
        let wasAttached = omnibarController.activeTabAttachments.contains(where: { $0.id == attachment.id })
        // Set the accept flag BEFORE `spliceTokenFromTextView()` — the splice's
        // `didChangeText` posts `NSText.didChangeNotification` synchronously, which
        // cascades into the omnibar's `textDidChange → updateMentionTokenDetection →
        // dismiss()` path. If the flag isn't already set when that re-entrant `dismiss`
        // runs, it sees `didAcceptDuringPresentation == false` and erroneously fires the
        // `mention_picker_canceled` pixel alongside the chosen/removed pixel below.
        didAcceptDuringPresentation = true
        spliceTokenFromTextView()
        omnibarController.toggleTabAttachment(attachment)
        let pixel: AIChatPixel = wasAttached
            ? .aiChatAddressBarMentionTabRemoved
            : .aiChatAddressBarMentionTabChosen
        PixelKit.fire(pixel, frequency: .dailyAndCount, includeAppVersionParameter: true)
        dismiss()
    }

    /// Removes the `@token` substring (including the leading `@`) from the omnibar input
    /// and places the caret where the `@` was. Re-detects the token range at splice time
    /// in case the caret moved between the last `presentIfNeeded` and now.
    @MainActor
    private func spliceTokenFromTextView() {
        guard let textView = anchoredTextView else { return }
        let caret = textView.selectedRange.location
        let rangeToRemove: NSRange
        if let liveToken = AIChatMentionTokenDetector.token(in: textView.string, caret: caret) {
            rangeToRemove = liveToken.range
        } else if let cached = lastTokenRange {
            // Fall back to the range captured at present time. Shouldn't normally happen
            // — if the picker is on screen, the detector should still find the token —
            // but defend against caret-out-of-token races regardless.
            rangeToRemove = cached
        } else {
            return
        }
        // Use the text view's editing API rather than mutating textStorage directly so
        // selection, undo, and `textViewDidChange:` callbacks all fire correctly.
        if textView.shouldChangeText(in: rangeToRemove, replacementString: "") {
            textView.replaceCharacters(in: rangeToRemove, with: "")
            textView.didChangeText()
            // Caret lands where the `@` was.
            textView.selectedRange = NSRange(location: rangeToRemove.location, length: 0)
        }
    }

    // MARK: - Lazy construction

    private func ensureViewController() -> AIChatMentionPickerViewController {
        if let viewController { return viewController }
        let vc = AIChatMentionPickerViewController()
        // Force-load the view so `fittingContentSize` is computable before the panel is shown.
        _ = vc.view
        self.viewController = vc
        return vc
    }

    private func ensurePanel(hosting viewController: AIChatMentionPickerViewController) -> AIChatMentionPickerPanel {
        if let panel { return panel }
        let panel = AIChatMentionPickerPanel(contentViewController: viewController)
        self.panel = panel
        return panel
    }

    // MARK: - Positioning

    @MainActor
    private func repositionPanel(textView: NSTextView, tokenRange: NSRange) {
        guard let panel, let window = attachedToWindow, tokenRange.length > 0 else { return }
        // First char of the token is the `@` — that's our anchor point.
        let atRange = NSRange(location: tokenRange.location, length: 1)
        let rectInScreen = textView.firstRect(forCharacterRange: atRange, actualRange: nil)
        // `firstRect` returns screen coordinates. The panel's frame is also in screen
        // coordinates, so we can position directly. Position the panel below the `@` —
        // in screen coordinates (Y increases up), the @'s bottom edge is `minY`, so
        // panel.top = minY - gap, and panel.origin.y (bottom-left) = top - panel.height.
        let panelHeight = panel.frame.height
        var panelOrigin = NSPoint(
            x: rectInScreen.minX,
            y: rectInScreen.minY - Anchor.verticalOffset - panelHeight
        )

        // Clamp horizontally so the panel doesn't drift off the parent window's left edge.
        let parentMinX = window.frame.minX + Anchor.minimumLeadingMargin
        if panelOrigin.x < parentMinX {
            panelOrigin.x = parentMinX
        }
        let panelFrame = NSRect(origin: panelOrigin, size: NSSize(width: panel.frame.width, height: panelHeight))
        panel.setFrame(panelFrame, display: true)
    }

    // MARK: - Window observers

    private func installWindowObservers(window: NSWindow, textView: NSTextView) {
        removeWindowObservers()
        let center = NotificationCenter.default

        // If the omnibar window resigns key (user switches apps / clicks another window),
        // dismiss the picker. We don't try to keep it floating around while attention is
        // elsewhere — it's tied to active typing.
        let resignKey = center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        // When the omnibar window moves or resizes (e.g. the panel grows as suggestions
        // appear), reposition the picker so it stays anchored to the `@`. We re-fetch the
        // token range from the text view's current selection to handle the case where the
        // user scrolled while typing.
        let didMove = center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self, weak textView] _ in
            Task { @MainActor in
                guard let self, let textView else { return }
                self.repositionIfStillTracking(textView: textView)
            }
        }
        let didResize = center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self, weak textView] _ in
            Task { @MainActor in
                guard let self, let textView else { return }
                self.repositionIfStillTracking(textView: textView)
            }
        }
        windowObservers = [resignKey, didMove, didResize]
    }

    private func removeWindowObservers() {
        let center = NotificationCenter.default
        windowObservers.forEach { center.removeObserver($0) }
        windowObservers.removeAll()
    }

    @MainActor
    private func repositionIfStillTracking(textView: NSTextView) {
        // If the caret is no longer inside an @-token, the next text-change callback will
        // dismiss us anyway; here we just keep the existing panel aligned with the @.
        guard isPresented,
              let token = AIChatMentionTokenDetector.token(in: textView.string, caret: textView.selectedRange.location)
        else { return }
        repositionPanel(textView: textView, tokenRange: token.range)
    }
}
