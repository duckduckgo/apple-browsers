//
//  NavigationAction.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import WebKit

public struct MainFrame: Sendable {
    fileprivate init() {}
}

public struct NavigationAction {

    private static var maxIdentifier: UInt64 = 0
#if DEBUG
    static func resetIdentifier() { maxIdentifier = 0 }
#endif

    /// auto-incremented id
    public var identifier: UInt64 = {
        Self.maxIdentifier += 1
        return Self.maxIdentifier
    }()

    public let request: URLRequest

    public let navigationType: NavigationType
#if os(macOS)
    /// keyboard modifiers for `linkActivated` NavigationType
    public internal(set) var modifierFlags: NSEvent.ModifierFlags = []
#endif

#if _IS_USER_INITIATED_ENABLED
    /// if navigation was initiated by user action on a web page
    public let isUserInitiated: Bool
#endif
    public let shouldDownload: Bool

    /// The frame requesting the navigation
    public let sourceFrame: FrameInfo
    /// The target frame, `nil` if this is a new window navigation
    public let targetFrame: FrameInfo?

    /// Used to protect main frame .redirect NavigationActionPolicy actions as only main frame can be redirected
    /// `nil` for non-main-frame navigations
    public var mainFrameTarget: MainFrame? {
        guard targetFrame?.isMainFrame == true else { return nil }
        return MainFrame()
    }

    /// Currently active Main Frame Navigation associated with the NavigationAction
    /// May be non-nil for non-main-frame NavigationActions
    public internal(set) weak var mainFrameNavigation: Navigation?

#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
    /// Actual `BackForwardListItem` identity before the NavigationAction had started
    public let fromHistoryItemIdentity: HistoryItemIdentity?
#endif
    /// Previous Navigation Actions received during current logical `Navigation`, includes .server, .client and .developer redirects
    /// zero-based, most recent is the last redirect
    public let redirectHistory: [NavigationAction]?

    public init(request: URLRequest, navigationType: NavigationType, currentHistoryItemIdentity: HistoryItemIdentity?, redirectHistory: [NavigationAction]?, isUserInitiated: Bool?, sourceFrame: FrameInfo, targetFrame: FrameInfo?, shouldDownload: Bool, mainFrameNavigation: Navigation?) {
        var request = request
        if request.allHTTPHeaderFields == nil {
            request.allHTTPHeaderFields = [:]
        }
        if request.url == nil {
            request.url = .empty
        }
        self.request = request
        self.navigationType = navigationType
#if _IS_USER_INITIATED_ENABLED
        self.isUserInitiated = isUserInitiated ?? false
#endif
        self.shouldDownload = shouldDownload

        self.sourceFrame = sourceFrame
        self.targetFrame = targetFrame

#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
        self.fromHistoryItemIdentity = currentHistoryItemIdentity
#endif
        self.redirectHistory = redirectHistory
        self.mainFrameNavigation = mainFrameNavigation
    }

