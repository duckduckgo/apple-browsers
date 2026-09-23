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
import os.log
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
        /// Gap between the toolbar button and the popup.
        static let verticalOffset: CGFloat = 4

        /// Used until the popup page reports the size it wants.
        static let fallbackSize = NSSize(width: 380, height: 560)

        /// Keeps a popup that reports an unusable size from collapsing.
        static let minimumSize = NSSize(width: 120, height: 80)

        /// Keeps a popup that reports an extreme size from covering the screen.
        static let maximumSize = NSSize(width: 800, height: 800)

        /// Reads the size the popup page lays itself out at.
        ///
        /// An explicit `body` width wins over `scrollWidth`. A page whose `html` fills the
        /// viewport never reports a `scrollWidth` smaller than the panel, so a popup that wants
        /// to be narrower than `fallbackSize` could otherwise only ever grow. Bitwarden sets
        /// `body.style.width` from script, which gives us the width it actually wants.
        static let measurePageScript = """
        (function() {
            var body = document.body;
            var width = body && body.style.width
                ? body.getBoundingClientRect().width
                : Math.max(document.documentElement.scrollWidth, body ? body.scrollWidth : 0);
            var height = Math.max(document.documentElement.scrollHeight, body ? body.scrollHeight : 0);
            return [width, height];
        })()
        """

        /// Tells whether the popup page declares a color scheme, through CSS or a `<meta>` tag.
        static let declaresColorSchemeScript = """
        (function() {
            if (document.querySelector('meta[name="color-scheme"]')) { return true; }
            var root = document.documentElement;
            return !!root && getComputedStyle(root).colorScheme !== "normal";
        })()
        """

        /// Name of the script message handler the popup page posts to when its layout changes.
        static let resizeMessageHandlerName = "ddgWebExtensionPopupResize"

        /// Makes the popup page report layout changes, so the panel follows them as they happen.
        ///
        /// A popup can change size without loading anything: LastPass swaps its login form for
        /// its vault in place, and grows the form to show an error banner. A `ResizeObserver`
        /// catches the page's own boxes changing size, and a `MutationObserver` catches content
        /// swapped in without resizing `html` or `body`. Reports are coalesced to one per frame,
        /// and the browser measures the page itself on each, with `measurePageScript`.
        ///
        /// Installed once per document: a page that loads again gets it again.
        static let observePageScript = """
        (function() {
            if (window.__ddgPopupResizeObserved) { return; }
            var handlers = window.webkit && window.webkit.messageHandlers;
            var handler = handlers && handlers["\(resizeMessageHandlerName)"];
            if (!handler) { return; }
            window.__ddgPopupResizeObserved = true;

            var scheduled = false;
            function report() {
                if (scheduled) { return; }
                scheduled = true;
                requestAnimationFrame(function() {
                    scheduled = false;
                    try { handler.postMessage(null); } catch (error) {}
                });
            }

            var resizeObserver = new ResizeObserver(report);
            resizeObserver.observe(document.documentElement);
            if (document.body) { resizeObserver.observe(document.body); }
            new MutationObserver(report).observe(document.documentElement, {
                subtree: true, childList: true, attributes: true, characterData: true
            });
        })()
        """
    }

    private var panel: WebExtensionPopupPanel?
    private var shownContext: WKWebExtensionContext?
    private weak var shownAction: WKWebExtension.Action?
    private weak var anchorButton: NSView?
    private weak var popupWebView: WKWebView?
    private var loadingObservation: NSKeyValueObservation?
    private var clickMonitor: Any?
    private var resizeMessageUserContentController: WKUserContentController?

    /// Whether the popup of the given extension is on screen.
    func isShown(for context: WKWebExtensionContext) -> Bool {
        panel?.isVisible == true && shownContext?.uniqueIdentifier == context.uniqueIdentifier
    }

    // MARK: - Show

    func present(_ action: WKWebExtension.Action,
                 for context: WKWebExtensionContext,
                 from button: NSView) {
        guard let popupWebView = action.popupWebView else {
            Logger.webExtensions.error("❌ Popup of \(context.uniqueIdentifier) has no web view")
            return
        }
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

        let contentView = NSView(frame: NSRect(origin: .zero, size: Constants.fallbackSize))
        contentView.wantsLayer = true
        contentView.layer?.masksToBounds = true
        // The popup page paints its own background, but only once it loads. An opaque body
        // keeps the panel visible until then, instead of a fully transparent rectangle.
        contentView.layer?.backgroundColor = popupBackgroundColor.cgColor

        // Light until the page shows it declares a color scheme, so a page that relies on
        // Chrome's light defaults never renders a frame with white text.
        // See `updateAppearance(of:)`.
        popupWebView.appearance = NSAppearance(named: .aqua)

        popupWebView.frame = contentView.bounds
        popupWebView.autoresizingMask = [.width, .height]
        contentView.addSubview(popupWebView)
        panel.contentView = contentView

        // Size the panel from the fallback size, not from the content view. AppKit resizes
        // the content view to the frame the panel already has, which is the placeholder size
        // from `WebExtensionPopupPanel.init`.
        panel.setFrame(frame(forContentSize: Constants.fallbackSize, below: button, in: parentWindow),
                       display: false)

        parentWindow.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        panel.makeKey()

        // Never drive the extension from here: a call such as `loadBackgroundContent()` makes
        // WebKit hold the popup back until the background content is ready, and an extension
        // whose worker never starts then shows no popup. Only observe the page.
        observePopupSize(of: popupWebView)
        startWatchingForClicksOutside()
    }

    private var popupBackgroundColor: NSColor {
        NSApp.delegateTyped.themeManager.theme.colorsProvider.popoverBackgroundColor
    }

    // MARK: - Size

    /// Resizes the panel to the size the popup page lays itself out at.
    ///
    /// WebKit does not tell us that size. The `contentSize` of the popover it would have
    /// presented stays zero, and the popup web view keeps a zero frame until something sizes
    /// it, so both are useless as a source. We therefore ask the page itself once it loads.
    ///
    /// The popup page may have finished loading before it is presented, in which case `isLoading`
    /// never changes, so the page is measured and observed right away as well as on the load event.
    ///
    /// After that the page reports its own layout changes through `observePageScript`. WebKit
    /// never resizes the popup web view by itself, so nothing on the native side would notice a
    /// popup that changes size without loading, such as LastPass swapping its vault for its
    /// login form on logout.
    private func observePopupSize(of popupWebView: WKWebView) {
        // Every extension page shares this user content controller, so the handler only
        // answers messages from the popup it was registered for.
        let handler = PopupResizeMessageHandler { [weak self, weak popupWebView] webView in
            guard let self, let popupWebView, webView === popupWebView else { return }
            self.measurePageAndResize(popupWebView)
        }
        let userContentController = popupWebView.configuration.userContentController
        // Adding a second handler under the same name raises, so drop any left behind first.
        userContentController.removeScriptMessageHandler(forName: Constants.resizeMessageHandlerName)
        userContentController.add(handler, name: Constants.resizeMessageHandlerName)
        resizeMessageUserContentController = userContentController

        measureAndObservePage(popupWebView)

        loadingObservation = popupWebView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard webView.isLoading == false else { return }
                self?.measureAndObservePage(webView)
            }
        }
    }

    private func measureAndObservePage(_ popupWebView: WKWebView) {
        updateAppearance(of: popupWebView)
        measurePageAndResize(popupWebView)
        popupWebView.evaluateJavaScript(Constants.observePageScript) { _, error in
            if let error {
                Logger.webExtensions.debug("🧩 Popup page could not be observed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Appearance

    /// Gives a popup page that declares no color scheme the light defaults Chrome gives it, and a
    /// page that declares one the app's appearance.
    ///
    /// Chrome renders a page whose `color-scheme` is `normal` with black text and light form
    /// controls whatever the system appearance, and extensions built for Chrome rely on it:
    /// LastPass leaves text at the default color on its own light backgrounds. WebKit takes those
    /// defaults from the web view's appearance and ignores `color-scheme` for them, so in a dark
    /// app that text renders white. The appearance is the only lever that works. A page that
    /// declares a color scheme handles dark mode itself, so it keeps the app's appearance and
    /// sees `prefers-color-scheme` follow the app, as it would in Chrome.
    private func updateAppearance(of popupWebView: WKWebView) {
        popupWebView.evaluateJavaScript(Constants.declaresColorSchemeScript) { [weak popupWebView] result, _ in
            DispatchQueue.main.async {
                guard let popupWebView else { return }
                let declaresColorScheme = (result as? Bool) ?? false
                popupWebView.appearance = declaresColorScheme ? nil : NSAppearance(named: .aqua)
            }
        }
    }

    private func measurePageAndResize(_ popupWebView: WKWebView) {
        popupWebView.evaluateJavaScript(Constants.measurePageScript) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let values = result as? [Double], values.count == 2 else {
                    Logger.webExtensions.debug("🧩 Popup page did not report a size: \(error?.localizedDescription ?? "no value", privacy: .public)")
                    return
                }
                self.resize(toPageSize: NSSize(width: values[0], height: values[1]))
            }
        }
    }

    private func resize(toPageSize pageSize: NSSize) {
        guard let panel, panel.isVisible,
              let button = anchorButton,
              let parentWindow = button.window else { return }

        let size = NSSize(
            width: min(max(pageSize.width, Constants.minimumSize.width), Constants.maximumSize.width),
            height: min(max(pageSize.height, Constants.minimumSize.height), Constants.maximumSize.height)
        )
        guard size != panel.frame.size else { return }

        Logger.webExtensions.debug("🧩 Popup page reports \(NSStringFromSize(pageSize), privacy: .public), panel set to \(NSStringFromSize(size), privacy: .public)")
        panel.setFrame(frame(forContentSize: size, below: button, in: parentWindow), display: true)
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

    /// Closes the popup on a click in a browser window that lands neither in the popup nor on its button.
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

        // Only a click in a browser window dismisses the popup. Web Inspector opens on the
        // popup page in a window of our own process, and closing the popup when it is clicked
        // would take down the page being inspected.
        guard clickedWindow is MainWindow else { return }

        if let button = anchorButton, clickedWindow === button.window {
            let pointInButton = button.convert(location, from: nil)
            if button.bounds.contains(pointInButton) { return }
        }

        close()
    }

    /// Closes the panel when it hosts `webView`, which is how a popup page's own `window.close()`
    /// reaches the presenter. A close from any other extension page is ignored.
    func close(ifShowing webView: WKWebView) {
        guard popupWebView === webView else { return }
        close()
    }

    func close() {
        guard let panel else { return }

        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }

        loadingObservation?.invalidate()
        loadingObservation = nil

        resizeMessageUserContentController?.removeScriptMessageHandler(forName: Constants.resizeMessageHandlerName)
        resizeMessageUserContentController = nil

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

/// Receives the layout-change reports `observePageScript` posts from a popup page.
private final class PopupResizeMessageHandler: NSObject, WKScriptMessageHandler {

    private let onReport: @MainActor (WKWebView) -> Void

    init(onReport: @escaping @MainActor (WKWebView) -> Void) {
        self.onReport = onReport
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let webView = message.webView else { return }
        MainActor.assumeIsolated {
            onReport(webView)
        }
    }
}
