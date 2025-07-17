//
//  NavigationTestHelpers.swift
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

import Combine
import Common
import Foundation
import Navigation
import WebKit

// swiftlint:disable cyclomatic_complexity
// swiftlint:disable implicit_getter

// swiftlint:disable:next large_tuple
typealias EncodingContext = (urls: Any, webView: WKWebView, dataSource: Any, navigationActions: UnsafeMutablePointer<[UInt64: NavAction]>, navigationResponses: UnsafeMutablePointer<[NavigationResponse]>, responderResponses: [NavResponse], history: [UInt64: HistoryItemIdentity])
extension TestsNavigationEvent {

    static func navigationAction(_ request: URLRequest, _ navigationType: NavigationType, from currentHistoryItemIdentity: HistoryItemIdentity? = nil, redirects: [NavAction]? = nil, _ isUserInitiated: NavigationAction.UserInitiated? = nil, src: FrameInfo, targ: FrameInfo?, _ shouldDownload: NavigationAction.ShouldDownload? = nil, line: UInt = #line) -> TestsNavigationEvent {
        .navigationAction(.init(request, navigationType, from: currentHistoryItemIdentity, redirects: redirects, isUserInitiated, src: src, targ: targ, shouldDownload), line: line)
    }

    static func navigationAction(_ request: URLRequest, _ navigationType: NavigationType, from currentHistoryItemIdentity: HistoryItemIdentity? = nil, redirects: [NavAction]? = nil, _ isUserInitiated: NavigationAction.UserInitiated? = nil, src: FrameInfo, _ shouldDownload: NavigationAction.ShouldDownload? = nil, line: UInt = #line) -> TestsNavigationEvent {
        .navigationAction(.init(request, navigationType, from: currentHistoryItemIdentity, redirects: redirects, isUserInitiated, src: src, targ: src, shouldDownload), line: line)
    }

    static func response(_ nav: Nav, line: UInt = #line) -> TestsNavigationEvent {
        .navigationResponse(.navigation(nav), line: line)
    }
    static func response(_ response: NavResponse, _ nav: Nav?, line: UInt = #line) -> TestsNavigationEvent {
        .navigationResponse(.response(response, navigation: nav), line: line)
    }

    func encoded(_ context: EncodingContext) -> String {
        let v = { () -> String in
            switch self {
            case .navigationAction(let arg, let arg2, line: _):
                if let prefs = arg2.encoded() {
                    return ".navigationAction(\(arg.navigationAction.encoded(context)), \(prefs))"
                } else {
                    return ".navigationAction(" + arg.navigationAction.encoded(context).dropping(prefix: ".init") + ")"
                }
            case .didCancel(let arg, expected: let arg2, line: _):
                return ".didCancel(\(arg.navigationAction.encoded(context))\(arg2 != nil ? ", expected: \(arg2!)" : ""))"
            case .navActionWillBecomeDownload(let arg, line: _):
                return ".navActionWillBecomeDownload(\(arg.navigationAction.encoded(context)))"
            case .navActionBecameDownload(let arg, let arg2, line: _):
                return ".navActionBecameDownload(\(arg.navigationAction.encoded(context)), \(urlConst(for: URL(string: arg2)!, in: context.urls)!))"
            case .willStart(let arg, line: _):
                return ".willStart(\(arg.encoded(context)))"
            case .didStart(let arg, line: _):
                return ".didStart(\(arg.encoded(context)))"
            case .didReceiveAuthenticationChallenge(let arg, let arg2, line: _):
                return ".didReceiveAuthenticationChallenge(\(arg.encoded()), \(arg2?.encoded(context) ?? "nil"))"
            case .navigationResponse(.response(let resp, navigation: let nav), line: _):
                return ".response(.\(resp.response.encoded(context)), \(nav == nil ? "nil" : nav!.encoded(context)))"
            case .navigationResponse(.navigation(let nav), line: _):
                return ".response(\(nav.encoded(context)))"
            case .navResponseWillBecomeDownload(let arg, line: _):
                return ".navResponseWillBecomeDownload(\(arg))"
            case .navResponseBecameDownload(let arg, let arg2, line: _):
                return ".navResponseBecameDownload(\(arg), \(urlConst(for: arg2, in: context.urls)!))"
            case .didCommit(let arg, line: _):
                return ".didCommit(\(arg.encoded(context)))"
            case .didSameDocumentNavigation(let arg, let arg2, line: _):
                return ".didSameDocumentNavigation(\(arg?.encoded(context) ?? "nil"), \(arg2))"
            case .didReceiveRedirect(let navAct, let nav, line: _) where nav.navigationAction == navAct:
                return ".didReceiveRedirect(\(nav.encoded(context)))"
            case .didReceiveRedirect(let navAct, let nav, line: _):
                return ".didReceiveRedirect(\(navAct.navigationAction.encoded(context)), \(nav.encoded(context)))"
            case .didFinish(let arg, line: _):
                return ".didFinish(\(arg.encoded(context)))"
            case .didFail(let arg, let arg2, line: _):
                return ".didFail(\(arg.encoded(context)), \(arg2))"
            case .didTerminate(let arg, line: _):
                return arg != nil ? ".didTerminate(\(arg.map { ".init(rawValue: \($0.rawValue))" } ?? "nil"))" : ".terminated"
            }
        }().replacing(regex: "\\s\\s+", with: "")

        return v.replacingOccurrences(of: "  ", with: " ").replacing(regex: "\\s*,\\s*", with: ", ").replacing(regex: "\\s*\\+\\s*", with: " + ").replacing(regex: "\\s+\\)", with: ")").replacing(regex: "Accept-Language\\\": \\\"\\S\\S-\\S\\S, ", with: "Accept-Language\": \"en-XX,").replacingOccurrences(of: ", , ", with: ", ").replacingOccurrences(of: "..", with: ".")
    }

