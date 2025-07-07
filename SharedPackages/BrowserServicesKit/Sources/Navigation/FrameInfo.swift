//
//  FrameInfo.swift
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

public struct FrameInfo {

    public weak var webView: WKWebView?

    public let isMainFrame: Bool
    public let url: URL
    public let securityOrigin: SecurityOrigin

#if _FRAME_HANDLE_ENABLED
    public let handle: FrameHandle

    public init(webView: WKWebView?, handle: FrameHandle, isMainFrame: Bool, url: URL, securityOrigin: SecurityOrigin) {
        self.webView = webView
        self.handle = handle
        self.isMainFrame = isMainFrame
        self.url = url
        self.securityOrigin = securityOrigin
    }

    public init(frame: WKFrameInfo) {
        self.init(webView: frame.webView, handle: frame.handle, isMainFrame: frame.isMainFrame, url: frame.safeRequest?.url ?? .empty, securityOrigin: SecurityOrigin(frame.securityOrigin))
    }

    public static func mainFrame(for webView: WKWebView) -> FrameInfo {
        FrameInfo(webView: webView,
                  handle: webView.mainFrameHandle,
                  isMainFrame: true,
                  url: webView.url ?? .empty,
                  securityOrigin: webView.url?.securityOrigin ?? .empty)
    }

#else

    public init(webView: WKWebView?, isMainFrame: Bool, url: URL, securityOrigin: SecurityOrigin) {
        self.webView = webView
        self.isMainFrame = isMainFrame
        self.url = url
        self.securityOrigin = securityOrigin
    }

    public init(frame: WKFrameInfo) {
        self.init(webView: frame.webView, isMainFrame: frame.isMainFrame, url: frame.safeRequest?.url ?? .empty, securityOrigin: SecurityOrigin(frame.securityOrigin))
    }

    public static func mainFrame(for webView: WKWebView) -> FrameInfo {
        FrameInfo(webView: webView,
                  isMainFrame: true,
                  url: webView.url ?? .empty,
                  securityOrigin: webView.url?.securityOrigin ?? .empty)
    }

#endif
}

#if _FRAME_HANDLE_ENABLED
extension FrameInfo: Equatable {
    public static func == (lhs: FrameInfo, rhs: FrameInfo) -> Bool {
        return lhs.handle == rhs.handle && lhs.webView == rhs.webView && lhs.isMainFrame == rhs.isMainFrame && lhs.url.matches(rhs.url) && lhs.securityOrigin == rhs.securityOrigin
    }
}
#else
extension FrameInfo: Equatable {
    public static func == (lhs: FrameInfo, rhs: FrameInfo) -> Bool {
        return lhs.webView == rhs.webView && lhs.isMainFrame && rhs.isMainFrame && lhs.url.matches(rhs.url) && lhs.securityOrigin == rhs.securityOrigin
    }
}
#endif

extension SecurityOrigin {
    public init(_ securityOrigin: WKSecurityOrigin) {
        self.init(protocol: securityOrigin.protocol, host: securityOrigin.host, port: securityOrigin.port)
    }
}

extension FrameInfo: CustomDebugStringConvertible {
    public var debugDescription: String {
        let webViewPtr = webView.map(NSValue.init(nonretainedObject:))?.pointerValue?.debugDescription.replacing(regex: "^0x0*", with: "0x") ?? "<nil>"
#if _FRAME_HANDLE_ENABLED
        let handle = handle.debugDescription + " "
#else
        let handle = ""
#endif
        return "<Frame \(webViewPtr)_\(handle)\(isMainFrame ? ": Main" : ""); current url: \(url.absoluteString.isEmpty ? "empty" : url.absoluteString)>"
    }
}
