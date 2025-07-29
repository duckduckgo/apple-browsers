//
//  WKWebViewExtension.swift
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

import WebKit

extension WKWebView {

#if _FRAME_HANDLE_ENABLED

    private static let mainFrameKey = "mainFrame"
    public var mainFrameHandle: FrameHandle {
        guard self.responds(to: NSSelectorFromString("_" + Self.mainFrameKey))
                || self.responds(to: NSSelectorFromString(Self.mainFrameKey)) else {
            return .fallbackMainFrameHandle
        }
        return value(forKey: Self.mainFrameKey) as? FrameHandle ?? .fallbackMainFrameHandle
    }

#endif

    private static let committedURLKey = "committedURL"
    public var committedURL: URL? {
        guard self.responds(to: NSSelectorFromString("_" + Self.committedURLKey))
                || self.responds(to: NSSelectorFromString(Self.committedURLKey)) else { return nil }
        return value(forKey: Self.committedURLKey) as? URL
    }

#if _SESSION_STATE_WITH_FILTER_ENABLED

    @nonobjc
    @available(macOS, deprecated: 12.0)
    public func sessionStateData() -> Data? {
        guard self.responds(to: Selector.sessionStateData) else {
            assertionFailure("\(Self.self) does not respond to _sessionStateData")
            return nil
        }

        return self.perform(Selector.sessionStateData)?.takeUnretainedValue() as? Data
    }

    @nonobjc
    @available(macOS, deprecated: 12.0)
    public func restoreSessionState(from data: Data) {
        guard self.responds(to: Selector.restoreFromSessionStateData) else {
            assertionFailure("\(Self.self) does not respond to _restoreFromSessionStateData:")
            return
        }

        self.perform(Selector.restoreFromSessionStateData, with: data)
    }

    public typealias SessionStateFilterBlockType = @convention(block) (WKBackForwardListItem) -> Bool
    @nonobjc
    public func sessionState(withFilter filter: @escaping SessionStateFilterBlockType) -> Any? {
        guard self.responds(to: Selector.sessionStateWithFilter) else {
            assertionFailure("\(Self.self) does not respond to _sessionStateWithFilter:")
            return nil
        }

        let result = self.perform(Selector.sessionStateWithFilter, with: filter)?.takeUnretainedValue()
        return result
    }

    @discardableResult
    @nonobjc
    public func restoreSessionState(from sessionState: Any, andNavigate shouldNavigate: Bool) -> WKNavigation? {
        guard self.responds(to: Selector.restoreSessionStateAndNavigate) else {
            assertionFailure("\(Self.self) does not respond to _restoreSessionState:andNavigate:")
            return nil
        }
        let result = self.perform(Selector.restoreSessionStateAndNavigate, with: sessionState, with: shouldNavigate ? true : nil)?.takeUnretainedValue() as? WKNavigation
        return result
    }

    enum Selector {
        static let sessionStateData = NSSelectorFromString("_sessionStateData")
        static let restoreFromSessionStateData = NSSelectorFromString("_restoreFromSessionStateData:")
        static let sessionStateWithFilter = NSSelectorFromString("_sessionStateWithFilter:")
        static let restoreSessionStateAndNavigate = NSSelectorFromString("_restoreSessionState:andNavigate:")
    }

#endif

#if !_MAIN_FRAME_NAVIGATION_ENABLED

    static let swizzleLoadMethodOnce: Void = {
        var selectors = [
            #selector(load(_:)): #selector(navigation_load(_:)),
            #selector(loadFileURL): #selector(navigation_loadFileURL),
            #selector(loadHTMLString): #selector(navigation_loadHTMLString),
            #selector(load(_:mimeType:characterEncodingName:baseURL:)): #selector(navigation_load(_:mimeType:characterEncodingName:baseURL:)),
            #selector(go(to:)): #selector(navigation_go(to:)),
            NSSelectorFromString("goBack"): #selector(navigation_goBack),
            NSSelectorFromString("goForward"): #selector(navigation_goForward),
            NSSelectorFromString("reload"): #selector(navigation_reload),
            NSSelectorFromString("reloadFromOrigin"): #selector(navigation_reloadFromOrigin),
        ]
        if #available(macOS 12.0, iOS 15.0, *) {
            selectors.merge([
                #selector(loadFileRequest(_:allowingReadAccessTo:)): #selector(navigation_loadFileRequest(_:allowingReadAccessTo:)),
                #selector(loadSimulatedRequest(_:response:responseData:)): #selector(navigation_loadSimulatedRequest(_:response:responseData:)),
                #selector(loadSimulatedRequest(_:responseHTML:)): #selector(navigation_loadSimulatedRequest(_:responseHTML:)),
            ]) { _, _ in fatalError() }
        }
        for (selector, swizzledSelector) in selectors {
            let originalMethod = class_getInstanceMethod(WKWebView.self, selector)!
            let swizzledMethod = class_getInstanceMethod(WKWebView.self, swizzledSelector)!
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }()