    static var terminated = TestsNavigationEvent.didTerminate(nil)
}

extension URLProtectionSpace {
    convenience init(_ host: String, _ port: Int = 0, _ protocol: String?, realm: String?, method: String?) {
        self.init(host: host, port: port, protocol: `protocol`, realm: realm, authenticationMethod: method)
    }
    func encoded() -> String {
        """
        .init(
            \"\(host)\"
            \(port > 0 ? ", \(port)" : "")
            \(`protocol` != nil ? ", \"\(`protocol`!)\"" : "")
            \(realm != nil ? ", realm: \"\(realm!)\"" : "")
            \(authenticationMethod.isEmpty ? "" : ", method: \"\(authenticationMethod)\"")
        )
        """
    }
}

struct Nav: Equatable {
    var navigationAction: NavAction
    var response: NavResponse?
    var redirects: [NavAction]
    var state: NavigationState
    var isCommitted: Bool
    var didReceiveAuthenticationChallenge: Bool
    var isCurrent: Bool

    enum IsCommitted {
        case committed
    }
    enum DidReceiveAuthenticationChallenge {
        case gotAuth
    }

    init(action navigationAction: NavAction, redirects: [NavAction] = [], _ state: NavigationState, resp response: NavResponse? = nil, _ isCommitted: IsCommitted? = nil, _ didReceiveAuthenticationChallenge: DidReceiveAuthenticationChallenge? = nil, isCurrent: Bool = true) {
        self.navigationAction = navigationAction
        self.state = state
        self.response = response
        self.isCommitted = isCommitted != nil
        self.didReceiveAuthenticationChallenge = didReceiveAuthenticationChallenge != nil
        self.redirects = redirects
        self.isCurrent = isCurrent
    }

    func encoded(_ context: EncodingContext) -> String {
        "Nav(action: \(navigationAction.navigationAction.encoded(context)), \(redirects.isEmpty ? "" : "redirects: [\(redirects.map { $0.navigationAction.encoded(context) }.joined(separator: ", "))], ")\(state.encoded(context))" +
        "\(response != nil ? ", resp: \(response!.response.encoded(context))" : "")" +
        "\(isCommitted ? ", .committed" : (didReceiveAuthenticationChallenge ? ", nil" : "")) \(didReceiveAuthenticationChallenge ? ", .gotAuth" : "")" +
        "\(isCurrent == false ? ", isCurrent: false" : "")" +
        ")"
    }
}
extension Nav: TestComparable {
    static func difference(between lhs: Nav, and rhs: Nav) -> String? {
        compare_tc("navigationAction", lhs.navigationAction, rhs.navigationAction)
        ?? compare("response", lhs.response?.response, rhs.response?.response)
        ?? compare("redirects", lhs.redirects, rhs.redirects)
        ?? compare("state", lhs.state, rhs.state)
        ?? compare("isCommitted", lhs.isCommitted, rhs.isCommitted)
        ?? compare("didReceiveAuthenticationChallenge", lhs.didReceiveAuthenticationChallenge, rhs.didReceiveAuthenticationChallenge)
        ?? compare("isCurrent", lhs.isCurrent, rhs.isCurrent)
    }
}

struct NavResponse: Equatable {
    var response: NavigationResponse
    static func == (lhs: NavResponse, rhs: NavResponse) -> Bool {
        NavigationResponse.difference(between: lhs.response, and: rhs.response) == nil
    }
    var url: URL {
        response.url
    }
}

extension NavigationState {

    static var expected: NavigationState {
        return .expected(nil)
    }

    func encoded(_ context: EncodingContext) -> String {
        switch self {
        case .expected(.none):
            return ".expected"
        case .expected(.some(let navigationType)):
            return ".expected(\(navigationType.encoded(context)))"
        case .started:
            return ".started"
        case .redirected(.server):
            return ".redirected(.server)"
        case .willPerformClientRedirect(delay: 0):
            return ".willPerformClientRedirect"
        case .willPerformClientRedirect(delay: let delay):
            return ".willPerformClientRedirect(delay: \(delay))"
        case .redirected(.client(delay: 0)):
            return ".redirected(.client)"
        case .redirected(.client(delay: let delay)):
            return ".redirected(.client(delay: \(Int(delay))))"
        case .redirected(.developer):
            return ".redirected(.developer)"
        case .responseReceived:
            return ".responseReceived"
        case .finished:
            return ".finished"
        case .failed(let error):
            return ".failed(WKError(\(error.encoded())))"
        case .navigationActionReceived:
            return ".navigationActionReceived"
        case .approved:
            return ".approved"
        }
    }
}

extension [String: String] {
    static var `default`: [String: String] {
        [
            "Server": "Swifter Unspecified",
            "Connection": "keep-alive"
        ]
    }
}
extension NavigationResponse: TestComparable {
    func encoded(_ context: EncodingContext) -> String {
        if context.navigationResponses.pointee.contains(where: { NavigationResponse.difference(between: $0, and: self) == nil }) {
            let idx = context.responderResponses.firstIndex(where: { $0 == NavResponse(response: self) })!
            return "resp(\(idx))"
        } else {
            context.navigationResponses.pointee.append(self)
        }

        if !canShowMIMEType || !isForMainFrame {
            return ".resp" + "\(response.encoded(context).dropping(suffix: ")"))\(isForMainFrame ? "" : ", .nonMain")\(canShowMIMEType ? "" : ", .cantShow"))".dropping(prefix: "urlresp")
        } else {
            return ".resp" + response.encoded(context).dropping(prefix: "urlresp")
        }
    }

    static func difference(between lhs: NavigationResponse, and rhs: NavigationResponse) -> String? {
        compare_tc("response", lhs.response, rhs.response)
        ?? compare("isForMainFrame", lhs.isForMainFrame, rhs.isForMainFrame)
        ?? compare("canShowMIMEType", lhs.canShowMIMEType, rhs.canShowMIMEType)
    }

}
extension NavResponse {
    enum IsNotForMainFrame {
        case nonMain
    }
    enum CannotShowMimeType {
        case cantShow
    }

