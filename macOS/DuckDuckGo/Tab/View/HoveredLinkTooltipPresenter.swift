//
//  HoveredLinkTooltipPresenter.swift
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
import os.log

/// Owns the presentation of the hovered-link URL tooltip.
///
/// Mirrors Chrome's behavior:
///
/// - In a regular (non-fullscreen, non-zoomed) browser window, when the cursor
///   is far from the bottom edge of the window, the tooltip is shown inside the
///   window in the bottom-leading corner (the existing in-window subview owned
///   by `BrowserTabViewController`).
///
/// - When the cursor is near the bottom of the window AND the window has free
///   screen space beneath it, the tooltip floats *below* the parent window in a
///   borderless child `NSWindow`, so it doesn't cover the link being hovered.
///
/// - When the parent window is full-screen or zoomed (no space beneath it on
///   screen), the tooltip is shown *above* the cursor in that same borderless
///   child window — matching the spec from
///   https://app.asana.com/0/0/1204013224241988
///
/// The presenter also fixes a stuck-tooltip bug: when the Web Inspector is
/// shown and the cursor moves from the page area into the inspector pane, the
/// in-page `mouseout` event is not fired and the tooltip would otherwise stay
/// visible. The presenter dismisses the tooltip whenever the cursor leaves the
/// `webView` bounds while a URL is being shown — which covers the
/// inspector-take-over case as well as any other case where the cursor exits
/// the web content area without a clean `mouseout`.
@MainActor
final class HoveredLinkTooltipPresenter {

    // MARK: - Constants

    /// Distance from the bottom of the parent window (in window-coordinate
    /// points) within which the cursor is considered "near the bottom edge"
    /// — at which point the in-window tooltip is replaced with the floating
    /// presentation so it doesn't cover the link.
    static let nearBottomEdgeThreshold: CGFloat = 96

    /// Vertical offset above the cursor for the `.aboveCursor` presentation.
    static let aboveCursorOffset: CGFloat = 24

    /// Vertical gap between the parent window's bottom edge and the floating
    /// tooltip in the `.belowWindow` presentation.
    static let belowWindowGap: CGFloat = 4

    /// Horizontal inset (from the parent window's leading edge) for the
    /// `.belowWindow` presentation.
    static let belowWindowLeadingInset: CGFloat = 0

    /// Accessibility identifier of the floating tooltip window, used by UI
    /// tests to assert position.
    static let floatingWindowAccessibilityIdentifier = "HoveredLinkTooltip.floatingWindow"

    /// Accessibility identifier of the floating tooltip's text label.
    static let floatingLabelAccessibilityIdentifier = "HoveredLinkTooltip.floatingLabel"

    /// Accessibility identifier of the in-window tooltip's text label.
    static let inWindowLabelAccessibilityIdentifier = "HoveredLinkTooltip.inWindowLabel"

    /// Accessibility identifier of the in-window tooltip's container view.
    /// (Used by UI tests to assert the in-window presentation is being shown.)
    static let inWindowContainerAccessibilityIdentifier = "HoveredLinkTooltip.inWindowContainer"

    // MARK: - Position

    enum Position: Equatable {
        /// Pinned to the bottom-leading corner inside the host view.
        case insideBottomLeft
        /// Floating just below the parent window's bottom edge, on screen.
        case belowWindow
        /// Floating above the cursor's last known location, on screen.
        case aboveCursor(cursorPointInScreen: NSPoint)
    }

    // MARK: - Configuration

    private weak var inWindowContainer: NSView?
    private weak var inWindowLabel: NSTextField?
    private weak var hostView: NSView?
    private weak var webView: NSView?

    // MARK: - State

    private(set) var currentURL: URL?
    private(set) var currentPosition: Position = .insideBottomLeft
    private var lastMouseLocationInWindow: NSPoint?
    private var fadeWorkItem: DispatchWorkItem?

    // MARK: - Floating window components

    private var floatingWindow: HoveredLinkTooltipWindow?
    private var floatingLabel: NSTextField?
    private var floatingContainer: ColorView?

    // MARK: - Init

    init(inWindowContainer: NSView, inWindowLabel: NSTextField, hostView: NSView) {
        self.inWindowContainer = inWindowContainer
        self.inWindowLabel = inWindowLabel
        self.hostView = hostView

        inWindowLabel.setAccessibilityIdentifier(Self.inWindowLabelAccessibilityIdentifier)
        inWindowContainer.setAccessibilityIdentifier(Self.inWindowContainerAccessibilityIdentifier)
    }

