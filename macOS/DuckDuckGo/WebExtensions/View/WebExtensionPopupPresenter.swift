//
//  WebExtensionPopupPresenter.swift
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
import ConcurrencyExtensions
import WebExtensions
import WebKit

/// Borderless panel that hosts a web extension popup.
///
/// Used in place of `WKWebExtensionAction.popupPopover` so the visible shape stays under our
/// control. On macOS 26 the popover chrome draws its own rounded corners that we cannot clip
/// from outside, and extension popups such as Dark Reader paint a square page over them, which
/// leaves the frame corners showing around the page. This panel draws square corners instead.
final class WebExtensionPopupPanel: NSPanel {

    override var canBecomeKey: Bool { true }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .popUpMenu
        animationBehavior = .none
        hidesOnDeactivate = true
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.transient, .ignoresCycle]
    }
}

/// Presents web extension action popups in a square-cornered panel.
///
/// Only one popup is shown at a time, which matches how `NSPopover` behaved before.
@available(macOS 15.4, *)
@MainActor
final class WebExtensionPopupPresenter {

    private enum Constants {
        /// Square corners are the point of this panel, so the radius stays at zero.
        static let cornerRadius: CGFloat = 0

        /// Gap between the toolbar button and the popup.
        static let verticalOffset: CGFloat = 4

        /// Used until the popup page reports the size it wants.
        static let fallbackSize = NSSize(width: 360, height: 480)

        /// Keeps a popup that reports an unusable size from covering the screen.
        static let minimumSize = NSSize(width: 100, height: 100)
    }

    private var panel: WebExtensionPopupPanel?
    private var shownContext: WKWebExtensionContext?
    private weak var shownAction: WKWebExtension.Action?
    private weak var anchorButton: NSView?
    private weak var popupWebView: WKWebView?
    private var sizeObservation: NSKeyValueObservation?
    private var clickMonitor: Any?

    /// Whether the popup of the given extension is on screen.
    func isShown(for context: WKWebExtensionContext) -> Bool {
        panel?.isVisible == true && shownContext?.uniqueIdentifier == context.uniqueIdentifier
    }

    // MARK: - Show

    func present(_ action: WKWebExtension.Action,
                 for context: WKWebExtensionContext,
                 from button: NSView) {
        guard let popupWebView = action.popupWebView else { return }
        guard let parentWindow = button.window else {
            assertionFailure("Web extension toolbar button has no window")
            return
        }

        // A popup of another extension, or of another window, must go away first.
        close()

        let panel = WebExtensionPopupPanel()
        self.panel = panel
        self.shownContext = context
        self.shownAction = action
        self.anchorButton = button
        self.popupWebView = popupWebView

        let contentView = NSView(frame: NSRect(origin: .zero, size: preferredSize(for: action)))
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = Constants.cornerRadius
        contentView.layer?.masksToBounds = true

        popupWebView.frame = contentView.bounds
        popupWebView.autoresizingMask = [.width, .height]
        contentView.addSubview(popupWebView)
        panel.contentView = contentView

        panel.setFrame(frame(forContentSize: contentView.bounds.size, below: button, in: parentWindow),
                       display: false)

        parentWindow.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        panel.makeKey()

        observePopupSize(of: action)
        startWatchingForClicksOutside()
    }

    /// Follows the size WebKit computes for the popup page.
    ///
    /// WebKit reports it through the `contentSize` of the popover it would have presented, and
    /// keeps it up to date while the page reflows. We never show that popover, so its rounded
    /// chrome never appears; we read it only as the source of the size.
    private func observePopupSize(of action: WKWebExtension.Action) {
        guard let popupPopover = action.popupPopover else { return }

        sizeObservation = popupPopover.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.resizeToPopupContent()
            }
        }
    }

    private func resizeToPopupContent() {
        guard let panel, panel.isVisible,
              let shownAction,
              let button = anchorButton,
              let parentWindow = button.window else { return }

        let size = preferredSize(for: shownAction)
        guard size != panel.frame.size else { return }

        panel.setFrame(frame(forContentSize: size, below: button, in: parentWindow), display: true)
    }

    private func preferredSize(for action: WKWebExtension.Action) -> NSSize {
        let reported = action.popupPopover?.contentSize ?? .zero
        guard reported.width >= Constants.minimumSize.width,
              reported.height >= Constants.minimumSize.height else {
            return Constants.fallbackSize
        }
        return reported
    }

    /// Positions the popup under the button, kept inside the screen.
    private func frame(forContentSize size: NSSize, below button: NSView, in parentWindow: NSWindow) -> NSRect {
        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = parentWindow.convertToScreen(buttonRectInWindow)

        var origin = NSPoint(x: buttonRectOnScreen.midX - size.width / 2,
                             y: buttonRectOnScreen.minY - size.height - Constants.verticalOffset)

        if let screenFrame = parentWindow.screen?.visibleFrame {
            origin.x = min(max(screenFrame.minX, origin.x), screenFrame.maxX - size.width)
            // Flip above the button when there is no room below.
            if origin.y < screenFrame.minY {
                let above = buttonRectOnScreen.maxY + Constants.verticalOffset
                origin.y = above + size.height <= screenFrame.maxY ? above : screenFrame.minY
            }
        }

        return NSRect(origin: origin, size: size)
    }

    // MARK: - Close

    /// Closes the popup on a click that lands neither in the popup nor on its button.
    ///
    /// The button needs the exception so that a click on it reaches the button action, which
    /// closes the popup itself. Without it the popup would close here and the action would
    /// then reopen it, and the button would never toggle the popup off.
    private func startWatchingForClicksOutside() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let clickedWindow = event.window
            let location = event.locationInWindow

            MainActor.assumeMainThread {
                self?.closeIfClickLandsOutside(in: clickedWindow, at: location)
            }

            return event
        }
    }

    private func closeIfClickLandsOutside(in clickedWindow: NSWindow?, at location: NSPoint) {
        guard let panel, panel.isVisible else { return }

        if clickedWindow === panel { return }

        if let button = anchorButton, clickedWindow === button.window {
            let pointInButton = button.convert(location, from: nil)
            if button.bounds.contains(pointInButton) { return }
        }

        close()
    }

    func close() {
        guard let panel else { return }

        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }

        sizeObservation?.invalidate()
        sizeObservation = nil

        // The web view belongs to WebKit, so hand it back rather than leaving it in our panel.
        popupWebView?.removeFromSuperview()
        popupWebView = nil

        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil

        shownAction?.closePopup()
        shownAction = nil
        shownContext = nil
        anchorButton = nil
    }
}
