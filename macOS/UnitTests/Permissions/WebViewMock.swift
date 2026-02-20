//
//  WebViewMock.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import CommonObjCExtensions
import Foundation
import Navigation
import WebKit

@testable import DuckDuckGo_Privacy_Browser

@objc protocol WebViewPermissionsDelegate: WKUIDelegate {
    @objc(_webView:checkUserMediaPermissionForURL:mainFrameURL:frameIdentifier:decisionHandler:)
    func webView(_ webView: WKWebView,
                 checkUserMediaPermissionFor url: URL,
                 mainFrameURL: URL,
                 frameIdentifier frame: UInt,
                 decisionHandler: @escaping (String, Bool) -> Void)

    @objc(webView:requestMediaCapturePermissionForOrigin:initiatedByFrame:type:decisionHandler:)
    @available(macOS 12.0, *)
    optional func webView(_ webView: WKWebView,
                          requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                          initiatedByFrame frame: WKFrameInfo,
                          type: WKMediaCaptureType,
                          decisionHandler: @escaping (WKPermissionDecision) -> Void)

    @objc(_webView:requestUserMediaAuthorizationForDevices:url:mainFrameURL:decisionHandler:)
    func webView(_ webView: WKWebView,
                 requestUserMediaAuthorizationFor devices: _WKCaptureDevices,
                 url: URL,
                 mainFrameURL: URL,
                 decisionHandler: @escaping (Bool) -> Void)

    @objc(_webView:mediaCaptureStateDidChange:)
    func webView(_ webView: WKWebView, mediaCaptureStateDidChange state: _WKMediaCaptureStateDeprecated)

    @objc(_webView:requestGeolocationPermissionForFrame:decisionHandler:)
    func webView(_ webView: WKWebView, requestGeolocationPermissionFor frame: WKFrameInfo, decisionHandler: @escaping (Bool) -> Void)

    @objc(_webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:)
    @available(macOS 12, *)
    func webView(_ webView: WKWebView,
                 requestGeolocationPermissionFor origin: WKSecurityOrigin,
                 initiatedBy frame: WKFrameInfo,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void)

}

final class WebViewMock: WKWebView {

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        _=Self.swizzleCaptureStateHandlersOnce
        super.init(frame: frame, configuration: configuration)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var urlValue: URL?
    override var url: URL? {
        urlValue
    }

    private var microphoneStateValue: Int = 0
    @available(macOS 12.0, *)
    override var microphoneCaptureState: WKMediaCaptureState {
        get {
            WKMediaCaptureState(rawValue: microphoneStateValue)!
        }
        set {
            willChangeValue(for: \.microphoneCaptureState)
            microphoneStateValue = newValue.rawValue
            didChangeValue(for: \.microphoneCaptureState)
        }
    }

    private var cameraStateValue: Int = 0
    @available(macOS 12.0, *)
    override var cameraCaptureState: WKMediaCaptureState {
        get {
            WKMediaCaptureState(rawValue: cameraStateValue)!
        }
        set {
            willChangeValue(for: \.cameraCaptureState)
            cameraStateValue = newValue.rawValue
            didChangeValue(for: \.cameraCaptureState)
        }
    }

    var setCameraCaptureStateHandler: ((Bool?) -> Void)?
    var setMicCaptureStateHandler: ((Bool?) -> Void)?

    var mediaCaptureState: _WKMediaCaptureStateDeprecated = [] {
        didSet {
            (self.uiDelegate as? WebViewPermissionsDelegate)!
                .webView(self, mediaCaptureStateDidChange: mediaCaptureState)
        }
    }
    override var _mediaCaptureState: _WKMediaCaptureStateDeprecated {
        mediaCaptureState
    }

    var stopMediaCaptureHandler: (() -> Void)?
    override func _stopMediaCapture() {
        mediaCaptureState = []
        stopMediaCaptureHandler?()
    }

    var mediaMutedStateValue: _WKMediaMutedState = []
    var setPageMutedHandler: ((_WKMediaMutedState) -> Void)?
    override var mediaMutedState: _WKMediaMutedState {
        get {
            mediaMutedStateValue
        }
        set {
            mediaMutedStateValue = newValue
            setPageMutedHandler?(newValue)
        }
    }

