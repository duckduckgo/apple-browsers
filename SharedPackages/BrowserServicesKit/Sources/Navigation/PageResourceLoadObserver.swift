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
import os.log
import WebKit

#if PRIVATE_PAGE_SIGNALS_ENABLED
/// The owner must retain this observer for the lifetime of its attachment; WebKit keeps a weak delegate.
@MainActor
public final class PageResourceLoadObserver: NSObject {
    private enum Keys {
        static let originalURL = "originalURL"
    }

    private weak var observedWebView: WKWebView?
    private let listener: (URL, PageResourceLoadError) -> Void

    public init(listener: @escaping (URL, PageResourceLoadError) -> Void) {
        self.listener = listener
    }

    public func attach(to webView: WKWebView) {
        guard webView.isResourceLoadDelegateSupported else {
            Logger.navigation.error("PageResourceLoadObserver: cannot attach, resource load delegate unsupported")
            return
        }

        guard webView.resourceLoadDelegate == nil else {
            Logger.navigation.error("PageResourceLoadObserver: cannot attach, resource load delegate already set")
            return
        }

        webView.resourceLoadDelegate = self
        observedWebView = webView
    }

    public func detach() {
        guard let observedWebView else {
            return
        }

        if observedWebView.isResourceLoadDelegateSupported, let delegate = observedWebView.resourceLoadDelegate as? PageResourceLoadObserver, delegate == self {
            observedWebView.resourceLoadDelegate = nil
        }

        self.observedWebView = nil
    }
}

// MARK: - Resources Delegate

extension PageResourceLoadObserver {

    @objc(webView:resourceLoad:didCompleteWithError:response:)
    private func webView(_ webView: WKWebView, resourceLoad: NSObject, didCompleteWithError error: NSError?, response: URLResponse?) {
        guard observedWebView == webView else {
            return
        }

        guard
            let url: URL = resourceLoad.ddgValueIfAvailable(forKey: Keys.originalURL),
            let resourceLoadError = PageResourceLoadError.resourceLoadError(from: error, response: response)
        else {
            return
        }

        listener(url, resourceLoadError)
    }
}

extension WKWebView {

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
