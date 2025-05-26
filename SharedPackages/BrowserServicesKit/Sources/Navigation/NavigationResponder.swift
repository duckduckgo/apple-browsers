//
//  NavigationResponder.swift
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

import Foundation
import WebKit

public protocol NavigationResponder {

    // MARK: Decision making

    /// Decides whether to allow or cancel a navigation
    /// Navigation Responders are queried in the provided order until any of them returns a NavigationActionPolicy decision
    /// Responder Chain proceeds querying a next Responder when `.next` policy decision is returned
    /// Modify `preferences` argument to set User Agent, Content Mode and disable javaScript
    @MainActor
    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy?

    /// Called when NavigationAction did not turn into a Navigation (received .cancel or .redirect)
    /// won‘t be called for cancelled server-redirect NavigationActions, `navigationDidFail` will be called instead
    /// won‘t be called for NavigationAction turned into downloads, `navigationAction(_:willBecomeDownloadIn:)` will be called instead
    @MainActor
    func didCancelNavigationAction(_ navigationAction: NavigationAction, withRedirectNavigations expectedNavigations: [ExpectedNavigation]?)

    // MARK: Navigation

    /// Called only for Main Frame Navigation Actions when all of the Responders returned `.next` or one of the Responders returned `.allow`  for `decidePolicy(for:navigationAction)` query
    @MainActor
    func willStart(_ navigation: Navigation)
    /// Called for `webView:didStartNavigation:` event _except_ for the navigations that were redirected
    /// May be called without preceding `decidePolicy(for:navigationAction)` for Session Restoration navigations
    @MainActor
    func didStart(_ navigation: Navigation)

    /// Invoked when the web view needs to respond to an authentication challenge.
    @MainActor
    func didReceive(_ authenticationChallenge: URLAuthenticationChallenge, for navigation: Navigation?) async -> AuthChallengeDisposition?

    /// Invoked when Redirect (either server or client) received for a Navigation
    @MainActor
    func didReceiveRedirect(_ navigationAction: NavigationAction, for navigation: Navigation)

    /// Happens after server redirects and completing authenticationChallenge
    /// Navigation Responders are queried in the provided order until any of them returns a NavigationResponsePolicy decision
    /// Responder Chain proceeds querying a next Responder when `.next` policy decision is returned
    @MainActor
    func decidePolicy(for navigationResponse: NavigationResponse) async -> NavigationResponsePolicy?

    /// Now the Navigation is considered _happened_ and added to the BackForwardList as a Current Item
    @MainActor
    func didCommit(_ navigation: Navigation)

    // MARK: - Completion

    /// Main Frame navigation did finish
    @MainActor
    func navigationDidFinish(_ navigation: Navigation)

    /// Called for both `webView:didFailNavigation:` and `webView:didFailProvisionalNavigation:` - check the `navigation.isCurrent` to distinguish
    @MainActor
    func navigation(_ navigation: Navigation, didFailWith error: WKError)

    /// Called when one of the Responders returned `.download` for `decidePolicyNavigationAction:` query
    @MainActor
    func navigationAction(_ navigationAction: NavigationAction, willBecomeDownloadIn webView: WKWebView)

    /// Called after one of the Responders returned `.download` for `decidePolicy(for:navigationAction)` query and download has started
    /// Not followed by `navigationDidFinish` or `navigation(_:didFail:)` events
    @MainActor
    func navigationAction(_ navigationAction: NavigationAction, didBecome download: WebKitDownload)

    /// Called when one of the Responders returned `.download` for `decidePolicyForNavigationResponse:` query
    @MainActor
    func navigationResponse(_ navigationResponse: NavigationResponse, willBecomeDownloadIn webView: WKWebView)
    /// Called when one of the Responders returned `.download` for `decidePolicy(for:navigationResponse)` query
    /// Not followed by `navigationDidFinish` or `navigation(_:didFail:)` events
    @MainActor
    func navigationResponse(_ navigationResponse: NavigationResponse, didBecome download: WebKitDownload)

    /// Called when WebView process was terminated
    @MainActor
    func webContentProcessDidTerminate(with reason: WKProcessTerminationReason?)

    // MARK: - Private
#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
    @MainActor
    func navigation(_ navigation: Navigation, didSameDocumentNavigationOf navigationType: WKSameDocumentNavigationType)

    @MainActor
    func webViewWillPerformClientRedirect(to url: URL, withDelay delay: TimeInterval)

    @MainActor
    func webViewDidCancelClientRedirect(currentNavigation: Navigation?)

    @MainActor
    func didFinishLoad(with request: URLRequest, in frame: WKFrameInfo)

    @MainActor
    func didFailProvisionalLoad(with request: URLRequest, in frame: WKFrameInfo, with error: Error)

    @MainActor
    func renderingProgressDidChange(progressEvents: UInt)
#endif

    /// Return true to disable stop on decidePolicyForNavigationAction taking longer than 4 secoinds
    @MainActor
    var shouldDisableLongDecisionMakingChecks: Bool { get }

}

// MARK: - Delegate methods are optional
@MainActor
public extension NavigationResponder {

    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? { .next }

    func didCancelNavigationAction(_ navigationAction: NavigationAction, withRedirectNavigations expectedNavigations: [ExpectedNavigation]?) {}

    func willStart(_ navigation: Navigation) {}
    func didStart(_ navigation: Navigation) {}

    @MainActor
    func didReceive(_ authenticationChallenge: URLAuthenticationChallenge, for navigation: Navigation?) async -> AuthChallengeDisposition? { .next }

    func didReceiveRedirect(_ navigationAction: NavigationAction, for navigation: Navigation) {}

    func decidePolicy(for navigationResponse: NavigationResponse) async -> NavigationResponsePolicy? { .next }

    func didCommit(_ navigation: Navigation) {}

    func navigationDidFinish(_ navigation: Navigation) {}

    func navigation(_ navigation: Navigation, didFailWith error: WKError) {}

    func navigationAction(_ navigationAction: NavigationAction, willBecomeDownloadIn webView: WKWebView) {}
    func navigationAction(_ navigationAction: NavigationAction, didBecome download: WebKitDownload) {}
    func navigationResponse(_ navigationResponse: NavigationResponse, willBecomeDownloadIn webView: WKWebView) {}
    func navigationResponse(_ navigationResponse: NavigationResponse, didBecome download: WebKitDownload) {}

    func webContentProcessDidTerminate(with reason: WKProcessTerminationReason?) {}

    @MainActor
    func webViewWillPerformClientRedirect(to url: URL, withDelay delay: TimeInterval) {}

    @MainActor
    func webViewDidCancelClientRedirect(currentNavigation: Navigation?) {}

#if PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED
    @MainActor
    func navigation(_ navigation: Navigation, didSameDocumentNavigationOf navigationType: WKSameDocumentNavigationType) {}

    @MainActor
    func didFinishLoad(with request: URLRequest, in frame: WKFrameInfo) {}

    @MainActor
    func didFailProvisionalLoad(with request: URLRequest, in frame: WKFrameInfo, with error: Error) {}

    @MainActor
    func renderingProgressDidChange(progressEvents: UInt) {}
#endif

    var shouldDisableLongDecisionMakingChecks: Bool { false }

}