    private static let swizzleCaptureStateHandlersOnce: Void = {
        guard #available(macOS 12.0, *) else { return }

        let originalSetCameraCaptureState = class_getInstanceMethod(WKWebView.self, #selector(WKWebView.setCameraCaptureState))!
        let swizzledSetCameraCaptureState = class_getInstanceMethod(WKWebView.self, #selector(WKWebView.swizzled_setCameraCaptureState))!
        method_exchangeImplementations(originalSetCameraCaptureState, swizzledSetCameraCaptureState)

        let originalSetMicrophoneCaptureState = class_getInstanceMethod(WKWebView.self, #selector(WKWebView.setMicrophoneCaptureState))!
        let swizzledSetMicrophoneCaptureState = class_getInstanceMethod(WKWebView.self, #selector(WKWebView.swizzled_setMicrophoneCaptureState))!
        method_exchangeImplementations(originalSetMicrophoneCaptureState, swizzledSetMicrophoneCaptureState)
    }()

}

extension WKWebView {

    @available(macOS 12.0, *)
    @objc dynamic func swizzled_setCameraCaptureState(_ state: WKMediaCaptureState, completionHandler: (() -> Void)?) {
        guard let this = self as? WebViewMock, let setCameraCaptureStateHandler = this.setCameraCaptureStateHandler else {
            self.swizzled_setCameraCaptureState(state, completionHandler: completionHandler) // call original
            return
        }
        this.cameraCaptureState = state

        switch state {
        case .none: setCameraCaptureStateHandler(.none)
        case .active: setCameraCaptureStateHandler(true)
        case .muted: setCameraCaptureStateHandler(false)
        @unknown default: fatalError()
        }
    }

    @available(macOS 12.0, *)
    @objc dynamic func swizzled_setMicrophoneCaptureState(_ state: WKMediaCaptureState, completionHandler: (() -> Void)?) {
        guard let this = self as? WebViewMock, let setMicCaptureStateHandler = this.setMicCaptureStateHandler else {
            self.swizzled_setMicrophoneCaptureState(state, completionHandler: completionHandler) // call original
            return
        }
        this.microphoneCaptureState = state
        switch state {
        case .none: setMicCaptureStateHandler(.none)
        case .active: setMicCaptureStateHandler(true)
        case .muted: setMicCaptureStateHandler(false)
        @unknown default: fatalError()
        }
    }

}

@objc final class WKSecurityOriginMock: WKSecurityOrigin {
    var _protocol: String!
    override var `protocol`: String { _protocol }
    var _host: String!
    override var host: String { _host }
    var _port: Int!
    override var port: Int { _port }

    internal func setURL(_ url: URL) {
        self._protocol = url.scheme ?? ""
        self._host = url.host ?? ""
        self._port = url.port ?? url.navigationalScheme?.defaultPort ?? 0
    }

    class func new(url: URL) -> WKSecurityOriginMock {
        let mock = (self.perform(NSSelectorFromString("alloc")).takeUnretainedValue() as? WKSecurityOriginMock)!
        mock.setURL(url)
        return mock
    }

}

final class WKFrameInfoMock: NSObject {
    @objc var isMainFrame: Bool
    @objc var request: URLRequest!
    @objc var securityOrigin: WKSecurityOrigin!
    @objc weak var webView: WKWebView?

    fileprivate var frameInfo: WKFrameInfo {
        withUnsafePointer(to: self) { $0.withMemoryRebound(to: WKFrameInfo.self, capacity: 1) { $0 } }.pointee
    }

    @objc var _handle: UnsafeMutableRawPointer? {
        guard let webView else { return nil }
        let selector = NSSelectorFromString("_mainFrame")
        let method = class_getInstanceMethod(WKWebView.self, selector)!
        let imp = method_getImplementation(method)
        typealias GetHandleType = @convention(c) (WKWebView, ObjectiveC.Selector) -> UnsafeMutableRawPointer?
        let getHandle = unsafeBitCast(imp, to: GetHandleType.self)
        return getHandle(webView, selector)
    }
    override func value(forKey key: String) -> Any? {
        if key == "handle" {
            if let _handle {
                return _handle
            }
            return FrameHandle(rawValue: (isMainFrame ? 4 /*.fallbackMainFrameHandle*/ : 9 /*.fallbackNonMainFrameHandle*/) as UInt64)
        }
        return super.value(forKey: key)
    }

    init(webView: WKWebView?, securityOrigin: WKSecurityOrigin, request: URLRequest, isMainFrame: Bool) {
        self.webView = webView
        self.securityOrigin = securityOrigin
        self.request = request
        self.isMainFrame = isMainFrame
    }

}

extension WKFrameInfo {
    static func mock(for webView: WKWebView?, isMain: Bool = true, securityOrigin: WKSecurityOrigin? = nil, request: URLRequest? = nil) -> WKFrameInfo {
        let url = request?.url ?? webView?.url ?? .empty
        return WKFrameInfoMock(webView: webView, securityOrigin: securityOrigin ?? WKSecurityOriginMock.new(url: url), request: request ?? URLRequest(url: .empty), isMainFrame: isMain).frameInfo
    }

    private static let webViewKey = UnsafeRawPointer(bitPattern: "webViewKey".hashValue)!

    static func mock(url: URL? = nil) -> WKFrameInfo {
        let webView = WKWebView()
        let frameInfo = WKFrameInfo.mock(
            for: webView,
            isMain: true,
            securityOrigin: WKSecurityOriginMock.new(url: url ?? .empty),
            request: URLRequest(url: url ?? .empty)
        )
        // keep the WebView alive
        objc_setAssociatedObject(frameInfo, Self.webViewKey, webView, .OBJC_ASSOCIATION_RETAIN)
        return frameInfo
    }
}
