//
//  WebViewHandler.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Foundation
import WebKit
import PrivacyConfig
import BrowserServicesKit
import UserScript
import Common
import os.log

public protocol WebViewHandler: NSObject {
    func initializeWebView(showWebView: Bool) async
    func load(url: URL) async throws
    func takeSnaphost(path: String, fileName: String) async throws
    func saveHTML(path: String, fileName: String) async throws
    func waitForWebViewLoad() async throws
    func finish() async
    func execute(action: Action, ofType stepType: StepType?, data: CCFRequestData) async
    func evaluateJavaScript(_ javaScript: String) async throws
    func setCookies(_ cookies: [HTTPCookie]) async
}

@MainActor
final class DataBrokerProtectionWebViewHandler: NSObject, WebViewHandler {
    private var activeContinuation: CheckedContinuation<Void, Error>?

    private let isFakeBroker: Bool
    private let executionConfig: BrokerJobExecutionConfig
    private var webViewConfiguration: WKWebViewConfiguration?
    private var userContentController: DataBrokerUserContentController?

    private var webView: WebView?

#if os(macOS)
    private var urlObservation: NSKeyValueObservation?
    private var window: NSWindow?
    private var addressBarTextField: NSTextField?
    private var toolbar: NSToolbar?
#elseif os(iOS)
    private var window: UIWindow?
#endif

    private var timer: Timer?

    init(privacyConfig: PrivacyConfigurationManaging, prefs: ContentScopeProperties, delegate: CCFCommunicationDelegate, isFakeBroker: Bool = false, executionConfig: BrokerJobExecutionConfig, shouldContinueActionHandler: @escaping () -> Bool) throws {
        self.isFakeBroker = isFakeBroker
        self.executionConfig = executionConfig
        let configuration = WKWebViewConfiguration()
        try configuration.applyDataBrokerConfiguration(privacyConfig: privacyConfig, prefs: prefs, delegate: delegate, executionConfig: executionConfig, shouldContinueActionHandler: shouldContinueActionHandler)
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        self.webViewConfiguration = configuration

        let userContentController = configuration.userContentController as? DataBrokerUserContentController
        assert(userContentController != nil)
        self.userContentController = userContentController
    }

    func initializeWebView(showWebView: Bool) async {
        guard let configuration = self.webViewConfiguration else {
            return
        }

        webView = WebView(frame: CGRect(origin: .zero, size: CGSize(width: 1024, height: 1024)), configuration: configuration)
        webView?.navigationDelegate = self

        if showWebView {
#if os(macOS)
            urlObservation = webView?.observe(\.url, options: [.initial, .new]) { [weak self] _, change in
                let url = change.newValue ?? nil
                Task { @MainActor in
                    self?.updateAddressBar(with: url)
                }
            }

            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1024, height: 1024),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window?.title = "Data Broker Protection"
            window?.toolbarStyle = .expanded
            let toolbar = makeToolbar()
            self.toolbar = toolbar
            window?.toolbar = toolbar

            window?.delegate = self
            window?.isReleasedWhenClosed = false
            window?.contentView = webView

            window?.makeKeyAndOrderFront(nil)
#elseif os(iOS)
            cleanupExistingPIRDebugWindow()

            let viewController = UIViewController.init()
            viewController.view = webView
            let navigationController = UINavigationController(rootViewController: viewController)
            viewController.title = "PIR Debug Mode"

            if let currentWindowScene = UIApplication.shared.connectedScenes.first as?  UIWindowScene {
                window = UIWindow(windowScene: currentWindowScene)
                window?.rootViewController = navigationController
                window?.windowLevel = UIWindow.Level.alert
            } else {
                assertionFailure("Could not find window scene")
            }
#endif

        }

        installTimer()