    deinit {
        fadeWorkItem?.cancel()
        // The floating window is a child of the parent window — when the
        // parent goes away, AppKit detaches and releases the child window
        // automatically. We just need to make sure it's hidden.
        let window = floatingWindow
        DispatchQueue.main.async {
            if let parent = window?.parent {
                parent.removeChildWindow(window!)
            }
            window?.orderOut(nil)
        }
    }

    // MARK: - Web view tracking

    /// The WebView the tooltip is attached to. Used to detect when the cursor
    /// has left the web content area (e.g. into the Web Inspector pane) so we
    /// can dismiss a stuck tooltip.
    func setWebView(_ webView: NSView?) {
        self.webView = webView
    }

    // MARK: - Mouse tracking

    /// Called by the host view controller on every `.mouseMoved` event in the
    /// parent window so the presenter can:
    /// 1. Re-evaluate the tooltip position (cursor may have entered/left the
    ///    bottom edge band).
    /// 2. Detect when the cursor has moved out of the WebView's bounds while a
    ///    tooltip is being shown — typically because the cursor has moved into
    ///    the Web Inspector pane — and dismiss the tooltip in that case.
    func mouseDidMove(to locationInWindow: NSPoint) {
        lastMouseLocationInWindow = locationInWindow

        guard currentURL != nil else { return }

        if hasCursorLeftWebView(locationInWindow: locationInWindow) {
            // The in-page hover script never fired its `mouseout` (the cursor
            // didn't move via the page DOM, e.g. it went into the inspector).
            // Dismiss the tooltip explicitly.
            update(url: nil, animated: false)
            return
        }

        // Re-evaluate placement; cursor may have moved into / out of the
        // bottom-edge band.
        present(url: currentURL, position: positionForCurrentState(), animated: false)
    }

    /// Force-dismiss without animation. Called when the window resigns key,
    /// the view disappears, or the tab is switched.
    func reset() {
        fadeWorkItem?.cancel()
        fadeWorkItem = nil
        currentURL = nil
        if let inWindowContainer {
            inWindowContainer.alphaValue = 0
        }
        floatingWindow?.alphaValue = 0
        floatingWindow?.orderOut(nil)
    }

    // MARK: - Update

    /// Show or hide the tooltip for `url`. If `url` is `nil` the tooltip is
    /// faded out.
    func update(url: URL?, animated: Bool = true) {
        // Cancel any pending fade.
        fadeWorkItem?.cancel()
        fadeWorkItem = nil

        currentURL = url
        let position = positionForCurrentState()
        present(url: url, position: position, animated: animated)
    }

    // MARK: - Presentation

    private func present(url: URL?, position: Position, animated: Bool) {
        currentPosition = position

        let urlString = url?.absoluteString ?? ""

        switch position {
        case .insideBottomLeft:
            tearDownFloatingWindow(animated: animated)
            showInWindow(text: urlString, visible: url != nil, animated: animated)

        case .belowWindow:
            hideInWindow(animated: false)
            ensureFloatingWindow()
            updateFloatingLabel(text: urlString)
            positionFloatingWindowBelowParent()
            setFloatingVisible(url != nil, animated: animated)

        case .aboveCursor(let cursorPointInScreen):
            hideInWindow(animated: false)
            ensureFloatingWindow()
            updateFloatingLabel(text: urlString)
            positionFloatingWindowAboveCursor(cursorPointInScreen: cursorPointInScreen)
            setFloatingVisible(url != nil, animated: animated)
        }
    }

    // MARK: - In-window presentation

    private func showInWindow(text: String, visible: Bool, animated: Bool) {
        guard let inWindowContainer, let inWindowLabel else { return }

        if visible {
            // schedule a fade in (matches the original 0.5s reveal delay)
            if inWindowContainer.alphaValue < 1 {
                if animated {
                    let work = DispatchWorkItem { [weak inWindowContainer, weak inWindowLabel] in
                        inWindowLabel?.stringValue = text
                        inWindowContainer?.animator().alphaValue = 1
                    }
                    fadeWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
                } else {
                    inWindowLabel.stringValue = text
                    inWindowContainer.alphaValue = 1
                }
            } else {
                inWindowLabel.stringValue = text
            }
        } else {
            hideInWindow(animated: animated)
        }
    }

