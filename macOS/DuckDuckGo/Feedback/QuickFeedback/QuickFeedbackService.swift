//
//  QuickFeedbackService.swift
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
import BrowserServicesKit
import Combine
import WebKit

@MainActor
final class QuickFeedbackService: NSObject {

    private var windowController: QuickFeedbackWindowController?
    private var currentTab: Tab?
    private var screenshotData: Data?
    private let diagnosticsCollector: QuickFeedbackDiagnosticsCollector
    private var cancellables = Set<AnyCancellable>()

    private var contentOverlayPopover: ContentOverlayPopover?

    /// Suffix match (not substring) so only Asana-owned cookies are cleared on sign-out.
    private static let asanaDomainSuffix = "asana.com"

    /// Hides the form section until the autofiller's `hideIrrelevantFields` runs (8s fallback)
    /// and suppresses `beforeunload` prompts that would block the panel closing.
    private static let popupModeEarlyInjectionScript = """
    (function() {
        var s = document.createElement('style');
        s.id = 'ddg-form-hider';
        s.textContent = '.WorkRequestsSection { opacity: 0; }';
        (document.head || document.documentElement).appendChild(s);

        setTimeout(function() {
            var h = document.getElementById('ddg-form-hider');
            if (h && h.textContent.indexOf('opacity: 0') !== -1) {
                h.textContent = '.WorkRequestsSection { opacity: 1; }';
            }
        }, 8000);

        var origAdd = EventTarget.prototype.addEventListener;
        EventTarget.prototype.addEventListener = function(type, fn, opts) {
            if (type === 'beforeunload') return;
            return origAdd.call(this, type, fn, opts);
        };
        window.addEventListener('beforeunload', function(e) { e.stopImmediatePropagation(); delete e.returnValue; }, true);
        window.onbeforeunload = null;
        Object.defineProperty(window, 'onbeforeunload', { get: function() { return null; }, set: function() {} });
    })();
    """

    init(
        diagnosticsCollector: QuickFeedbackDiagnosticsCollector,
        firePublisher: AnyPublisher<Fire.BurningData?, Never>
    ) {
        self.diagnosticsCollector = diagnosticsCollector

        super.init()

        firePublisher
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.forceClosePopup()
            }
            .store(in: &cancellables)
    }

    func openFeedbackPopup(from window: NSWindow? = nil) {
        captureScreenshot(from: window)

        if let existing = windowController, let tab = currentTab {
            existing.window?.makeKeyAndOrderFront(nil)
            tab.internalFeedbackForm?.popupContext = makePopupContext()
            tab.webView.load(URLRequest(url: .internalFeedbackForm))
            return
        }

        let tab = makeFeedbackTab()
        currentTab = tab

        let controller = QuickFeedbackWindowController(tab: tab)
        controller.onSignOutRequested = { [weak self] in
            self?.signOut()
        }
        controller.window?.delegate = self
        windowController = controller

        tab.autofill?.setDelegate(self)

        controller.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Tab construction

    private func makeFeedbackTab() -> Tab {
        // `.none` then explicit `load`: ensures the early-injection script is registered
        // before document-start fires on the first navigation.
        let tab = Tab(
            content: .none,
            shouldLoadInBackground: false,
            burnerMode: .regular
        )
        tab.setDelegate(self)
        tab.webView.configuration.userContentController.addUserScript(
            WKUserScript(source: Self.popupModeEarlyInjectionScript,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: true)
        )
        tab.internalFeedbackForm?.popupContext = makePopupContext()
        tab.webView.load(URLRequest(url: .internalFeedbackForm))
        return tab
    }

    private func makePopupContext() -> InternalFeedbackFormPopupContext {
        InternalFeedbackFormPopupContext(
            quickMode: true,
            diagnostics: diagnosticsCollector.collectDiagnostics(),
            screenshotData: screenshotData
        )
    }

    // MARK: - Popup lifecycle

    private func hidePopup() {
        contentOverlayPopover?.viewController.closeContentOverlayPopover()
        windowController?.window?.orderOut(nil)
        screenshotData = nil
    }

    private func forceClosePopup() {
        contentOverlayPopover?.viewController.closeContentOverlayPopover()
        contentOverlayPopover = nil
        windowController?.window?.orderOut(nil)
        windowController = nil
        currentTab = nil
        screenshotData = nil
    }

    // MARK: - Autofill overlay

    private func overlayPopoverCreatingIfNeeded() -> ContentOverlayPopover? {
        if let existing = contentOverlayPopover {
            return existing
        }
        guard let anchorView = windowController?.webViewContainer,
              let appDelegate = Application.appDelegate else {
            return nil
        }
        let popover = ContentOverlayPopover(
            currentTabView: anchorView,
            privacyConfigurationManager: appDelegate.privacyFeatures.contentBlocking.privacyConfigurationManager,
            webTrackingProtectionPreferences: appDelegate.webTrackingProtectionPreferences,
            featureFlagger: appDelegate.featureFlagger,
            tld: appDelegate.tld,
            pinningManager: appDelegate.pinningManager
        )
        contentOverlayPopover = popover
        return popover
    }

    private func signOut() {
        windowController?.setSignOutVisible(false)

        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let asanaRecords = records.filter { $0.displayName.hasSuffix(Self.asanaDomainSuffix) }
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: asanaRecords) {
                Task { @MainActor [weak self] in
                    self?.currentTab?.webView.load(URLRequest(url: .internalFeedbackForm))
                }
            }
        }
    }

    // MARK: - Screenshot

    private func captureScreenshot(from window: NSWindow?) {
        guard let targetWindow = window ?? NSApp.mainWindow else {
            screenshotData = nil
            return
        }

        let windowID = CGWindowID(targetWindow.windowNumber)
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .nominalResolution]
        ) else {
            screenshotData = nil
            return
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        screenshotData = bitmapRep.representation(using: .png, properties: [:])
    }
}