        try? await load(url: URL(string: "\(WebViewSchemeHandler.dataBrokerProtectionScheme)://blank")!)
    }

    func load(url: URL) async throws {
        webView?.load(url)
        Logger.action.log("Loading URL: \(String(describing: url.absoluteString))")
        try await waitForWebViewLoad()
    }

    func setCookies(_ cookies: [HTTPCookie]) async {
        for cookie in cookies {
            await webView?.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        }
    }

    func finish() {
        Logger.action.log("WebViewHandler finished")
        webView?.stopLoading()
        userContentController?.cleanUpBeforeClosing()
        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache], modifiedSince: Date(timeIntervalSince1970: 0)) {
            Logger.action.log("WKWebView data store deleted correctly")
        }

        stopTimer()

        webViewConfiguration = nil
        userContentController = nil
        webView?.navigationDelegate = nil
        webView = nil
#if os(macOS)
        urlObservation?.invalidate()
        urlObservation = nil
#endif
    }

    deinit {
        Logger.action.log("WebViewHandler Deinit")
    }

    func waitForWebViewLoad() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.activeContinuation = continuation
        }
    }

    func execute(action: Action, ofType stepType: StepType?, data: CCFRequestData) {
        Logger.action.log("Executing action: \(String(describing: action.actionType.rawValue), privacy: .public)")

        userContentController?.dataBrokerUserScripts?.dataBrokerFeature.pushAction(
            method: .onActionReceived,
            webView: self.webView!,
            params: Params(state: ActionRequest(action: action, data: data))
        )
    }

    func evaluateJavaScript(_ javaScript: String) async throws {
        try await webView?.evaluateJavaScript(javaScript) as Void?
    }

    func takeSnaphost(path: String, fileName: String) async throws {
        guard let height: CGFloat = try await webView?.evaluateJavaScript("document.body.scrollHeight") else { return }

        webView?.frame = CGRect(origin: .zero, size: CGSize(width: 1024, height: height))
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: webView?.frame.size.width ?? 0.0, height: height)

#if os(macOS)
        if let image = try await webView?.takeSnapshot(configuration: configuration) {
            saveToDisk(image: image, path: path, fileName: fileName)
        }
#endif
    }

    func saveHTML(path: String, fileName: String) async throws {
        guard let htmlString: String = try await webView?.evaluateJavaScript("document.documentElement.outerHTML") else { return }
        let fileManager = FileManager.default

        do {
            if !fileManager.fileExists(atPath: path) {
                try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            }

            let fileURL = URL(fileURLWithPath: "\(path)/\(fileName)")
            try htmlString.write(to: fileURL, atomically: true, encoding: .utf8)
            print("HTML content saved to file: \(fileURL)")
        } catch {
            Logger.action.error("Error writing HTML content to file: \(error)")
        }
    }

#if os(macOS)
    private func saveToDisk(image: NSImage, path: String, fileName: String) {
        guard let tiffData = image.tiffRepresentation else {
            // Handle the case where tiff representation is not available
            return
        }

        // Create a bitmap representation from the tiff data
        guard let bitmapImageRep = NSBitmapImageRep(data: tiffData) else {
            // Handle the case where bitmap representation cannot be created
            return
        }

        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: path) {
            do {
                try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Error creating folder: \(error)")
            }
        }

        if let pngData = bitmapImageRep.representation(using: .png, properties: [:]) {
            // Save the PNG data to a file
            do {
                let fileURL = URL(fileURLWithPath: "\(path)/\(fileName)")
                try pngData.write(to: fileURL)
            } catch {
                print("Error writing PNG: \(error)")
            }
        } else {
            print("Error png data was not respresented")
        }
    }
#endif

    /// Workaround for stuck scans
    /// https://app.asana.com/0/0/1208502720748038/1208596554608118/f

    private func installTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            Task {
                try await self.webView?.evaluateJavaScript("1+1") as Void?
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

#if os(iOS)
    private func cleanupExistingPIRDebugWindow() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }

        for existingWindow in windowScene.windows {
            if let navController = existingWindow.rootViewController as? UINavigationController,
               let title = navController.topViewController?.title,
               title.hasPrefix("PIR Debug Mode") {
                existingWindow.isHidden = true
                existingWindow.rootViewController = nil
                break
            }
        }
    }