    static func resp(_ response: URLResponse, _ isNotForMainFrame: IsNotForMainFrame? = nil, _ cantShowMIMEType: CannotShowMimeType? = nil) -> NavResponse {
        NavResponse(response: .init(response: response, isForMainFrame: isNotForMainFrame == nil, canShowMIMEType: cantShowMIMEType == nil, mainFrameNavigation: nil))
    }

    static func resp(_ url: URL, status: Int = 200, mime: String? = "text/html", _ length: Int = -1, _ encoding: String? = nil, headers: [String: String] = .default, _ isNotForMainFrame: IsNotForMainFrame? = nil, _ cantShowMIMEType: CannotShowMimeType? = nil) -> NavResponse {
        var headers = headers
        if length >= 0 {
            headers["Content-Length"] = String(length)
        }
        if let encoding {
            headers["Content-Encoding"] = encoding
        }
        let response = MockHTTPURLResponse(url: url, statusCode: status, mime: mime, httpVersion: nil, headerFields: headers)!
        return NavResponse(response: .init(response: response, isForMainFrame: isNotForMainFrame == nil, canShowMIMEType: cantShowMIMEType == nil, mainFrameNavigation: nil))
    }

    static func resp(_ url: URL, status: Int? = 200, mime: String? = "text/html", _ length: Int = -1, _ encoding: String? = nil, headers: [String: String]? = nil, _ isNotForMainFrame: IsNotForMainFrame? = nil) -> NavResponse {
        if let status {
            return .resp(url, status: status, mime: mime, length, encoding, headers: headers ?? .default, isNotForMainFrame)
        } else {
            assert(headers == nil)
            return NavResponse(response: .init(response: URLResponse(url: url, mimeType: mime, expectedContentLength: length, textEncodingName: encoding),
                                               isForMainFrame: isNotForMainFrame == nil, canShowMIMEType: true, mainFrameNavigation: nil))
        }
    }

}

extension TestsNavigationEvent.EitherResponseOrNavigation: TestComparable {
    static func difference(between lhs: Self, and rhs: Self) -> String? {
        switch (lhs, rhs) {
        case (.response(let resp1, let nav1), .response(let resp2, let nav2)):
            return compare_tc("", resp1.response, resp2.response) ?? compare_tc("navigation", nav1, nav2)
        case (.navigation(let lhs), .navigation(let rhs)):
            return compare_tc("", lhs, rhs)
        default:
            return compare("", lhs, rhs, using: ==)
        }
    }
}

extension URLResponse: TestComparable {

    static func difference(between lhs: URLResponse, and rhs: URLResponse) -> String? {
        compare("url", lhs.url ?? .empty, rhs.url ?? .empty) { $0.matches($1) }
        ?? compare("mimeType", lhs.mimeType, rhs.mimeType)
        ?? compare("expectedContentLength", lhs.expectedContentLength, rhs.expectedContentLength)
        ?? compare("textEncodingName", lhs.textEncodingName, rhs.textEncodingName)
        ?? compare("suggestedFilename", lhs.suggestedFilename, rhs.suggestedFilename)
        ?? compare("is HTTPURLResponse", lhs is HTTPURLResponse, rhs is HTTPURLResponse)
        ?? (lhs as? HTTPURLResponse).flatMap { lhs -> String? in
            guard let rhs = rhs as? HTTPURLResponse else { return nil }
            return HTTPURLResponse.diff(lhs, and: rhs)
        }
    }

}

private extension HTTPURLResponse {

    static func diff(_ lhs: HTTPURLResponse, and rhs: HTTPURLResponse) -> String? {
        compare("statusCode", lhs.statusCode, rhs.statusCode)
        ?? compare("allHeaderFields", lhs.allHeaderFields as NSDictionary, rhs.allHeaderFields as NSDictionary)
    }

}