    private static let expectedMainFrameNavigationsKey = UnsafeRawPointer(bitPattern: "expectedMainFrameNavigations".hashValue)!
    private var expectedMainFrameNavigations: [HashableURLRequest: WeakWKNavigationBox] {
        get {
            objc_getAssociatedObject(self, Self.expectedMainFrameNavigationsKey) as? [HashableURLRequest: WeakWKNavigationBox] ?? [:]
        }
        set {
            objc_setAssociatedObject(self, Self.expectedMainFrameNavigationsKey, newValue.filter { $0.value.ref != nil }, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    fileprivate func addExpectedNavigation(_ navigation: WKNavigation, matching request: URLRequest) {
        expectedMainFrameNavigations[.init(request)] = WeakWKNavigationBox(ref: navigation)
    }

    internal func expectedMainFrameNavigation(for navigationAction: WKNavigationAction) -> WKNavigation? {
        // return and nullify the same dict record
        withUnsafeMutablePointer(to: &expectedMainFrameNavigations[.init(navigationAction.request)]) { ptr in
            defer {
                ptr.pointee = nil
            }
            return ptr.pointee?.ref
        }
    }

    @objc dynamic private func navigation_load(_ request: URLRequest) -> WKNavigation? {
        navigation_load(request)?.appendingToExpectedNavigations(in: self, matching: request)
    }
    @objc dynamic private func navigation_loadFileURL(_ url: URL, allowingReadAccessTo readAccessURL: URL) -> WKNavigation? {
        navigation_loadFileURL(url, allowingReadAccessTo: readAccessURL)?.appendingToExpectedNavigations(in: self, matching: URLRequest(url: url))
    }
    @objc dynamic private func navigation_loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
        navigation_loadHTMLString(string, baseURL: baseURL)?.appendingToExpectedNavigations(in: self, matching: URLRequest(url: baseURL ?? url ?? .empty))
    }
    @objc dynamic private func navigation_load(_ data: Data, mimeType MIMEType: String, characterEncodingName: String, baseURL: URL) -> WKNavigation? {
        navigation_load(data, mimeType: MIMEType, characterEncodingName: characterEncodingName, baseURL: baseURL)?.appendingToExpectedNavigations(in: self, matching: URLRequest(url: baseURL))
    }
    @objc dynamic private func navigation_go(to item: WKBackForwardListItem) -> WKNavigation? {
        navigation_go(to: item)?.appendingToExpectedNavigations(in: self, matching: URLRequest(url: item.url, cachePolicy: .returnCacheDataElseLoad))
    }
    @objc dynamic private func navigation_goBack() -> WKNavigation? {
        navigation_goBack()?.appendingToExpectedNavigations(in: self, matching: URLRequest(url: backForwardList.backItem?.url ?? .empty, cachePolicy: .returnCacheDataElseLoad))
    }
    @objc dynamic private func navigation_goForward() -> WKNavigation? {
        navigation_goForward()?.appendingToExpectedNavigations(in: self, matching: URLRequest(url: backForwardList.forwardItem?.url ?? .empty, cachePolicy: .returnCacheDataElseLoad))
    }
    @objc dynamic private func navigation_reload() -> WKNavigation? {
        navigation_reload()?.appendingToExpectedNavigations(in: self, matching: URLRequest(url: url ?? .empty, cachePolicy: .reloadIgnoringLocalCacheData))
    }
    @objc dynamic private func navigation_reloadFromOrigin() -> WKNavigation? {
        navigation_reloadFromOrigin()?.appendingToExpectedNavigations(in: self, matching: URLRequest(url: url ?? .empty, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
    }

    @objc dynamic private func navigation_loadFileRequest(_ request: URLRequest, allowingReadAccessTo readAccessURL: URL) -> WKNavigation {
        navigation_loadFileRequest(request, allowingReadAccessTo: readAccessURL).appendingToExpectedNavigations(in: self, matching: request)
    }

    @objc dynamic private func navigation_loadSimulatedRequest(_ request: URLRequest, response: URLResponse, responseData data: Data) -> WKNavigation {
        navigation_loadSimulatedRequest(request, response: response, responseData: data).appendingToExpectedNavigations(in: self, matching: request)
    }

    @objc dynamic private func navigation_loadSimulatedRequest(_ request: URLRequest, responseHTML string: String) -> WKNavigation {
        navigation_loadSimulatedRequest(request, responseHTML: string).appendingToExpectedNavigations(in: self, matching: request)
    }

#endif

}

#if !_MAIN_FRAME_NAVIGATION_ENABLED
struct WeakWKNavigationBox {
    weak var ref: WKNavigation?
}

struct HashableURLRequest: Hashable {
    var url: String?
    var cachePolicy: URLRequest.CachePolicy
    var timeoutInterval: TimeInterval

    init(url: URL? = nil, cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy, timeoutInterval: TimeInterval = 60) {
        self.url = url?.absoluteString.dropping(suffix: "/")
        self.cachePolicy = cachePolicy
        self.timeoutInterval = timeoutInterval
    }

    init(_ request: URLRequest) {
        self.init(url: request.url, cachePolicy: request.cachePolicy, timeoutInterval: request.timeoutInterval)
    }
}

extension WKNavigation {
    func appendingToExpectedNavigations(in webView: WKWebView, matching request: URLRequest) -> WKNavigation {
        webView.addExpectedNavigation(self, matching: request)
        return self
    }
}
#endif