#endif

}

#if os(macOS)
private extension DataBrokerProtectionWebViewHandler {
    @objc func copyURLFromAddressBar() {
        let urlString = addressBarTextField?.stringValue ?? ""
        guard !urlString.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("PIRDebugToolbar"))
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        return toolbar
    }

    func makeAddressBarView() -> NSView {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 22))
        let addressField = NSTextField(labelWithString: "")
        addressField.isEditable = false
        addressField.isSelectable = true
        addressField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        addressField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addressField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addressField.cell?.lineBreakMode = .byTruncatingTail
        addressField.usesSingleLineMode = true
        addressBarTextField = addressField
        updateAddressBar(with: webView?.url)

        let copyButton = NSButton(title: "Copy URL", target: self, action: #selector(copyURLFromAddressBar))
        copyButton.setContentHuggingPriority(.required, for: .horizontal)
        copyButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let addressRow = NSStackView(views: [addressField, copyButton])
        addressRow.orientation = .horizontal
        addressRow.spacing = 8
        addressRow.alignment = .centerY
        addressRow.distribution = .fill
        addressRow.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(addressRow)
        NSLayoutConstraint.activate([
            addressRow.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            addressRow.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            addressRow.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 0),
            addressRow.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: 0)
        ])

        return containerView
    }

    func updateAddressBar(with url: URL?) {
        addressBarTextField?.stringValue = url?.absoluteString ?? ""
    }
}

extension DataBrokerProtectionWebViewHandler: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

extension DataBrokerProtectionWebViewHandler: NSToolbarDelegate {
    private enum ToolbarItemIdentifier {
        static let addressBar = NSToolbarItem.Identifier("PIRDebugToolbar.AddressBar")
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarItemIdentifier.addressBar, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarItemIdentifier.addressBar, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == ToolbarItemIdentifier.addressBar else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        let view = makeAddressBarView()
        item.view = view
        item.minSize = view.fittingSize
        item.maxSize = NSSize(width: 2000, height: view.fittingSize.height)
        return item
    }
}
#endif

extension DataBrokerProtectionWebViewHandler: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.action.log("WebViewHandler didFinish")
#if os(macOS)
        updateAddressBar(with: webView.url)
#endif

        self.activeContinuation?.resume()
        self.activeContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Logger.action.error("WebViewHandler didFail: \(error.localizedDescription, privacy: .public)")
        self.activeContinuation?.resume(throwing: error)
        self.activeContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Logger.action.error("WebViewHandler didFailProvisionalNavigation: \(error.localizedDescription, privacy: .public)")
        self.activeContinuation?.resume(throwing: error)
        self.activeContinuation = nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
#if os(macOS)
        updateAddressBar(with: webView.url)
#endif
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        guard let statusCode = (navigationResponse.response as? HTTPURLResponse)?.statusCode else {
            // if there's no http status code to act on, exit and allow navigation
            return .allow
        }

        if statusCode == 403 {
            Logger.action.log("WebViewHandler failed with status code: \(String(describing: statusCode), privacy: .public)")
            Logger.action.log("WebViewHandler continuing despite error")
        } else if statusCode >= 400 {
            Logger.action.log("WebViewHandler failed with status code: \(String(describing: statusCode), privacy: .public)")
            self.activeContinuation?.resume(throwing: DataBrokerProtectionError.httpError(code: statusCode))
            self.activeContinuation = nil
        }

        return .allow
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if !isFakeBroker {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            guard let serverTrust = challenge.protectionSpace.serverTrust else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }

            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic ||
                    challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPDigest {

            let fakeBrokerCredentials = HTTPUtils.fetchFakeBrokerCredentials()
            let credential = URLCredential(user: fakeBrokerCredentials.username, password: fakeBrokerCredentials.password, persistence: .none)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

private class WebView: WKWebView {

    deinit {
        configuration.userContentController.removeAllUserScripts()
        Logger.action.log("DBP WebView Deinit")
    }
}