class MockHTTPURLResponse: HTTPURLResponse, @unchecked Sendable {
    private let mime: String?
    override var mimeType: String? {
        mime ?? super.mimeType
    }
    override var suggestedFilename: String? {
        URLResponse(url: url!, mimeType: mimeType, expectedContentLength: Int(expectedContentLength), textEncodingName: textEncodingName).suggestedFilename ?? super.suggestedFilename
    }
    init?(url: URL, statusCode: Int, mime: String?, httpVersion: String? = nil, headerFields: [String: String]?) {
        self.mime = mime
        super.init(url: url, statusCode: statusCode, httpVersion: httpVersion, headerFields: headerFields)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension WKError {
    init(_ code: Int) {
        self.init(Code(rawValue: code)!)
    }
    func encoded() -> String {
        "\(self.code.rawValue)"
    }
}

private func urlConst(for url: URL, in urls: Any) -> String? {
    let m = Mirror(reflecting: urls)
    for child in m.children where (child.value as? URL)?.matches(url) == true {
        return "urls." + child.label!
    }
    if url.isEmpty {
        return ".empty"
    }
    return nil
}

private func dataConst(forLength length: Int64, in dataSource: Any) -> String {
    let m = Mirror(reflecting: dataSource)
    for child in m.children where (child.value as? Data)?.count == Int(length) {
        return "data." + child.label! + ".count"
    }
    return "Data const with length \(length) not found in \(dataSource)"
}

var defaultHeaders: [String: String] = {
    let webView = WKWebView()
    class DefaultHeadersRetreiverNavigationDelegate: NSObject, WKNavigationDelegate {
        var headers: [String: String]?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            self.headers = navigationAction.request.allHTTPHeaderFields
            decisionHandler(.cancel)
        }
    }

    let delegate = DefaultHeadersRetreiverNavigationDelegate()
    webView.navigationDelegate = delegate
    webView.load(URLRequest(url: URL(string: "https://duckduckgo.com")!))
    while delegate.headers == nil {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    return delegate.headers!
}()

extension [String: String] {

    static let allowsExtraKeysKey = "_allowsExtraKeysKey"

    var allowingExtraKeys: [String: String] {
        var result = self
        result[Self.allowsExtraKeysKey] = "1"
        return result
    }

    var allowsExtraKeys: Bool {
        self[Self.allowsExtraKeysKey] == "1"
    }

}

func req(_ string: String, _ headers: [String: String]? = defaultHeaders, cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy) -> URLRequest {
    req(URL(string: string)!, headers, cachePolicy: cachePolicy)
}
func req(_ url: URL, _ headers: [String: String]? = defaultHeaders, cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy) -> URLRequest {
    var req = URLRequest(url: url, cachePolicy: cachePolicy)
    req.allHTTPHeaderFields = headers
    return req
}

func urlresp(_ url: URL, mime: String? = "text/html", _ length: Int = -1, _ encoding: String? = nil) -> URLResponse {
    return URLResponse(url: url, mimeType: mime, expectedContentLength: length, textEncodingName: encoding)
}

extension URLResponse {
    func encoded(_ context: EncodingContext) -> String {
        var headers = ""
        let defaultHeaders = [String: String].default
        var headerFields = (self as? HTTPURLResponse)?.allHeaderFields as? [String: String] ?? [:]
        headerFields["Content-Length"] = nil
        if !(self is HTTPURLResponse) || headerFields == defaultHeaders {
            headers = ""
        } else if (self as? HTTPURLResponse)?.allHeaderFields != nil {
            if Set(headerFields.keys).intersection(defaultHeaders.keys).count == defaultHeaders.count {
                headers = ", headers: .default + " + headerFields.filter { $0.value != defaultHeaders[$0.key] }.encoded(context: context)
            } else {
                headers = ", headers: " + headerFields.encoded(context: context)
            }
        } else {
            headers = ", headers: nil"
        }

        return """
        urlresp(
            \(urlConst(for: self.url!, in: context.urls) ?? "\(self.url!) not registered in URLs"),
            \((self as? HTTPURLResponse)?.statusCode != 200 ? "status: " + ((self as? HTTPURLResponse).map { String($0.statusCode) } ?? "nil") + "," : "")
            \(mimeType != "text/html" ? "mime: \"\(mimeType ?? "nil")\"," : "")
            \(expectedContentLength != -1 ? "\(dataConst(forLength: expectedContentLength, in: context.dataSource))" + (textEncodingName != nil ? "," : "") : "")
            \(textEncodingName != nil ? "\"\(textEncodingName!)\"" : "")
            \(headers)
        """.replacingOccurrences(of: ", ,", with: ", ").trimmingWhitespace().dropping(suffix: ",") + ")"
    }
}

func compare<T>(_ name: String, _ lhs: T, _ rhs: T, using comparator: (T, T) -> Bool) -> String? {
    if comparator(lhs, rhs) { return nil }
    return (name.isEmpty ? "" : "\(name): ") + "`\(lhs)` not equal to `\(rhs)`"
}

func compare<T: TestComparable>(_ name: String, _ lhs: T, _ rhs: T) -> String? {
    if let diff = T.difference(between: lhs, and: rhs) {
        return (name.isEmpty ? "" : "\(name): ") + "\(diff)"
    }
    return nil
}
func compare_tc<T: TestComparable>(_ name: String, _ lhs: T, _ rhs: T) -> String? {
    compare(name, lhs, rhs)
}
func compare_tc<T: TestComparable>(_ name: String, _ lhs: T?, _ rhs: T?) -> String? {
    compare(name, lhs, rhs)
}
func compare<T: TestComparable>(_ name: String, _ lhs: T?, _ rhs: T?) -> String? {
    if case .none = lhs, case .none = rhs { return nil }
    guard let lhs, let rhs else {
        return (name.isEmpty ? "" : "\(name): ") + "`\(String(describing: lhs))` not equal to `\(String(describing: rhs))`"
    }
    return compare(name, lhs, rhs)
}

func compare<T: Equatable>(_ name: String, _ lhs: T, _ rhs: T) -> String? {
    compare(name, lhs, rhs, using: ==)
}

protocol TestComparable {
    static func difference(between lhs: Self, and rhs: Self) -> String?
}

extension NavigationAction: TestComparable {

    static func difference(between lhs: NavigationAction, and rhs: NavigationAction) -> String? {
        compare("navigationType", lhs.navigationType, rhs.navigationType)
        ?? compare_tc("sourceFrame", lhs.sourceFrame, rhs.sourceFrame)
        ?? compare_tc("targetFrame", lhs.targetFrame, rhs.targetFrame)
        ?? compare("shouldDownload", lhs.shouldDownload, rhs.shouldDownload)
        ?? compare_tc("request", lhs.request, rhs.request)
        ?? compare("redirectHistory", lhs.redirectHistory, rhs.redirectHistory)
        ?? {
#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
            compare("fromHistoryItemIdentity", lhs.fromHistoryItemIdentity, rhs.fromHistoryItemIdentity)
#else
            nil
#endif
        }()
    }

}
extension [NavigationAction]?: TestComparable {

    static func difference(between lhs: [NavigationAction]?, and rhs: [NavigationAction]?) -> String? {
        guard let lhs, let rhs else {
            if let lhs {
                return "\(lhs) not equal to <nil>"
            }
            if let rhs {
                return "<nil> not equal to \(rhs)"
            }
            return nil
        }
        for (i, element) in lhs.enumerated() {
            guard rhs.indices.contains(i) else {
                return "[\(i)]: \(element) not equal to <nil>"
            }
            if let diff = NavigationAction.difference(between: element, and: rhs[i]) {
                return "[\(i)]: \(diff)"
            }
        }
        if rhs.count > lhs.count {
            return "[\(lhs.count)]: <nil> not equal to \(rhs[lhs.count])"
        }
        return nil
    }

}

extension URLRequest: TestComparable {

    static func difference(between lhs: URLRequest, and rhs: URLRequest) -> String? {
        compare("url", lhs.url ?? .empty, rhs.url ?? .empty) { $0.matches($1) }
        ?? compare("httpMethod", lhs.httpMethod, rhs.httpMethod)
        ?? compare("allHTTPHeaderFields", Headers(lhs.allHTTPHeaderFields), Headers(rhs.allHTTPHeaderFields))
        ?? compare("cachePolicy", lhs.cachePolicy, rhs.cachePolicy)
        ?? compare("timeoutInterval", lhs.timeoutInterval, rhs.timeoutInterval)
    }

}

struct Headers: TestComparable {

    let dict: [String: String]

    init(_ dict: [String: String]?) {
        self.dict = dict ?? [:]
    }

    static func difference(between lhs: Headers, and rhs: Headers) -> String? {
        var result = ""
        let lhs = lhs.dict
        let rhs = rhs.dict
        for key in Set(lhs.keys).union(rhs.keys) where key != [String: String].allowsExtraKeysKey {
            let value1 = lhs[key]
            let value2 = rhs[key]
            if let diff = compare(key, value1, value2) {
                if value1 == nil && lhs.allowsExtraKeys { continue }
                if value2 == nil && rhs.allowsExtraKeys { continue }

                result += (result.isEmpty ? "" : ",\n") + diff
            }
        }
        return result.isEmpty ? nil : result
    }

}

extension FrameInfo: TestComparable {
    static func difference(between lhs: FrameInfo, and rhs: FrameInfo) -> String? {
        compare("webView", lhs.webView, rhs.webView)
        ?? compare("handle", lhs.handle, rhs.handle)
        ?? compare("url", lhs.url, rhs.url) { $0.matches($1) }
        ?? compare("securityOrigin", lhs.securityOrigin, rhs.securityOrigin)
    }
}

extension NavigationPreferences: TestComparable {
    enum JSDisabled {
        case jsDisabled
    }
    init(_ ua: String? = nil, _ contentMode: WKWebpagePreferences.ContentMode = .recommended, _ disableJs: JSDisabled? = nil) {
        self.init(userAgent: ua, contentMode: contentMode, javaScriptEnabled: disableJs == nil)
    }
    func encoded() -> String? {
        if userAgent == nil, contentMode == .recommended, javaScriptEnabled == true {
            return nil
        }
        return ".init(\(userAgent ?? "")\(contentMode == .recommended ? "" : ((userAgent == nil ? "" : ",") + (contentMode == .mobile ? ":mobile" : "desktop")))\(javaScriptEnabled == false ? ((userAgent != nil || contentMode != .recommended ? "," : "") + ".jsDisabled") : ""))"
    }

    static func difference(between lhs: NavigationPreferences, and rhs: NavigationPreferences) -> String? {
        if let diff = compare("userAgent", lhs.userAgent, rhs.userAgent)
            ?? compare("contentMode", lhs.contentMode, rhs.contentMode)
            ?? compare("javaScriptEnabled", lhs.javaScriptEnabled, rhs.javaScriptEnabled) {
            return diff
        }
#if _WEBPAGE_PREFS_CUSTOM_HEADERS_ENABLED
        return compare("customHeaders", lhs.customHeaders ?? [], rhs.customHeaders ?? [])
#else
        return nil
#endif
    }
}

extension [String: String] {
    func encoded(context: EncodingContext) -> String {
        if self.isEmpty { return "[:]" }
        var result = "["
        for (idx, item) in self.enumerated() {
            if idx > 0 {
                result.append(",\n")
            }
            var value = "\"\(item.value)\""
            if let url = URL(string: item.value), let const = urlConst(for: url, in: context.urls) {
                value = const + (item.value.hasSuffix("/") ? ".separatedString" : ".string")
            }
            result.append("\"\(item.key)\": \(value)")
        }
        result.append("]")
        return result
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        lhs.merging(rhs, uniquingKeysWith: { $1 })
    }
}

extension NavigationAction {
    enum UserInitiated {
        case userInitiated
    }
    enum ShouldDownload {
        case shouldDownload
    }

    func encoded(_ context: EncodingContext) -> String {

        if context.navigationActions.pointee[self.identifier] != nil {
            return "navAct(\(self.identifier))"
        } else {
            context.navigationActions.pointee[self.identifier] = .init(self)
        }

#if _IS_USER_INITIATED_ENABLED
        let isUserInitiated = self.isUserInitiated ? ".userInitiated," : ""
#else
        let isUserInitiated = ""
#endif
        var headers = ""
        if request.allHTTPHeaderFields == defaultHeaders {
            headers = ""
        } else if let headerFields = request.allHTTPHeaderFields {
            if Set(headerFields.keys).intersection(defaultHeaders.keys).count == defaultHeaders.count {
                headers = ", defaultHeaders + " + headerFields.filter { $0.value != defaultHeaders[$0.key] }.encoded(context: context)
            } else {
                headers = ", " + headerFields.encoded(context: context)
            }
        } else {
            headers = ", nil"
        }
        switch request.cachePolicy {
        case .useProtocolCachePolicy: break
        case .reloadIgnoringLocalCacheData:
            headers += ", cachePolicy: .reloadIgnoringLocalCacheData"
        case .reloadIgnoringLocalAndRemoteCacheData:
            headers += ", cachePolicy: .reloadIgnoringLocalAndRemoteCacheData"
        case .returnCacheDataElseLoad:
            headers += ", cachePolicy: .returnCacheDataElseLoad"
        case .returnCacheDataDontLoad:
            headers += ", cachePolicy: .returnCacheDataDontLoad"
        case .reloadRevalidatingCacheData:
            headers += ", cachePolicy: .reloadRevalidatingCacheData"
        @unknown default:
            fatalError()
        }
#if _FRAME_HANDLE_ENABLED
        let sourceFrameEnc = targetFrame == sourceFrame  ? "" : "targ: " + (targetFrame?.encoded(context) ?? "nil") + ","
#else
        let sourceFrameEnc = " ,"
#endif
#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
        let fromHistoryItemIdentityEnc = fromHistoryItemIdentity != nil ? "from: " + fromHistoryItemIdentity!.encoded(context) + "," : ""
#else
        let fromHistoryItemIdentityEnc = " ,"
#endif
        return """
        NavAction(
            req(\(urlConst(for: url, in: context.urls) ?? "\(url) not registered in URLs")\(headers)),
            \(navigationType.encoded(context)),
            \(fromHistoryItemIdentityEnc)
            \(redirectHistory != nil ? "redirects: [\(redirectHistory!.map { $0.encoded(context) }.joined(separator: ", "))]," : "")
            \(isUserInitiated)
            src: \(sourceFrame.encoded(context)),
            \(sourceFrameEnc)
            \(shouldDownload ? ".shouldDownload," : "")
        """.trimmingWhitespace().dropping(suffix: ",") +
        ")"
    }
}

extension FrameInfo {
    func encoded(_ context: EncodingContext) -> String {
        let secOrigin = (securityOrigin == url.securityOrigin ? "" : "secOrigin: " + securityOrigin.encoded(context))
        if self.isMainFrame {
            return "main(" + (url.isEmpty ? "" : (urlConst(for: url, in: context.urls) ?? "!URL(\"\(url.absoluteString)\" not found in constants)") + (secOrigin.isEmpty ? "" : ", "))  + secOrigin + ")"
        } else {
#if _FRAME_HANDLE_ENABLED
            let frameID = handle.frameID
#else
            let frameID = ""
#endif
            return "frame(\(frameID), \(urlConst(for: url, in: context.urls)!)\((secOrigin.isEmpty ? "" : ", ") + secOrigin))"
        }
    }
}

extension SecurityOrigin: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String
    public init(stringLiteral: String) {
        self = URL(string: stringLiteral)!.securityOrigin
    }

    func encoded(_ context: EncodingContext) -> String {
        let url = URL(string: self.protocol + "://" + self.host + (port > 0 ? ":\(port)" : ""))!
        if let const = urlConst(for: url, in: context.urls) {
            return const + ".securityOrigin"
        } else {
            return "\"\(url.absoluteString)\""
        }
    }
}

extension NavigationType {
    enum MiddleClick {
        case middleClick
    }

#if os(macOS)
    static var link = NavigationType.linkActivated(isMiddleClick: false)
    static func link(_ middleClick: MiddleClick) -> NavigationType { .linkActivated(isMiddleClick: true) }
#endif

