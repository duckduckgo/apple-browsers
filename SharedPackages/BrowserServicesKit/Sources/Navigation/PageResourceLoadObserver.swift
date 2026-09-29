//
//  PageResourceLoadObserver.swift
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

import FoundationExtensions
import WebKit

/// The owner must retain this observer for the lifetime of its attachment; WebKit keeps a weak delegate.
@MainActor
public final class PageResourceLoadObserver: NSObject {
    private weak var webView: WKWebView?
    private var activeResourceIDs = Set<UInt64>()
    private let onError: (URL, PageResourceLoadError) -> Void

    private init(webView: WKWebView, onError: @escaping (URL, PageResourceLoadError) -> Void) {
        self.webView = webView
        self.onError = onError
    }

    /// Returns nil if private page signals are disabled, the SPI is unavailable, or another resource-load delegate is already attached.
    public static func attach(to webView: WKWebView,
                              onError: @escaping (URL, PageResourceLoadError) -> Void) -> PageResourceLoadObserver? {
#if PRIVATE_PAGE_SIGNALS_ENABLED
        guard webView.isResourceLoadDelegateSupported, webView.resourceLoadDelegate == nil else { return nil }

        let observer = PageResourceLoadObserver(webView: webView, onError: onError)
        webView.resourceLoadDelegate = observer
        return observer
#else
        return nil
#endif
    }

    /// Discards pending loads from the previous page. Uncommitted navigations leave collection untouched.
    public func navigationDidCommit() {
        activeResourceIDs.removeAll()
    }

    public func detach() {
        activeResourceIDs.removeAll()
        guard let webView else { return }
#if PRIVATE_PAGE_SIGNALS_ENABLED
        if webView.resourceLoadDelegate === self {
            webView.resourceLoadDelegate = nil
        }
#endif
        self.webView = nil
    }

#if PRIVATE_PAGE_SIGNALS_ENABLED
    @objc(webView:resourceLoad:didSendRequest:)
    private func webView(_ webView: WKWebView, resourceLoad: NSObject, didSendRequest request: URLRequest) {
        guard self.webView === webView,
              let resourceID: UInt64 = resourceLoad.ddgValueIfAvailable(forKey: "resourceLoadID") else { return }
        activeResourceIDs.insert(resourceID)
    }

    @objc(webView:resourceLoad:didCompleteWithError:response:)
    private func webView(_ webView: WKWebView, resourceLoad: NSObject, didCompleteWithError error: NSError?, response: URLResponse?) {
        // Require a start observed since the last commit. Completions without a matching start (including
        // some cache loads) cannot be safely attributed to the current page.
        guard self.webView === webView,
              let resourceID: UInt64 = resourceLoad.ddgValueIfAvailable(forKey: "resourceLoadID"),
              activeResourceIDs.remove(resourceID) != nil else { return }
        guard let url: URL = resourceLoad.ddgValueIfAvailable(forKey: "originalURL"),
              let loadError = PageResourceLoadError(error: error, response: response) else { return }
        onError(url, loadError)
    }

#endif
}

#if PRIVATE_PAGE_SIGNALS_ENABLED
private extension WKWebView {

    enum ResourceLoadDelegateSelector {
        static let resourceLoadDelegate = NSSelectorFromString("_resourceLoadDelegate")
        static let setResourceLoadDelegate = NSSelectorFromString("_setResourceLoadDelegate:")
    }

    var isResourceLoadDelegateSupported: Bool {
        responds(to: ResourceLoadDelegateSelector.resourceLoadDelegate)
            && responds(to: ResourceLoadDelegateSelector.setResourceLoadDelegate)
    }

    var resourceLoadDelegate: AnyObject? {
        get {
            guard responds(to: ResourceLoadDelegateSelector.resourceLoadDelegate) else {
                assertionFailure("WKWebView does not respond to selector _resourceLoadDelegate")
                return nil
            }
            return perform(ResourceLoadDelegateSelector.resourceLoadDelegate)?.takeUnretainedValue()
        }
        set {
            guard responds(to: ResourceLoadDelegateSelector.setResourceLoadDelegate),
                  let method = class_getInstanceMethod(object_getClass(self), ResourceLoadDelegateSelector.setResourceLoadDelegate) else {
                assertionFailure("WKWebView does not respond to selector _setResourceLoadDelegate:")
                return
            }
            let imp = method_getImplementation(method)
            typealias SetResourceLoadDelegateType = @convention(c) (WKWebView, ObjectiveC.Selector, AnyObject?) -> Void
            let setResourceLoadDelegate = unsafeBitCast(imp, to: SetResourceLoadDelegateType.self)
            setResourceLoadDelegate(self, ResourceLoadDelegateSelector.setResourceLoadDelegate, newValue)
        }
    }
}
#endif
