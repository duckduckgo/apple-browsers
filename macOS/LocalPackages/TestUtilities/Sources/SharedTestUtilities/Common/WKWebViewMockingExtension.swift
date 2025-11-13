//
//  WKWebViewMockingExtension.swift
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

import Common
import Foundation
import ObjectiveC
import SharedObjCTestsUtils
import WebKit

@available(macOS 12.0, *)
public extension WKWebView {

    private static let simulatedRequestHandlersKey = UnsafeRawPointer(bitPattern: "simulatedRequestsKey".hashValue)!
    private static let delegateTestsProxyKey = UnsafeRawPointer(bitPattern: "delegateTestsProxyKey".hashValue)!

    // allow setting WKURLSchemeHandler for WebView-handled schemes like HTTP
    static var customHandlerSchemes = Set<URL.NavigationalScheme>() {
        didSet {
            _=swizzleHandlesURLSchemeOnce
        }
    }

    private static let swizzleHandlesURLSchemeOnce: Void = {
        let originalLoad = class_getClassMethod(WKWebView.self, #selector(WKWebView.handlesURLScheme))!
        let swizzledLoad = class_getClassMethod(WKWebView.self, #selector(WKWebView.swizzled_handlesURLScheme))!
        method_exchangeImplementations(originalLoad, swizzledLoad)
    }()

    @objc dynamic private class func swizzled_handlesURLScheme(_ urlScheme: String) -> Bool {
        guard !customHandlerSchemes.contains(URL.NavigationalScheme(rawValue: urlScheme)) else { return false }
        return self.swizzled_handlesURLScheme(urlScheme) // call original
    }

}

@available(macOS 12.0, *)
public class TestSchemeHandler: NSObject, WKURLSchemeHandler {

    public var middleware: [(URLRequest) -> WKURLSchemeTaskHandler?]

    public init(middleware: ((URLRequest) -> WKURLSchemeTaskHandler?)? = nil) {
        self.middleware = middleware.map { [$0] } ?? []
    }

    public func webViewConfiguration(withCustomSchemeHandlersFor navigationalSchemes: [URL.NavigationalScheme] = [.http, .https]) -> WKWebViewConfiguration {
        WKWebView.customHandlerSchemes = WKWebView.customHandlerSchemes.union(navigationalSchemes)

        let webViewConfiguration = WKWebViewConfiguration()

        // mock WebView https protocol handling
        webViewConfiguration.setURLSchemeHandler(self, forURLScheme: URL.NavigationalScheme.http.rawValue)
        webViewConfiguration.setURLSchemeHandler(self, forURLScheme: URL.NavigationalScheme.https.rawValue)

        return webViewConfiguration
    }

    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        for middleware in middleware {
            if let handler = middleware(urlSchemeTask.request) {
                handler(urlSchemeTask)
                return
            }
        }
        urlSchemeTask.didFailWithError(WKError(WKError.Code(rawValue: NSURLErrorCancelled)!))
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    deinit {
        WKWebView.customHandlerSchemes = []
    }
}

public struct WKURLSchemeTaskHandler {

    public enum OkResult {
        case data(Data, mime: String? = nil)
        case html(String)

        public var mime: String? {
            switch self {
            case .data(_, mime: let mime):
                return mime
            case .html:
                return "text/html"
            }
        }
        public var data: Data {
            switch self {
            case .data(let data, mime: _):
                return data
            case .html(let string):
                return string.data(using: .utf8)!
            }
        }
    }

    public static func ok(code: Int = 200, headers: [String: String] = [:], _ result: OkResult) -> WKURLSchemeTaskHandler {
        .init { task in
            let response = MockHTTPURLResponse(url: task.request.url!, statusCode: code, mime: result.mime, headerFields: headers)!

            task.didReceive(response)
            task.didReceive(result.data)
            task.didFinish()
        }
    }

    public static func failure(_ error: Error) -> WKURLSchemeTaskHandler {
        .init { task in
            task.didFailWithError(error)
        }
    }

    public static func redirect(to url: URL) -> WKURLSchemeTaskHandler {
        redirect(to: url.absoluteString)
    }

    public static func redirect(to location: String) -> WKURLSchemeTaskHandler {
        .init { task in
            let response = MockHTTPURLResponse(url: task.request.url!,
                                               statusCode: 301,
                                               mime: nil,
                                               headerFields: ["Location": location])!

            task.didPerformRedirection(response, newRequest: URLRequest(url: URL(string: location, relativeTo: task.request.url)!))
            task.didReceive(response)
            task.didFinish()
        }
    }

    public static func redirect(to url: URL, with error: NSError) -> WKURLSchemeTaskHandler {
        .init { task in
            let response = MockHTTPURLResponse(url: task.request.url!,
                                               statusCode: 301,
                                               mime: nil,
                                               headerFields: ["Location": url.absoluteString])!

            task.didPerformRedirection(response, newRequest: URLRequest(url: url))
            task.didFailWithError(error)
        }
    }

    public let handler: (WKURLSchemeTask) -> Void
    public init(handler: @escaping (WKURLSchemeTask) -> Void) {
        self.handler = handler
    }

    public func callAsFunction(_ task: WKURLSchemeTask) {
        handler(task)
    }

}

extension WKURLSchemeTask {
    typealias WillPerformRedirectionCompletionHandler = @convention(c) (NSURLRequest) -> Void
    // - (void)_willPerformRedirection:(NSURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler;
    func willPerformRedirection(_ response: URLResponse, newRequest: URLRequest, completionHandler: WillPerformRedirectionCompletionHandler) {
        let selector = NSSelectorFromString("_willPerformRedirection:newRequest:completionHandler:")
        guard let method = class_getInstanceMethod(object_getClass(self), selector) else {
            fatalError("WKURLSchemeTask._willPerformRedirection:newRequest:completionHandler: not available")
        }
        let imp = method_getImplementation(method)
        typealias WillPerformRedirectionType = @convention(c) (WKURLSchemeTask, ObjectiveC.Selector, URLResponse, NSURLRequest, WillPerformRedirectionCompletionHandler) -> Void
        let willPerformRedirection = unsafeBitCast(imp, to: WillPerformRedirectionType.self)
        willPerformRedirection(self, selector, response, newRequest as NSURLRequest, completionHandler)
    }

    // - (void)_didPerformRedirection:(NSURLResponse *)response newRequest:(NSURLRequest *)request;
    func didPerformRedirection(_ response: URLResponse, newRequest: URLRequest) {
        let selector = NSSelectorFromString("_didPerformRedirection:newRequest:")
        guard let method = class_getInstanceMethod(object_getClass(self), selector) else {
            fatalError("WKURLSchemeTask._didPerformRedirection:newRequest: not available")
        }
        let imp = method_getImplementation(method)
        typealias DidPerformRedirectionType = @convention(c) (WKURLSchemeTask, ObjectiveC.Selector, URLResponse, NSURLRequest) -> Void
        let didPerformRedirection = unsafeBitCast(imp, to: DidPerformRedirectionType.self)
        didPerformRedirection(self, selector, response, newRequest as NSURLRequest)
    }
}

public class MockHTTPURLResponse: HTTPURLResponse, @unchecked Sendable {

    private let mime: String?

    public override var mimeType: String? {
        mime ?? super.mimeType
    }

    public override var suggestedFilename: String? {
        URLResponse(url: url!, mimeType: mimeType, expectedContentLength: Int(expectedContentLength), textEncodingName: textEncodingName).suggestedFilename ?? super.suggestedFilename
    }

    public init?(url: URL, statusCode: Int, mime: String?, httpVersion: String? = nil, headerFields: [String: String]?) {
        self.mime = mime
        super.init(url: url, statusCode: statusCode, httpVersion: httpVersion, headerFields: headerFields)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}