    static var form = NavigationType.formSubmitted
    static var formRe = NavigationType.formResubmitted
#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
    static func backForw(_ dist: Int) -> NavigationType { .backForward(distance: dist) }
#else
    static func backForw(_ dist: Int) -> NavigationType { .backForward }
#endif
    static var restore = NavigationType.sessionRestoration

    func encoded(_ context: EncodingContext) -> String {
        switch self {
#if os(macOS)
        case .linkActivated(isMiddleClick: let isMiddleClick):
            return isMiddleClick ? ".link(.middleClick)" : ".link"
#else
        case .linkActivated:
            return ".linkActivated"
#endif
        case .formSubmitted:
            return ".form"
        case .formResubmitted:
            return ".formRe"
#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
        case .backForward(distance: let distance):
            return ".backForw(\(distance))"
#else
        case .backForward:
            return ".backForw"
#endif
        case .reload:
            return ".reload"
        case .redirect(.server):
            return ".redirect(.server)"
        case .redirect(.client(delay: let delay)) where delay != 0:
            return ".redirect(.client(delay: \(delay)))"
        case .redirect(.client):
            return ".redirect(.client)"
        case .redirect(.developer):
            return ".redirect(.developer)"
        case .sessionRestoration:
            return ".restore"
#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
        case .sameDocumentNavigation(let navigationType):
            return ".sameDocumentNavigation(.\(navigationType.debugDescription))"
#else
        case .sameDocumentNavigation:
            return ".sameDocumentNavigation"
#endif
        case .other:
            return ".other"
        case .custom(let name):
            return "<##custom: \(name.rawValue)>"
        case .alternateHtmlLoad:
            return ".alternateHtmlLoad"
        }
    }
}

extension RedirectType {
    static var client = RedirectType.client(delay: 0)
    static func client(_ delay: Int) -> RedirectType { RedirectType.client(delay: TimeInterval(delay) / 1000) }
    func encoded() -> String {
        switch self {
        case .client(delay: let delay) where delay == 0:
            return ".client"
        case .client(delay: let delay):
            return ".client(delay: \(Int(delay)))"
        case .server:
            return ".server"
        case .developer:
            return ".developer"
        }
    }
}
extension HistoryItemIdentity {
    func encoded(_ context: EncodingContext) -> String {
        let navigationActionIdx = context.history.keys.sorted().first(where: { context.history[$0]! == self })!
        return "history[\(navigationActionIdx)]"
    }
}
extension WKWebView {
    func getDistance(from historyItemIdentity: HistoryItemIdentity) -> Int? {
        if backForwardList.currentItem.map(HistoryItemIdentity.init) == historyItemIdentity {
            return 0
        }
        if let forwardIndex = backForwardList.forwardList.firstIndex(where: { $0.identity == historyItemIdentity }) {
            return forwardIndex + 1
        }
        let backList = backForwardList.backList
        if let backIndex = backList.lastIndex(where: { $0.identity == historyItemIdentity }) {
            return -(backList.count - backIndex)  // going forward from item in _reveresed_ back list to current
        }
        return nil
    }
}

extension TestsNavigationEvent {
    func encoded() -> String {
        let m = Mirror(reflecting: self)
        let label = m.children.first!.label!

        let value = m.children.first!.value
        let mval = Mirror(reflecting: value)

        var result = ".\(label)("
        if mval.children.first?.label == "0" {
            for (idx, child) in mval.children.enumerated() {
                if idx > 0 {
                    result.append(", ")
                }
                result.append((child.value as? CustomDebugStringConvertible)?.debugDescription ?? "\(child.value)")
            }
        } else {
            result.append((value as? CustomDebugStringConvertible)?.debugDescription ?? "\(value)")
        }
        result.append(")")

        return result
    }
}
extension Array where Element == TestsNavigationEvent {