    private func hideInWindow(animated: Bool) {
        guard let inWindowContainer else { return }
        guard inWindowContainer.alphaValue > 0 else { return }

        if animated {
            let work = DispatchWorkItem { [weak inWindowContainer] in
                inWindowContainer?.animator().alphaValue = 0
            }
            fadeWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        } else {
            inWindowContainer.alphaValue = 0
        }
    }

    // MARK: - Floating window presentation

    private func ensureFloatingWindow() {
        guard floatingWindow == nil else { return }
        guard let parentWindow = hostView?.window else { return }

        let container = ColorView(frame: .zero,
                                  backgroundColor: .browserTabBackground,
                                  cornerRadius: 4)

        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byClipping
        label.textColor = .labelColor
        label.maximumNumberOfLines = 1
        label.setAccessibilityIdentifier(Self.floatingLabelAccessibilityIdentifier)

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            container.bottomAnchor.constraint(equalTo: label.bottomAnchor, constant: 6)
        ])

        let window = HoveredLinkTooltipWindow(contentView: container)
        window.setAccessibilityIdentifier(Self.floatingWindowAccessibilityIdentifier)
        // Start hidden so we can fade it in.
        window.alphaValue = 0
        parentWindow.addChildWindow(window, ordered: .above)

        self.floatingWindow = window
        self.floatingLabel = label
        self.floatingContainer = container
    }

    private func updateFloatingLabel(text: String) {
        floatingLabel?.stringValue = text
        // Force the window to size itself to the label.
        floatingWindow?.contentView?.layoutSubtreeIfNeeded()
        if let fitting = floatingContainer?.fittingSize, fitting.width > 0, fitting.height > 0 {
            var frame = floatingWindow?.frame ?? .zero
            frame.size = fitting
            floatingWindow?.setFrame(frame, display: false)
        }
    }

    private func positionFloatingWindowBelowParent() {
        guard let floatingWindow, let parentWindow = hostView?.window else { return }
        let parentFrame = parentWindow.frame
        let size = floatingWindow.frame.size
        let origin = NSPoint(
            x: parentFrame.minX + Self.belowWindowLeadingInset,
            y: parentFrame.minY - size.height - Self.belowWindowGap
        )
        floatingWindow.setFrameOrigin(clampToScreen(origin: origin, size: size, screen: parentWindow.screen))
    }

    private func positionFloatingWindowAboveCursor(cursorPointInScreen: NSPoint) {
        guard let floatingWindow else { return }
        let size = floatingWindow.frame.size
        let origin = NSPoint(
            x: cursorPointInScreen.x,
            y: cursorPointInScreen.y + Self.aboveCursorOffset
        )
        floatingWindow.setFrameOrigin(clampToScreen(origin: origin, size: size, screen: hostView?.window?.screen))
    }

    private func clampToScreen(origin: NSPoint, size: CGSize, screen: NSScreen?) -> NSPoint {
        guard let screenFrame = screen?.frame else { return origin }
        var clamped = origin
        if clamped.x < screenFrame.minX { clamped.x = screenFrame.minX }
        if clamped.x + size.width > screenFrame.maxX { clamped.x = screenFrame.maxX - size.width }
        if clamped.y < screenFrame.minY { clamped.y = screenFrame.minY }
        if clamped.y + size.height > screenFrame.maxY { clamped.y = screenFrame.maxY - size.height }
        return clamped
    }

    private func setFloatingVisible(_ visible: Bool, animated: Bool) {
        guard let floatingWindow else { return }
        if visible {
            if floatingWindow.alphaValue < 1 {
                if animated {
                    let work = DispatchWorkItem { [weak floatingWindow] in
                        floatingWindow?.animator().alphaValue = 1
                    }
                    fadeWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
                } else {
                    floatingWindow.alphaValue = 1
                }
            }
        } else {
            if animated {
                let work = DispatchWorkItem { [weak floatingWindow] in
                    floatingWindow?.animator().alphaValue = 0
                }
                fadeWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
            } else {
                floatingWindow.alphaValue = 0
            }
        }
    }

    private func tearDownFloatingWindow(animated: Bool) {
        guard let floatingWindow else { return }
        if animated {
            floatingWindow.animator().alphaValue = 0
        } else {
            floatingWindow.alphaValue = 0
        }
    }

    // MARK: - Position calculation (visible for testing)

    /// Returns the position the tooltip should occupy given the host view's
    /// current state, using the last-known cursor location.
    func positionForCurrentState() -> Position {
        return Self.computePosition(
            mouseLocationInWindow: lastMouseLocationInWindow,
            window: hostView?.window,
            hostBounds: hostView?.bounds ?? .zero
        )
    }

    /// Pure function that decides which presentation to use given the inputs.
    /// Exposed at file scope so that unit tests can verify it without spinning
    /// up a window.
    static func computePosition(
        mouseLocationInWindow mouse: NSPoint?,
        window: NSWindow?,
        hostBounds: NSRect
    ) -> Position {
        guard let window else { return .insideBottomLeft }

        let inputs = WindowInputs(
            isFullScreen: window.styleMask.contains(.fullScreen),
            isZoomed: window.isZoomed,
            windowBottom: window.frame.minY,
            screenVisibleFrameBottom: window.screen?.visibleFrame.minY
        )
        let cursorInScreen = mouse.map { window.convertPoint(toScreen: $0) }

        return computePosition(
            mouseLocationInWindow: mouse,
            cursorPointInScreen: cursorInScreen,
            hostBounds: hostBounds,
            inputs: inputs
        )
    }

    /// Pure-data version of `computePosition` for unit testing — none of the
    /// inputs are AppKit objects.
    struct WindowInputs: Equatable {
        let isFullScreen: Bool
        let isZoomed: Bool
        let windowBottom: CGFloat
        /// `nil` when the window is offscreen / has no associated screen.
        let screenVisibleFrameBottom: CGFloat?
    }

    static func computePosition(
        mouseLocationInWindow mouse: NSPoint?,
        cursorPointInScreen: NSPoint?,
        hostBounds: NSRect,
        inputs: WindowInputs
    ) -> Position {
        let canFloatBelow = !inputs.isFullScreen
            && !inputs.isZoomed
            && hasRoomBelowWindow(inputs: inputs)

        if !canFloatBelow {
            if let mouse = mouse, isMouseNearBottom(mouse, hostBounds: hostBounds) {
                return .aboveCursor(cursorPointInScreen: cursorPointInScreen ?? .zero)
            }
            return .insideBottomLeft
        }

        if let mouse = mouse, isMouseNearBottom(mouse, hostBounds: hostBounds) {
            return .belowWindow
        }
        return .insideBottomLeft
    }

    static func hasRoomBelowWindow(_ window: NSWindow) -> Bool {
        let inputs = WindowInputs(
            isFullScreen: window.styleMask.contains(.fullScreen),
            isZoomed: window.isZoomed,
            windowBottom: window.frame.minY,
            screenVisibleFrameBottom: window.screen?.visibleFrame.minY
        )
        return hasRoomBelowWindow(inputs: inputs)
    }

    static func hasRoomBelowWindow(inputs: WindowInputs) -> Bool {
        guard let screenBottom = inputs.screenVisibleFrameBottom else { return false }
        return inputs.windowBottom - screenBottom > nearBottomEdgeThreshold
    }

    static func isMouseNearBottom(_ mouseInWindow: NSPoint, hostBounds: NSRect) -> Bool {
        return mouseInWindow.y < hostBounds.minY + nearBottomEdgeThreshold
    }

    // MARK: - WebView bounds check

    /// Returns `true` if `locationInWindow` falls outside the WebView's bounds
    /// in window coordinates. Used to detect when the cursor has moved into a
    /// sibling view (e.g. the Web Inspector) so we can dismiss a stuck
    /// tooltip.
    private func hasCursorLeftWebView(locationInWindow: NSPoint) -> Bool {
        guard let webView, let window = webView.window else { return false }
        let webViewFrameInWindow = webView.convert(webView.bounds, to: nil)
        // We only care if the cursor moved to a *sibling* view in the same
        // window — moving outside the window entirely is fine and is handled
        // by `windowDidResignKey` elsewhere.
        guard window === hostView?.window else { return false }
        return !webViewFrameInWindow.contains(locationInWindow)
    }
}

// MARK: - Borderless child window used for the floating presentations.

@MainActor
final class HoveredLinkTooltipWindow: NSWindow {

    init(contentView: NSView) {
        super.init(contentRect: NSRect(origin: .zero, size: contentView.fittingSize),
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)
        self.isReleasedWhenClosed = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.level = .floating
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary, .canJoinAllSpaces]
        self.hidesOnDeactivate = false
        self.animationBehavior = .none
        self.contentView = contentView
    }

    // The tooltip should never become key — it's purely a passive overlay.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