    internal init(webView: WKWebView, navigationAction: WKNavigationAction, currentHistoryItemIdentity: HistoryItemIdentity?, redirectHistory: [NavigationAction]?, navigationType: NavigationType? = nil, mainFrameNavigation: Navigation?) {
        // In this cruel reality the source frame IS Nullable for developer-initiated load events, this would mean we‘re targeting the main frame
        var sourceFrame = (navigationAction.safeSourceFrame ?? navigationAction.targetFrame).map(FrameInfo.init) ?? .mainFrame(for: webView)
        // always has targetFrame if not targeting to a new window
        var targetFrame = navigationAction.targetFrame.map(FrameInfo.init)

        // To be adjusted when fixed in WebKit
        // see WKNavigationActionExtension: isSameDocumentNavigation
        if let frame = targetFrame,
           frame.isMainFrame, navigationAction.isSameDocumentNavigation,
           let committedURL = webView.committedURL,
           frame.url != committedURL {
#if _FRAME_HANDLE_ENABLED
            targetFrame = FrameInfo(webView: frame.webView,
                                    handle: frame.handle,
                                    isMainFrame: frame.isMainFrame,
                                    url: committedURL,
                                    securityOrigin: committedURL.securityOrigin)
#else
            targetFrame = FrameInfo(webView: frame.webView,
                                    isMainFrame: frame.isMainFrame,
                                    url: committedURL,
                                    securityOrigin: committedURL.securityOrigin)
#endif
            if sourceFrame == frame {
                sourceFrame = targetFrame!
            }
        }
        var navigationType = navigationType

        if case .other = navigationAction.navigationType,
           case .returnCacheDataElseLoad = navigationAction.request.cachePolicy,
           navigationType == nil,
           redirectHistory == nil,
           navigationAction.targetFrame?.isMainFrame == true,
           navigationAction.targetFrame?.safeRequest?.url?.isEmpty == true,
           webView.backForwardList.currentItem != nil {

            // go back after failing session restoration has `other` Navigation Type
#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
            if let currentHistoryItemIdentity,
               let distance = navigationAction.getDistance(from: currentHistoryItemIdentity) {

                navigationType = .backForward(distance: distance)
            // session restoration
            } else if navigationAction.isUserInitiated != true,
                      currentHistoryItemIdentity == nil {
                navigationType = .sessionRestoration
            }
#else
            if navigationAction.isUserInitiated != true {
                navigationType = .sessionRestoration
            }
#endif
        }

        self.init(request: navigationAction.request,
                  navigationType: navigationType ?? NavigationType(navigationAction, currentHistoryItemIdentity: currentHistoryItemIdentity),
                  currentHistoryItemIdentity: currentHistoryItemIdentity,
                  redirectHistory: redirectHistory,
                  isUserInitiated: navigationAction.isUserInitiated,
                  sourceFrame: sourceFrame,
                  targetFrame: targetFrame,
                  shouldDownload: navigationAction.shouldDownload,
                  mainFrameNavigation: mainFrameNavigation)
#if os(macOS)
        self.modifierFlags = navigationAction.modifierFlags
#endif
    }

    internal static func sessionRestoreNavigation(webView: WKWebView, mainFrameNavigation: Navigation?) -> Self {
        assert(webView.backForwardList.currentItem == nil)
        return self.init(request: URLRequest(url: webView.url ?? .empty), navigationType: .sessionRestoration, currentHistoryItemIdentity: nil, redirectHistory: nil, isUserInitiated: false, sourceFrame: .mainFrame(for: webView), targetFrame: .mainFrame(for: webView), shouldDownload: false, mainFrameNavigation: mainFrameNavigation)
    }

    internal static func alternateHtmlLoadNavigation(webView: WKWebView, mainFrameNavigation: Navigation?) -> Self {
        return self.init(request: URLRequest(url: webView.url ?? .empty), navigationType: .alternateHtmlLoad, currentHistoryItemIdentity: nil, redirectHistory: nil, isUserInitiated: false, sourceFrame: .mainFrame(for: webView), targetFrame: .mainFrame(for: webView), shouldDownload: false, mainFrameNavigation: mainFrameNavigation)
    }

}

public extension NavigationAction {

    var isForMainFrame: Bool {
        targetFrame?.isMainFrame == true
    }

    /// if another WebView initiated the navigation
    var isTargetingNewWindow: Bool {
        assert(sourceFrame.webView != nil || targetFrame?.webView != nil)
        return sourceFrame.webView != targetFrame?.webView || targetFrame?.webView == nil
    }

    var url: URL {
        request.url ?? .empty
    }

}

public struct NavigationPreferences: Equatable {

    public var userAgent: String?
    public var contentMode: WKWebpagePreferences.ContentMode

    fileprivate var javaScriptEnabledValue: Bool
    public var javaScriptEnabled: Bool {
        get {
            javaScriptEnabledValue
        }
        set {
            javaScriptEnabledValue = newValue
        }
    }

