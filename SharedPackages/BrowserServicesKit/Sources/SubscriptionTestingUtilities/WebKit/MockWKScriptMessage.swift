//
//  MockWKScriptMessage.swift
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

/// Mock implementation for creating WKScriptMessage instances in tests.
/// Uses unsafe pointer casting to create a mock object that can be used as WKScriptMessage.
public class MockWKScriptMessageObject: NSObject {

    @objc public var webView: WKWebView?
    @objc public var frameInfo: WKFrameInfo
    @objc public var name: String
    @objc public var body: Any

    /// Creates a mock script message object.
    ///
    /// - Parameters:
    ///   - webView: The web view that sent the message
    ///   - frameInfo: Information about the frame that sent the message
    ///   - name: The name of the message (default: "")
    ///   - body: The body of the message (default: [:])
    public init(webView: WKWebView?, frameInfo: WKFrameInfo, name: String = "", body: Any = [:]) {
        self.webView = webView
        self.frameInfo = frameInfo
        self.name = name
        self.body = body
    }

    /// Returns a WKScriptMessage instance that can be used in tests.
    public var scriptMessage: WKScriptMessage {
        withUnsafePointer(to: self) { $0.withMemoryRebound(to: WKScriptMessage.self, capacity: 1) { $0 } }.pointee
    }
}

extension WKScriptMessage {
    /// Creates a mock WKScriptMessage for testing.
    ///
    /// - Parameters:
    ///   - webView: The web view
    ///   - frameInfo: The frame info
    ///   - name: Message name (default: "")
    ///   - body: Message body (default: [:])
    /// - Returns: A WKScriptMessage instance suitable for testing
    public static func mock(webView: WKWebView?, frameInfo: WKFrameInfo, name: String = "", body: Any = [:]) -> WKScriptMessage {
        return MockWKScriptMessageObject(webView: webView, frameInfo: frameInfo, name: name, body: body).scriptMessage
    }
}