    func encoded(with urls: Any, webView: WKWebView, dataSource: Any, history: [UInt64: HistoryItemIdentity], responderNavigationResponses: [NavResponse]) -> String {
        var navigationActions = [UInt64: NavAction]()
        var navigationResponses = [NavigationResponse]()
        var result = "[\n"
        for (idx, item) in self.enumerated() {
            if idx > 0 {
                result.append(",\n")
            }
            withUnsafeMutablePointer(to: &navigationResponses) { navigationResponsesPtr in
                withUnsafeMutablePointer(to: &navigationActions) { navigationActionsPtr in
                    result.append("  " + item.encoded((urls: urls, webView: webView, dataSource: dataSource, navigationActions: navigationActionsPtr, navigationResponsesPtr, responderNavigationResponses, history: history)))
                }
            }
        }
        result.append("\n]")

        return result
    }

}

class NavigationDelegateProxy: NSObject, WKNavigationDelegate {
    var delegate: DistributedNavigationDelegate

    enum FinishEventsDispatchTime {
        case instant
        case beforeWillStartNavigationAction
        case afterWillStartNavigationAction
        case afterDidStartNavigationAction
    }
    var finishEventsDispatchTime: FinishEventsDispatchTime = .instant
    var didFailEventsDispatchTime: FinishEventsDispatchTime = .instant

