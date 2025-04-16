//
//  ClosureNavigationResponder.swift
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

import Foundation
import WebKit

@MainActor
public struct ClosureNavigationResponder: NavigationResponder {

    let decidePolicy: ((_ navigationAction: NavigationAction, _ preferences: inout NavigationPreferences) async -> NavigationActionPolicy?)?
    public func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        await self.decidePolicy?(navigationAction, &preferences)
    }

    let didCancelNavigationAction: ((_ navigationAction: NavigationAction, _ expectedNavigations: [ExpectedNavigation]?) -> Void)?
    public func didCancelNavigationAction(_ navigationAction: NavigationAction, withRedirectNavigations expectedNavigations: [ExpectedNavigation]?) {
        didCancelNavigationAction?(navigationAction, expectedNavigations)
    }

    let willStart: ((_ navigation: Navigation) -> Void)?
    public func willStart(_ navigation: Navigation) {
        willStart?(navigation)
    }
    let didStart: ((_ navigation: Navigation) -> Void)?
    public func didStart(_ navigation: Navigation) {
        didStart?(navigation)
    }

    let authenticationChallenge: ((_ authenticationChallenge: URLAuthenticationChallenge, Navigation?) async -> AuthChallengeDisposition?)?
    public func didReceive(_ authenticationChallenge: URLAuthenticationChallenge, for navigation: Navigation?) async -> AuthChallengeDisposition? {
        await self.authenticationChallenge?(authenticationChallenge, navigation)
    }

    let redirected: ((_ navigationAction: NavigationAction, Navigation) -> Void)?
    public func didReceiveRedirect(_ navigationAction: NavigationAction, for navigation: Navigation) {
        redirected?(navigationAction, navigation)
    }

    let navigationResponse: ((NavigationResponse) async -> NavigationResponsePolicy?)?
    public func decidePolicy(for navigationResponse: NavigationResponse) async -> NavigationResponsePolicy? {
        await self.navigationResponse?(navigationResponse)
    }

    let didCommit: ((Navigation) -> Void)?
    public func didCommit(_ navigation: Navigation) {
        didCommit?(navigation)
    }

    let navigationDidFinish: ((Navigation) -> Void)?
    public func navigationDidFinish(_ navigation: Navigation) {
        navigationDidFinish?(navigation)
    }

    let navigationDidFail: ((Navigation, WKError) -> Void)?
    public func navigation(_ navigation: Navigation, didFailWith error: WKError) {
        navigationDidFail?(navigation, error)
    }

    let navigationActionWillBecomeDownload: ((NavigationAction, WKWebView) -> Void)?
    public func navigationAction(_ navigationAction: NavigationAction, willBecomeDownloadIn webView: WKWebView) {
        navigationActionWillBecomeDownload?(navigationAction, webView)
    }
    let navigationActionDidBecomeDownload: ((NavigationAction, WebKitDownload) -> Void)?
    public func navigationAction(_ navigationAction: NavigationAction, didBecome download: WebKitDownload) {
        navigationActionDidBecomeDownload?(navigationAction, download)
    }

    let navigationResponseWillBecomeDownload: ((NavigationResponse, WKWebView) -> Void)?
    public func navigationResponse(_ navigationResponse: NavigationResponse, willBecomeDownloadIn webView: WKWebView) {
        navigationResponseWillBecomeDownload?(navigationResponse, webView)
    }
    let navigationResponseDidBecomeDownload: ((NavigationResponse, WebKitDownload) -> Void)?
    public func navigationResponse(_ navigationResponse: NavigationResponse, didBecome download: WebKitDownload) {
        navigationResponseDidBecomeDownload?(navigationResponse, download)
    }

    let webContentProcessDidTerminate: ((WKProcessTerminationReason?) -> Void)?
    public func webContentProcessDidTerminate(with reason: WKProcessTerminationReason?) {
        webContentProcessDidTerminate?(reason)
    }

    public init(decidePolicy: ((_: NavigationAction, _: inout NavigationPreferences) async -> NavigationActionPolicy?)? = nil,
                didCancel: ((_ navigationAction: NavigationAction, _ expectedNavigations: [ExpectedNavigation]?) -> Void)? = nil,
                willStart: ((_: Navigation) -> Void)? = nil,
                didStart: ((_: Navigation) -> Void)? = nil,
                authenticationChallenge: ((_: URLAuthenticationChallenge, Navigation?) async -> AuthChallengeDisposition?)? = nil,
                redirected: ((_: NavigationAction, Navigation) -> Void)? = nil,
                navigationResponse: ((NavigationResponse) async -> NavigationResponsePolicy?)? = nil,
                didCommit: ((Navigation) -> Void)? = nil,
                navigationDidFinish: ((Navigation) -> Void)? = nil,
                navigationDidFail: ((Navigation, WKError) -> Void)? = nil,
                navigationActionWillBecomeDownload: ((NavigationAction, WKWebView) -> Void)? = nil,
                navigationActionDidBecomeDownload: ((NavigationAction, WebKitDownload) -> Void)? = nil,
                navigationResponseWillBecomeDownload: ((NavigationResponse, WKWebView) -> Void)? = nil,
                navigationResponseDidBecomeDownload: ((NavigationResponse, WebKitDownload) -> Void)? = nil,
                webContentProcessDidTerminate: ((WKProcessTerminationReason?) -> Void)? = nil) {
        self.decidePolicy = decidePolicy
        self.didCancelNavigationAction = didCancel
        self.willStart = willStart
        self.didStart = didStart
        self.authenticationChallenge = authenticationChallenge
        self.redirected = redirected
        self.navigationResponse = navigationResponse
        self.didCommit = didCommit
        self.navigationDidFinish = navigationDidFinish
        self.navigationDidFail = navigationDidFail
        self.navigationActionWillBecomeDownload = navigationActionWillBecomeDownload
        self.navigationActionDidBecomeDownload = navigationActionDidBecomeDownload
        self.navigationResponseWillBecomeDownload = navigationResponseWillBecomeDownload
        self.navigationResponseDidBecomeDownload = navigationResponseDidBecomeDownload
        self.webContentProcessDidTerminate = webContentProcessDidTerminate
    }

}
