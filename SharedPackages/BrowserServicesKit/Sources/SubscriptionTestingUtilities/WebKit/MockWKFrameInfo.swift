//
//  MockWKFrameInfo.swift
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

import Foundation
import WebKit

/// Mock implementation for creating WKFrameInfo instances in tests.
/// Uses unsafe pointer casting to create a mock object that can be used as WKFrameInfo.
public class MockWKFrameInfoObject: NSObject {

    @objc public var isMainFrame: Bool
    @objc public var securityOrigin: WKSecurityOrigin
    @objc public weak var webView: WKWebView?

    /// Creates a mock frame info object.
    ///
    /// - Parameters:
    ///   - isMainFrame: Whether this frame is the main frame
    ///   - securityOrigin: The security origin for this frame
    ///   - webView: The web view (optional)
    public init(isMainFrame: Bool, securityOrigin: WKSecurityOrigin, webView: WKWebView? = nil) {
        self.isMainFrame = isMainFrame
        self.securityOrigin = securityOrigin
        self.webView = webView
    }

    /// Returns a WKFrameInfo instance that can be used in tests.
    public var frameInfo: WKFrameInfo {
        withUnsafePointer(to: self) { $0.withMemoryRebound(to: WKFrameInfo.self, capacity: 1) { $0 } }.pointee
    }
}

extension WKFrameInfo {
    /// Creates a mock WKFrameInfo for testing.
    ///
    /// - Parameters:
    ///   - isMainFrame: Whether this is the main frame
    ///   - securityOriginHost: The host for the security origin
    ///   - webView: Optional web view
    /// - Returns: A WKFrameInfo instance suitable for testing
    public static func mock(isMainFrame: Bool, securityOriginHost: String, webView: WKWebView? = nil) -> WKFrameInfo {
        let securityOrigin = MockWKSecurityOrigin.new(host: securityOriginHost)
        return MockWKFrameInfoObject(isMainFrame: isMainFrame, securityOrigin: securityOrigin, webView: webView).frameInfo
    }

    /// Creates a mock WKFrameInfo for testing with a custom security origin.
    ///
    /// - Parameters:
    ///   - isMainFrame: Whether this is the main frame
    ///   - securityOrigin: The security origin
    ///   - webView: Optional web view
    /// - Returns: A WKFrameInfo instance suitable for testing
    public static func mock(isMainFrame: Bool, securityOrigin: WKSecurityOrigin, webView: WKWebView? = nil) -> WKFrameInfo {
        return MockWKFrameInfoObject(isMainFrame: isMainFrame, securityOrigin: securityOrigin, webView: webView).frameInfo
    }
}