    var enableWillPerformClientRedirect: Bool = true

    init(delegate: DistributedNavigationDelegate) {
        self.delegate = delegate
    }

    // forward delegate calls to DistributedNavigationDelegate
    override func responds(to selector: Selector!) -> Bool {
        delegate.responds(to: selector)
    }
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        delegate
    }

    private var finishWorkItem: DispatchWorkItem? {
        willSet {
            guard let finishWorkItem, !finishWorkItem.isCancelled else { return }
            finishWorkItem.perform()
        }
    }
    private var didFailWorkItem: DispatchWorkItem? {
        willSet {
            guard let didFailWorkItem, !didFailWorkItem.isCancelled else { return }
            didFailWorkItem.perform()
        }
    }

    var nextNavigationActionShouldBeUserInitiated: Bool = false

    @MainActor
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        if nextNavigationActionShouldBeUserInitiated {
            navigationAction._isUserInitiated = true
            nextNavigationActionShouldBeUserInitiated = false
        }
        delegate.webView(webView, decidePolicyFor: navigationAction, preferences: preferences) { [self] policy, preferences in
            decisionHandler(policy, preferences)
            switch self.finishEventsDispatchTime {
            case .instant, .afterDidStartNavigationAction: break
            case .beforeWillStartNavigationAction:
                self.finishWorkItem = nil // trigger if set after decidePolicyFor callback
            case .afterWillStartNavigationAction:
                navigationAction.onDeinit {
                    self.finishWorkItem = nil
                }
            }
            switch self.didFailEventsDispatchTime {
            case .instant, .afterDidStartNavigationAction: break
            case .beforeWillStartNavigationAction:
                self.didFailWorkItem = nil // trigger if set after decidePolicyFor callback
            case .afterWillStartNavigationAction:
                navigationAction.onDeinit {
                    self.didFailWorkItem = nil
                }
            }
        }
    }

    @MainActor
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        delegate.webView(webView, didStartProvisionalNavigation: navigation)
        if case .afterDidStartNavigationAction = self.finishEventsDispatchTime {
            self.finishWorkItem = nil
        }
        if case .afterDidStartNavigationAction = self.didFailEventsDispatchTime {
            self.didFailWorkItem = nil
        }
    }

    var replaceDidFinishWithDidFailWithError: WKError?
    @MainActor
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let error = replaceDidFinishWithDidFailWithError {
            self.replaceDidFinishWithDidFailWithError = nil
            self.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
            return
        }

        guard finishEventsDispatchTime != .instant else {
            delegate.webView(webView, didFinish: navigation)
            return
        }
        finishWorkItem = DispatchWorkItem { [delegate, weak self] in
            self?.finishWorkItem?.cancel()
            delegate.webView(webView, didFinish: navigation)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: finishWorkItem!)
    }

    @MainActor
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard didFailEventsDispatchTime != .instant else {
            delegate.webView(webView, didFail: navigation, withError: error)
            return
        }
        didFailWorkItem = DispatchWorkItem { [delegate, weak self] in
            self?.didFailWorkItem?.cancel()
            delegate.webView(webView, didFail: navigation, withError: error)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: didFailWorkItem!)
    }

    @MainActor
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard didFailEventsDispatchTime != .instant else {
            delegate.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
            return
        }
        didFailWorkItem = DispatchWorkItem { [delegate, weak self] in
            self?.didFailWorkItem?.cancel()
            delegate.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: didFailWorkItem!)
    }

    @MainActor
    @objc(_webView:willPerformClientRedirectToURL:delay:)
    func webView(_ webView: WKWebView, willPerformClientRedirectTo url: URL, delay: TimeInterval) {
        guard enableWillPerformClientRedirect else { return }
        delegate.webView(webView, willPerformClientRedirectTo: url, delay: delay)
    }

}

