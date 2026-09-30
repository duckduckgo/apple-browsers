//
//  CPMBackgroundWebViewDelegateProxy.swift
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

import Common
import Foundation
import os.log
import WebKit

/// Mirrors WebKit's process termination reason values.
public enum CPMBackgroundProcessTerminationReason: Int, Sendable {
    case exceededMemoryLimit = 0
    case exceededCPULimit
    case requestedByClient
    case crash
    case exceededSharedProcessCrashLimit
}

extension CPMBackgroundProcessTerminationReason: CustomStringConvertible {
    public var description: String {
        switch self {
        case .exceededMemoryLimit: return "memory"
        case .exceededCPULimit: return "cpu"
        case .requestedByClient: return "client"
        case .crash: return "crash"
        case .exceededSharedProcessCrashLimit: return "crash_limit"
        }
    }
}

/// Receives process-health events from `CPMBackgroundWebViewDelegateProxy`.
@MainActor
public protocol CPMBackgroundWebViewProxyDelegate: AnyObject {
    func backgroundWebView(_ webView: WKWebView, webContentProcessDidTerminateWith reason: CPMBackgroundProcessTerminationReason?)
    func backgroundWebViewWebProcessDidBecomeUnresponsive(_ webView: WKWebView)
    func backgroundWebViewWebProcessDidBecomeResponsive(_ webView: WKWebView)
}

/// Observes background process termination while forwarding WebKit's delegate callbacks.
/// The original delegate owns the proxy; the proxy does not extend its lifetime.
/// WebKit caches supported selectors when assigning the delegate, so forwarding must
/// preserve `responds(to:)` behavior.
@MainActor
public final class CPMBackgroundWebViewDelegateProxy: NSObject, WKNavigationDelegate {

    private weak var original: (any WKNavigationDelegate)?
    private weak var delegate: (any CPMBackgroundWebViewProxyDelegate)?

    private static let originalNavigationDelegateKey = UnsafeRawPointer(bitPattern: "originalNavigationDelegateKey".hashValue)!

    public init(original: (any WKNavigationDelegate)?, delegate: any CPMBackgroundWebViewProxyDelegate) {
        self.original = original
        self.delegate = delegate
        super.init()
    }

    /// Associates the proxy with the original delegate. Without an original owner, installation is skipped.
    @discardableResult
    public static func install(on webView: WKWebView, delegate: any CPMBackgroundWebViewProxyDelegate) -> CPMBackgroundWebViewDelegateProxy? {
        guard let original = webView.navigationDelegate else { return nil }
        if let alreadyProxied = original as? CPMBackgroundWebViewDelegateProxy {
            return alreadyProxied
        }
        let existing = objc_getAssociatedObject(original, originalNavigationDelegateKey) as? CPMBackgroundWebViewDelegateProxy
        let proxy = existing ?? CPMBackgroundWebViewDelegateProxy(original: original, delegate: delegate)
        proxy.delegate = delegate
        objc_setAssociatedObject(original, originalNavigationDelegateKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        webView.navigationDelegate = proxy
        Logger.webExtensions.info("[CPM Diagnostics] Installed background navigation delegate proxy in front of \(String(describing: type(of: original)), privacy: .public)")
        return proxy
    }

    /// Restores the original delegate. The associated proxy stays alive until the original is released.
    public static func uninstall(from webView: WKWebView) {
        guard let proxy = webView.navigationDelegate as? CPMBackgroundWebViewDelegateProxy else { return }
        webView.navigationDelegate = proxy.original
        Logger.webExtensions.info("[CPM Diagnostics] Removed background navigation delegate proxy; original delegate restored")
    }

    /// Whether `webView` currently has a proxy installed.
    public static func isInstalled(on webView: WKWebView) -> Bool {
        webView.navigationDelegate is CPMBackgroundWebViewDelegateProxy
    }

    // MARK: - Forwarding

    public override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) {
            return true
        }
        return original?.responds(to: aSelector) ?? false
    }

    public override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let original, original.responds(to: aSelector) {
            return original
        }
        return super.forwardingTarget(for: aSelector)
    }

    public override func conforms(to aProtocol: Protocol) -> Bool {
        super.conforms(to: aProtocol) || (original?.conforms(to: aProtocol) ?? false)
    }

    // MARK: - Process termination

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Logger.webExtensions.error("[CPM Diagnostics] Background WebContent process terminated (reason unknown)")
        delegate?.backgroundWebView(webView, webContentProcessDidTerminateWith: nil)
        forwardProcessTermination(webView, rawReason: nil)
    }

    @objc(_webView:webContentProcessDidTerminateWithReason:)
    public func webView(_ webView: WKWebView, webContentProcessDidTerminateWithReason rawReason: Int) {
        let reason = CPMBackgroundProcessTerminationReason(rawValue: rawReason)
        Logger.webExtensions.error("[CPM Diagnostics] Background WebContent process terminated, reason=\(reason?.description ?? "unknown", privacy: .public)")
        delegate?.backgroundWebView(webView, webContentProcessDidTerminateWith: reason)
        forwardProcessTermination(webView, rawReason: rawReason)
    }

    /// WebKit calls exactly one termination callback on us (the private one, since we implement it), so hand the event
    /// to whichever variant the original delegate implements — the extension delegate needs it to unload the background.
    private func forwardProcessTermination(_ webView: WKWebView, rawReason: Int?) {
        guard let original else { return }
        guard let rawReason, original.responds(to: PrivateSelector.terminatedWithReason),
              let originalClass = object_getClass(original),
              let method = class_getInstanceMethod(originalClass, PrivateSelector.terminatedWithReason) else {
            original.webViewWebContentProcessDidTerminate?(webView)
            return
        }
        typealias Function = @convention(c) (AnyObject, Selector, WKWebView, Int) -> Void
        let implementation = unsafeBitCast(method_getImplementation(method), to: Function.self)
        implementation(original, PrivateSelector.terminatedWithReason, webView, rawReason)
    }

    // MARK: - Hang detection

    @objc(_webViewWebProcessDidBecomeUnresponsive:)
    public func webViewWebProcessDidBecomeUnresponsive(_ webView: WKWebView) {
        Logger.webExtensions.error("[CPM Diagnostics] Background WebContent process became unresponsive")
        delegate?.backgroundWebViewWebProcessDidBecomeUnresponsive(webView)
        forwardIfImplemented(PrivateSelector.becameUnresponsive, webView)
    }

    @objc(_webViewWebProcessDidBecomeResponsive:)
    public func webViewWebProcessDidBecomeResponsive(_ webView: WKWebView) {
        Logger.webExtensions.info("[CPM Diagnostics] Background WebContent process became responsive again")
        delegate?.backgroundWebViewWebProcessDidBecomeResponsive(webView)
        forwardIfImplemented(PrivateSelector.becameResponsive, webView)
    }

    // MARK: - Private

    private func forwardIfImplemented(_ selector: Selector, _ webView: WKWebView) {
        guard let original, original.responds(to: selector) else { return }
        _ = (original as AnyObject).perform(selector, with: webView)
    }

    private enum PrivateSelector {
        static let terminatedWithReason = NSSelectorFromString("_webView:webContentProcessDidTerminateWithReason:")
        static let becameUnresponsive = NSSelectorFromString("_webViewWebProcessDidBecomeUnresponsive:")
        static let becameResponsive = NSSelectorFromString("_webViewWebProcessDidBecomeResponsive:")
    }

}