// MARK: - TabDelegate

extension QuickFeedbackService: TabDelegate {

    var isInPopUpWindow: Bool { true }

    func tab(_ tab: Tab, createdChild childTab: Tab, of kind: NewWindowPolicy) {
        // Asana help links and similar new-window navigations open in a regular browser window.
        switch kind {
        case .popup(origin: let origin, size: let contentSize):
            WindowsManager.openPopUpWindow(with: childTab, origin: origin, contentSize: contentSize)
        case .window(active: let active, _):
            WindowsManager.openNewWindow(with: childTab, showWindow: active)
        case .tab(selected: let selected, _, _):
            if let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController {
                parentWindowController.mainViewController.tabCollectionViewModel.insertOrAppend(tab: childTab, selected: selected)
            } else {
                WindowsManager.openNewWindow(with: childTab, showWindow: true)
            }
        }
    }

    func tabWillStartNavigation(_ tab: Tab, isUserInitiated: Bool) {}
    func tabDidStartNavigation(_ tab: Tab) {}

    /// Bar visibility follows the rendered page: visible only when the form URL is loaded
    /// (i.e. user is signed in). Hidden on the login screen and during transient navigations.
    func tabPageDOMLoaded(_ tab: Tab) {
        let isOnFeedbackForm = tab.webView.url.map(InternalFeedbackFormTabExtension.isInternalFeedbackURL) ?? false
        windowController?.setSignOutVisible(isOnFeedbackForm)
    }

    func closeTab(_ tab: Tab) {
        forceClosePopup()
    }

    func websiteAutofillUserScriptCloseOverlay(_ websiteAutofillUserScript: WebsiteAutofillUserScript?) {
        overlayPopoverCreatingIfNeeded()?.websiteAutofillUserScriptCloseOverlay(websiteAutofillUserScript)
    }

    func websiteAutofillUserScript(_ websiteAutofillUserScript: WebsiteAutofillUserScript,
                                   willDisplayOverlayAtClick: CGPoint?,
                                   serializedInputContext: String,
                                   inputPosition: CGRect) {
        overlayPopoverCreatingIfNeeded()?.websiteAutofillUserScript(
            websiteAutofillUserScript,
            willDisplayOverlayAtClick: willDisplayOverlayAtClick,
            serializedInputContext: serializedInputContext,
            inputPosition: inputPosition
        )
    }
}

// MARK: - NSWindowDelegate

extension QuickFeedbackService: NSWindowDelegate {

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hidePopup()
        return false
    }
}
