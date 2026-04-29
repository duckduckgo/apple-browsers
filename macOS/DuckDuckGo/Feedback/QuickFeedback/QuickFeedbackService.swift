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
import Combine
import Common
import os.log
import WebKit

@MainActor
final class QuickFeedbackService: NSObject {

    private var windowController: QuickFeedbackWindowController?
    private var screenshotData: Data?
    private let diagnosticsCollector: QuickFeedbackDiagnosticsCollector
    private let appVersion: AppVersion

    private let dataStore: WKWebsiteDataStore
    private var cancellables = Set<AnyCancellable>()

    private static let asanaFormHost = "form.asana.com"
    private static let asanaCookieDomain = "asana.com"
    private static let feedbackStoreIdentifier = UUID(uuidString: "D1A2B3C4-E5F6-7890-ABCD-EF1234567890")!

    private static let earlyInjectionScript = """
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
        appVersion: AppVersion = AppVersion(),
        firePublisher: AnyPublisher<Fire.BurningData?, Never>
    ) {
        self.diagnosticsCollector = diagnosticsCollector
        self.appVersion = appVersion
        // macOS 14+ uses an isolated persistent store so Fire doesn't clear
        // the Asana session. On older macOS (no forIdentifier API), we fall
        // back to .default() where Fire will clear cookies. Acceptable since
        // internal users on macOS < 14 are extremely rare.
        if #available(macOS 14.0, *) {
            self.dataStore = WKWebsiteDataStore(forIdentifier: Self.feedbackStoreIdentifier)
        } else {
            self.dataStore = .default()
        }

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

        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            navigateToForm()
            return
        }

        let controller = createWindowController()
        windowController = controller

        controller.window?.makeKeyAndOrderFront(nil)

        Task {
            await copyAsanaCookiesFromDefaultStore()
            navigateToForm()
        }
    }

    private func createWindowController() -> QuickFeedbackWindowController {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.processPool = WKProcessPool()

        let userScript = WKUserScript(
            source: Self.earlyInjectionScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(userScript)
        let controller = QuickFeedbackWindowController(webViewConfiguration: config)
        controller.webView.navigationDelegate = self
        controller.window?.delegate = self
        controller.onSignOutRequested = { [weak self] in
            self?.signOut()
        }

        return controller
    }

    private func navigateToForm() {
        guard let webView = windowController?.webView else { return }
        let request = URLRequest(url: .internalFeedbackForm)
        webView.load(request)
    }

    private func hidePopup() {
        windowController?.window?.orderOut(nil)
        screenshotData = nil
    }

    private func forceClosePopup() {
        windowController?.window?.orderOut(nil)
        windowController = nil
        screenshotData = nil
    }

    private func signOut() {
        windowController?.setSignOutVisible(false)

        if dataStore === WKWebsiteDataStore.default() {
            dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { [weak self] records in
                let asanaRecords = records.filter { $0.displayName.contains("asana") }
                self?.dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: asanaRecords) {
                    Task { @MainActor [weak self] in
                        self?.navigateToForm()
                    }
                }
            }
        } else {
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.navigateToForm()
                }
            }
        }
    }

    // MARK: - Cookie Sync

    private func copyAsanaCookiesFromDefaultStore() async {
        guard dataStore !== WKWebsiteDataStore.default() else { return }

        let defaultCookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let asanaCookies = defaultCookies.filter { $0.domain.hasSuffix(Self.asanaCookieDomain) }

        for cookie in asanaCookies {
            await dataStore.httpCookieStore.setCookie(cookie)
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

    // MARK: - JS Injection

    private func injectQuickModeScript() {
        guard let webView = windowController?.webView else { return }

        guard let url = Bundle.main.url(forResource: "internal-feedback-autofiller", withExtension: "js"),
              let template = try? String(contentsOf: url, encoding: .utf8) else {
            Logger.general.error("Failed to load internal-feedback-autofiller.js from bundle")
            return
        }

        let bootstrapScript = template
            .replacingOccurrences(of: "%QUICK_MODE%", with: "null")
            .replacingOccurrences(of: "%DIAGNOSTICS%", with: "")
            .replacingOccurrences(of: "%SCREENSHOT_BASE64%", with: "")
            .replacingOccurrences(of: "%OS_VERSION%", with: "")
            .replacingOccurrences(of: "%APP_VERSION%", with: "")

        let appVersionModel = AppVersionModel(appVersion: appVersion)

        let payload: [String: Any] = [
            "osVersion": appVersion.osVersionMajorMinorPatch,
            "appVersion": "\(appVersionModel.versionLabelShort) (\(appVersionModel.distributionLabel))",
            "quickMode": true,
            "diagnostics": diagnosticsCollector.collectDiagnostics(),
            "screenshotBase64": screenshotData?.base64EncodedString() ?? "",
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: jsonData, encoding: .utf8) else {
            Logger.general.error("Failed to serialize quick feedback payload")
            return
        }

        webView.evaluateJavaScript(bootstrapScript) { [weak self] _, error in
            if let error {
                Logger.general.error("Quick feedback JS bootstrap failed: \(error.localizedDescription)")
                return
            }
            self?.windowController?.webView.evaluateJavaScript("window.__ddgQuickFeedbackAutofill(\(json))") { _, error in
                if let error {
                    Logger.general.error("Quick feedback autofill failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension QuickFeedbackService: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }

        let isAsanaForm = url.host == Self.asanaFormHost

        if !isAsanaForm {
            windowController?.setSignOutVisible(false)
            return
        }

        windowController?.setSignOutVisible(true)
        injectQuickModeScript()
    }
}

// MARK: - NSWindowDelegate

extension QuickFeedbackService: NSWindowDelegate {

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hidePopup()
        return false
    }
}
