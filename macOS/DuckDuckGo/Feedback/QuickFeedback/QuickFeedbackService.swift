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
import WebKit

@MainActor
final class QuickFeedbackService: NSObject {

    private var windowController: QuickFeedbackWindowController?
    private var formLoaded = false
    private var screenshotData: Data?
    private let diagnosticsCollector: QuickFeedbackDiagnosticsCollector

    private let dataStore: WKWebsiteDataStore
    private var cancellables = Set<AnyCancellable>()

    private static let asanaFormHost = "form.asana.com"

    private static let earlyInjectionScript = """
    (function() {
        var s = document.createElement('style');
        s.id = 'ddg-form-hider';
        s.textContent = '.WorkRequestsSection { opacity: 0; }';
        (document.head || document.documentElement).appendChild(s);

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
        self.dataStore = WKWebsiteDataStore.nonPersistent()

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
            formLoaded = false
            existing.window?.makeKeyAndOrderFront(nil)
            navigateToForm()
            return
        }

        let controller = createWindowController()
        windowController = controller

        controller.window?.makeKeyAndOrderFront(nil)
        formLoaded = false
        navigateToForm()
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
        windowController?.window?.close()
        windowController = nil
        formLoaded = false
        screenshotData = nil
    }

    private func signOut() {
        formLoaded = false
        windowController?.setSignOutVisible(false)

        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { [weak self] records in
            let asanaRecords = records.filter { $0.displayName.contains("asana") }
            self?.dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: asanaRecords) {
                Task { @MainActor [weak self] in
                    self?.navigateToForm()
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

    private func injectScreenshot() {
        guard let data = screenshotData, let webView = windowController?.webView else { return }

        let base64 = data.base64EncodedString()
        let js = """
        (function() {
            var anchor = document.getElementById('ddg-diagnostics-section') || document.getElementById('ddg-submit-clone');
            if (!anchor) return;

            var section = document.createElement('div');
            section.id = 'ddg-screenshot-section';
            section.style.cssText = 'margin: 12px 24px 0; padding: 0;';

            var headerRow = document.createElement('div');
            headerRow.style.cssText = 'display: flex; align-items: center; gap: 8px;';

            var cb = document.createElement('input');
            cb.type = 'checkbox';
            cb.id = 'ddg-include-screenshot';
            cb.checked = false;
            headerRow.appendChild(cb);

            var cbLabel = document.createElement('label');
            cbLabel.setAttribute('for', 'ddg-include-screenshot');
            cbLabel.textContent = 'Include screenshot';
            cbLabel.style.cssText = 'font-size: 14px; cursor: pointer;';
            headerRow.appendChild(cbLabel);

            section.appendChild(headerRow);

            var warning = document.createElement('div');
            warning.style.cssText = 'font-size: 12px; color: #856404; background: #fff3cd; padding: 6px 10px; border-radius: 4px; margin: 6px 0 8px; display: none;';
            warning.textContent = '\u{26A0} This screenshot may contain private information. Please review carefully before including it.';
            section.appendChild(warning);

            cb.addEventListener('change', function() {
                warning.style.display = cb.checked ? '' : 'none';
            });

            var img = document.createElement('img');
            img.src = 'data:image/png;base64,\(base64)';
            img.style.cssText = 'max-width: 100%; max-height: 150px; margin-top: 6px; border: 1px solid #ddd; border-radius: 4px; cursor: pointer;';
            img.title = 'Click to enlarge';

            img.addEventListener('click', function() {
                var overlay = document.createElement('div');
                overlay.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.85);z-index:99999;display:flex;flex-direction:column;align-items:center;justify-content:center;cursor:pointer;padding:16px;box-sizing:border-box;';

                var closeBtn = document.createElement('button');
                closeBtn.textContent = '\u{2715} Close';
                closeBtn.style.cssText = 'position:absolute;top:12px;right:16px;background:rgba(255,255,255,0.15);border:1px solid rgba(255,255,255,0.3);color:white;font-size:14px;padding:6px 14px;border-radius:6px;cursor:pointer;';
                closeBtn.addEventListener('click', function() { overlay.remove(); });
                overlay.appendChild(closeBtn);

                var bigImg = document.createElement('img');
                bigImg.src = img.src;
                bigImg.style.cssText = 'max-width:100%;max-height:calc(100% - 40px);object-fit:contain;border-radius:4px;';
                overlay.appendChild(bigImg);
                overlay.addEventListener('click', function(e) { if (e.target === overlay) overlay.remove(); });
                document.body.appendChild(overlay);
            });

            section.appendChild(img);

            anchor.parentNode.insertBefore(section, anchor.nextSibling);
        })();
        """
        webView.evaluateJavaScript(js) { _, error in
            if let error {
                Logger.general.error("Quick feedback screenshot injection failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - JS Injection

    private func injectQuickModeScript() {
        guard let webView = windowController?.webView else { return }

        let diagnostics = diagnosticsCollector.collectDiagnostics()
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        let appVersionModel = AppVersionModel()

        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osVersionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        guard let url = Bundle.main.url(forResource: "internal-feedback-autofiller", withExtension: "js"),
              let template = try? String(contentsOf: url, encoding: .utf8) else {
            Logger.general.error("Failed to load internal-feedback-autofiller.js from bundle")
            return
        }

        let script = template
            .replacingOccurrences(of: "%OS_VERSION%", with: osVersionString)
            .replacingOccurrences(of: "%APP_VERSION%", with: "\(appVersionModel.versionLabelShort) (\(appVersionModel.distributionLabel))")
            .replacingOccurrences(of: "%QUICK_MODE%", with: "true")
            .replacingOccurrences(of: "%DIAGNOSTICS%", with: diagnostics)

        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                Logger.general.error("Quick feedback JS evaluation failed: \(error.localizedDescription)")
            }
            self?.injectScreenshot()
        }
    }
}

// MARK: - WKNavigationDelegate

extension QuickFeedbackService: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }

        let isAsanaForm = url.host == Self.asanaFormHost

        if !isAsanaForm {
            formLoaded = false
            windowController?.setSignOutVisible(false)
            return
        }

        guard !formLoaded else {
            // Post-submit redirect: hide the popup (keep WebView warm for reuse)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.hidePopup()
            }
            return
        }

        formLoaded = true
        windowController?.setSignOutVisible(true)
        injectQuickModeScript()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        return .allow
    }
}

// MARK: - NSWindowDelegate

extension QuickFeedbackService: NSWindowDelegate {

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hidePopup()
        return false
    }
}