    public static let `default` = NavigationPreferences(userAgent: nil, contentMode: .recommended, javaScriptEnabled: true)

#if _WEBPAGE_PREFS_CUSTOM_HEADERS_ENABLED
    public static var customHeadersSupported: Bool {
        WKWebpagePreferences.customHeaderFieldsSupported
    }

    public var customHeaders: [CustomHeaderFields]?
#else
    public static var customHeadersSupported: Bool { false }
#endif

    public init(userAgent: String?, contentMode: WKWebpagePreferences.ContentMode, javaScriptEnabled: Bool) {
        self.userAgent = userAgent
        self.contentMode = contentMode
        self.javaScriptEnabledValue = javaScriptEnabled
    }

    internal init(userAgent: String?, preferences: WKWebpagePreferences) {
        self.contentMode = preferences.preferredContentMode
        self.javaScriptEnabledValue = preferences.allowsContentJavaScript
#if _WEBPAGE_PREFS_CUSTOM_HEADERS_ENABLED
        if Self.customHeadersSupported {
            self.customHeaders = preferences.customHeaderFields
        }
#endif
    }

    internal func applying(to preferences: WKWebpagePreferences) -> WKWebpagePreferences {
        preferences.preferredContentMode = contentMode
        preferences.allowsContentJavaScript = javaScriptEnabled
#if _WEBPAGE_PREFS_CUSTOM_HEADERS_ENABLED
        if Self.customHeadersSupported, let customHeaders = customHeaders {
            preferences.customHeaderFields = customHeaders
        }
#endif
        return preferences
    }

}

public enum NavigationActionPolicy: Sendable {
    case allow
    case cancel
    case download
    case redirect(MainFrame, @Sendable @MainActor (Navigator) -> Void)
}

extension NavigationActionPolicy? {
    /// Pass decision making to next responder
    public static let next = NavigationActionPolicy?.none
}

extension NavigationActionPolicy? {
    public var debugDescription: String {
        if case .some(let policy) = self {
            return policy.debugDescription
        }
        return "next"
    }
}

extension NavigationAction: CustomDebugStringConvertible {
    public var debugDescription: String {
#if _IS_USER_INITIATED_ENABLED
        let isUserInitiatedStr = isUserInitiated ? " [user-initiated]" : ""
#else
        let isUserInitiatedStr = ""
#endif
#if _FRAME_HANDLE_ENABLED
        let sourceFrame = sourceFrame != targetFrame ? sourceFrame.debugDescription + " -> " : ""
#else
        let sourceFrame = sourceFrame.debugDescription + " -> "
#endif
#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
        let fromHistoryItem = fromHistoryItemIdentity != nil ? " from: " + fromHistoryItemIdentity!.debugDescription : ""
#else
        let fromHistoryItem = ""
#endif
        return "<NavigationAction #\(identifier)\(isUserInitiatedStr): url: \"\(url.absoluteString)\" type: \(navigationType.debugDescription)\(shouldDownload ? " Download" : "") frame: \(sourceFrame)\(targetFrame.debugDescription)\(fromHistoryItem)>"
    }
}

extension NavigationActionPolicy: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .allow: return "allow"
        case .cancel: return "cancel"
        case .download: return "download"
        case .redirect: return "redirect"
        }
    }
}

extension NavigationPreferences: CustomDebugStringConvertible {
    public var debugDescription: String {
        "\(userAgent ?? "")\(contentMode == .recommended ? "" : (contentMode == .mobile ? ":mobile" : "desktop"))\(javaScriptEnabledValue == false ? ":jsdisabled" : "")"
    }
}

extension HistoryItemIdentity: CustomDebugStringConvertible {
    public var debugDescription: String {
        "<\(identifier) url: \(url?.absoluteString ?? "") title: \(title ?? "<nil>")>"
    }
}