private extension WKNavigationAction {
    private static let isUserInitiatedKey = UnsafeRawPointer(bitPattern: "isUserInitiatedKey".hashValue)!

    @nonobjc var _isUserInitiated: Bool {
        get {
#if _IS_USER_INITIATED_ENABLED
            return (objc_getAssociatedObject(self, Self.isUserInitiatedKey) as? Bool) ?? self.value(forKey: "_isUserInitiated") as! Bool
#else
            return false
#endif
        }
        set {
            objc_setAssociatedObject(self, Self.isUserInitiatedKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    @objc var isUserInitiated: Bool {
        _isUserInitiated
    }
}

extension Data {

    static let sessionRestorationMagic = Data([0x00, 0x00, 0x00, 0x02])

    var plist: [String: Any] {
        var data = self
        if data.prefix(through: Self.sessionRestorationMagic.count - 1) == Self.sessionRestorationMagic {
            data.removeFirst(Self.sessionRestorationMagic.count)
        }
        return try! PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
    }

}

extension [String: Any] {

    var plist: Data {
        try! PropertyListSerialization.data(fromPropertyList: self, format: .xml, options: 0)
    }
    var interactionStateData: Data {
        Data.sessionRestorationMagic + self.plist
    }

    subscript<T>(_ key: String, as _: T.Type) -> T? {
        get {
            self[key] as! T?
        }
        _modify {
            var value = withUnsafeMutablePointer(to: &self[key]) { ptr in
                defer {
                    ptr.pointee = nil
                }
                return ptr.pointee as! T?
            }
            yield &value
            self[key] = value
        }
    }

}

extension URL {
    var string: String {
        self.absoluteString
    }
    var separatedString: String {
        self.absoluteString.hasSuffix("/") ? self.absoluteString : self.absoluteString + "/"
    }
}

final class CustomCallbacksHandler: NSObject, NavigationResponder {

    var willPerformClientRedirectHandler: ((URL, TimeInterval) -> Void)?
    func webViewWillPerformClientRedirect(to url: URL, withDelay delay: TimeInterval) {
        self.willPerformClientRedirectHandler?(url, delay)
    }

    var didFinishLoadingFrame: ((URLRequest, WKFrameInfo) -> Void)?
    func didFinishLoad(with request: URLRequest, in frame: WKFrameInfo) {
        self.didFinishLoadingFrame?(request, frame)
    }

    var didFailProvisionalLoadInFrame: ((URLRequest, WKFrameInfo, Error) -> Void)?
    func didFailProvisionalLoad(with request: URLRequest, in frame: WKFrameInfo, with error: Error) {
        self.didFailProvisionalLoadInFrame?(request, frame, error)
    }

    var didSameDocumentNavigation: (@MainActor (Navigation, WKSameDocumentNavigationType) -> Void)?
    func navigation(_ navigation: Navigation, didSameDocumentNavigationOf navigationType: WKSameDocumentNavigationType) {
        self.didSameDocumentNavigation?(navigation, navigationType)
    }

}

class WKUIDelegateMock: NSObject, WKUIDelegate {
    var createWebViewWithConfig: ((WKWebViewConfiguration, WKNavigationAction, WKWindowFeatures) -> WKWebView?)?
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        createWebViewWithConfig?(configuration, navigationAction, windowFeatures)
    }
}

extension URLResponse {
    static func response(for request: URLRequest, mimeType: String? = "text/html", expectedLength: Int = 0, encoding: String? = nil) -> URLResponse {
        return URLResponse(url: request.url!, mimeType: mimeType, expectedContentLength: expectedLength, textEncodingName: encoding)
    }
}

#if !_FRAME_HANDLE_ENABLED

struct FrameHandle: Equatable {
    init(rawValue: UInt64? = nil) {}
}

extension WKWebView {
    var mainFrameHandle: FrameHandle { FrameHandle() }
}

extension FrameInfo {
    var handle: FrameHandle { FrameHandle() }

    init(webView: WKWebView?, handle: FrameHandle?, isMainFrame: Bool, url: URL, securityOrigin: SecurityOrigin) {
        self.init(webView: webView, isMainFrame: isMainFrame, url: url, securityOrigin: securityOrigin)
    }
}

#endif

// swiftlint:enable cyclomatic_complexity
// swiftlint:enable implicit_getter
