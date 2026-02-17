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

public class MockWKScriptMessageObject: NSObject {

    @objc public weak var webView: WKWebView?
    @objc public var frameInfo: WKFrameInfo
    @objc public var name: String
    @objc public var body: Any

    public init(webView: WKWebView?, frameInfo: WKFrameInfo, name: String = "", body: Any = [:]) {
        self.webView = webView
        self.frameInfo = frameInfo
        self.name = name
        self.body = body
    }

    override public func value(forUndefinedKey key: String) -> Any? { nil }

    public var scriptMessage: WKScriptMessage {
        withUnsafePointer(to: self) { $0.withMemoryRebound(to: WKScriptMessage.self, capacity: 1) { $0 } }.pointee
    }
}

extension WKScriptMessage {
    public static func mock(webView: WKWebView?, frameInfo: WKFrameInfo, name: String = "", body: Any = [:]) -> WKScriptMessage {
        return MockWKScriptMessageObject(webView: webView, frameInfo: frameInfo, name: name, body: body).scriptMessage
    }

    public static func mock(name: String = "", body: Any = [:], webView: WKWebView? = nil) -> WKScriptMessage {
        let frameInfo = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com")
        return MockWKScriptMessageObject(webView: webView, frameInfo: frameInfo, name: name, body: body).scriptMessage
    }
}
