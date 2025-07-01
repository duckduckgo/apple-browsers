//
//  Navigation.swift
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
import WebKit

@MainActor
public final class Navigation {

    fileprivate(set) var identity: NavigationIdentity

    internal private(set) var navigationActions = [NavigationAction]()
    public var navigationResponders: ResponderChain

    /// Is the navigation currently loaded in the WebView
    private(set) public var isCurrent: Bool

    @Published public fileprivate(set) var state: NavigationState
    public private(set) var isCommitted: Bool = false
    public private(set) var didReceiveAuthenticationChallenge: Bool = false

    /// Currently performed Navigation Action. May change for server redirects.
    public var navigationAction: NavigationAction {
        // should always have at least one NavigationAction after `navigationActionReceived` or `started`
        navigationActions.last!
    }
    /// Previous Navigation Actions received during current logical `Navigation`, zero-based, most recent is the last
    public var redirectHistory: [NavigationAction] {
        Array(navigationActions.dropLast())
    }
    /// contains NavigationResponse if it was received during navigation
    public private(set) var navigationResponse: NavigationResponse?

    public init(identity: NavigationIdentity, responders: ResponderChain, state: NavigationState, redirectHistory: [NavigationAction]? = nil, isCurrent: Bool, isCommitted: Bool = false) {
        self.state = state
        self.identity = identity
        self.navigationActions = redirectHistory ?? []
        self.isCommitted = isCommitted
        self.navigationResponders = responders
        self.isCurrent = isCurrent
    }

    /// latest NavigationAction request
    public var request: URLRequest {
        guard !navigationActions.isEmpty else { return URLRequest(url: .empty) }
        return navigationAction.request
    }

    /// latest NavigationAction request URL
    public var url: URL {
        request.url ?? .empty
    }

    /// decidePolicyFor(navigationAction..) approved with .allow
    public var isApproved: Bool {
        switch state {
        case .expected, .navigationActionReceived:
            return false
        case .approved, .started, .willPerformClientRedirect,
             .redirected, .responseReceived, .finished, .failed:
            return true
        }
    }

    /// is Finished or Failed
    public var isCompleted: Bool {
        return state.isCompleted
    }

    internal var hasReceivedNavigationAction: Bool {
        navigationActions.isEmpty == false
    }

}

public protocol NavigationProtocol: AnyObject {
    @MainActor
    var navigationResponders: ResponderChain { get set }
}

extension Navigation: NavigationProtocol {}

@MainActor
public extension NavigationProtocol { // Navigation or ExpectedNavigation

    /** override responder chain for Navigation Events with defined ownership and nullability:
     ```
     navigation.overrideResponders( .weak(responder1), .weak(nullable: responder2), .strong(responder3), .strong(nullable: responder4))
     ```
     **/
    func overrideResponders(_ refs: ResponderRefMaker?...) {
        dispatchPrecondition(condition: .onQueue(.main))

        navigationResponders.setResponders(refs.compactMap { $0 })
    }

    func overrideResponders(with decidePolicy: ((_: NavigationAction, _: inout NavigationPreferences) async -> NavigationActionPolicy?)? = nil,
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
                            navigationResponseDidBecomeDownload: ((NavigationResponse, WebKitDownload) -> Void)? = nil) {
        self.overrideResponders(.struct(ClosureNavigationResponder(decidePolicy: decidePolicy, didCancel: didCancel, willStart: willStart, didStart: didStart, authenticationChallenge: authenticationChallenge, redirected: redirected, navigationResponse: navigationResponse, didCommit: didCommit, navigationDidFinish: navigationDidFinish, navigationDidFail: navigationDidFail, navigationActionWillBecomeDownload: navigationActionWillBecomeDownload, navigationActionDidBecomeDownload: navigationActionDidBecomeDownload, navigationResponseWillBecomeDownload: navigationResponseWillBecomeDownload, navigationResponseDidBecomeDownload: navigationResponseDidBecomeDownload)))
    }

    func appendResponder(with decidePolicy: ((_: NavigationAction, _: inout NavigationPreferences) async -> NavigationActionPolicy?)? = nil,
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
                         navigationResponseDidBecomeDownload: ((NavigationResponse, WebKitDownload) -> Void)? = nil) {
        self.navigationResponders.append(.struct(ClosureNavigationResponder(decidePolicy: decidePolicy, didCancel: didCancel, willStart: willStart, didStart: didStart, authenticationChallenge: authenticationChallenge, redirected: redirected, navigationResponse: navigationResponse, didCommit: didCommit, navigationDidFinish: navigationDidFinish, navigationDidFail: navigationDidFail, navigationActionWillBecomeDownload: navigationActionWillBecomeDownload, navigationActionDidBecomeDownload: navigationActionDidBecomeDownload, navigationResponseWillBecomeDownload: navigationResponseWillBecomeDownload, navigationResponseDidBecomeDownload: navigationResponseDidBecomeDownload)))
    }

    func prependResponder(with decidePolicy: ((_: NavigationAction, _: inout NavigationPreferences) async -> NavigationActionPolicy?)? = nil,
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
                          navigationResponseDidBecomeDownload: ((NavigationResponse, WebKitDownload) -> Void)? = nil) {
        self.navigationResponders.prepend(.struct(ClosureNavigationResponder(decidePolicy: decidePolicy, didCancel: didCancel, willStart: willStart, didStart: didStart, authenticationChallenge: authenticationChallenge, redirected: redirected, navigationResponse: navigationResponse, didCommit: didCommit, navigationDidFinish: navigationDidFinish, navigationDidFail: navigationDidFail, navigationActionWillBecomeDownload: navigationActionWillBecomeDownload, navigationActionDidBecomeDownload: navigationActionDidBecomeDownload, navigationResponseWillBecomeDownload: navigationResponseWillBecomeDownload, navigationResponseDidBecomeDownload: navigationResponseDidBecomeDownload)))
    }

}

public struct NavigationIdentity: Equatable {

    private var value: UnsafeMutableRawPointer?

    public init(_ value: AnyObject?) {
        self.value = value.map { Unmanaged.passUnretained($0).toOpaque() }
    }

    public static var expected = NavigationIdentity(nil)

    fileprivate mutating func resolve(with navigation: WKNavigation?) {
        guard let navigation else { return }
        let newValue = Unmanaged.passUnretained(navigation).toOpaque()
        assert(self.value == nil || self.value == newValue)
        self.value = newValue
    }

    public static func == (lhs: NavigationIdentity, rhs: NavigationIdentity) -> Bool {
        return lhs.value == rhs.value
    }

}

extension Navigation {

    func associate(with wkNavigation: WKNavigation?) {
        guard let wkNavigation, wkNavigation.navigation !== self else { return }

        // ensure Navigation object lifetime is bound to the WKNavigation in case it‘s not properly started or finished
        wkNavigation.onDeinit { [self] in
            DispatchQueue.main.async { [self] in
                self.checkNavigationCompletion()
            }
        }
        wkNavigation.navigation = self
    }

    /// ensure the Navigation is completed when WKNavigation is deallocated
    private func checkNavigationCompletion() {
        guard !isCompleted, isApproved else { return }

        let error = WKError(_nsError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        self.state = .failed(error)

        for responder in navigationResponders {
            responder.navigation(self, didFailWith: error)
        }
    }

    private func resolve(with wkNavigation: WKNavigation?) {
        self.associate(with: wkNavigation)
        self.identity.resolve(with: wkNavigation)
    }

    func navigationActionReceived(_ navigationAction: NavigationAction) {
        assert(navigationAction.isForMainFrame)

        switch state {
        case .expected(let navigationType):
            assert(navigationType == nil || navigationType == navigationAction.navigationType)
            if let redirectHistory = navigationAction.redirectHistory, !redirectHistory.isEmpty {
                // new navigations started from navigationAction
                assert(navigationActions.isEmpty)
                self.navigationActions = (navigationAction.redirectHistory ?? []) + [navigationAction]
            } else {
                // navigations redirected from decidePolicyForNavigationAction handler
                self.navigationActions.append(navigationAction)
            }
            self.state = .navigationActionReceived

        case .started:
            // receiving another NavigationAction when already started means server redirect
            willPerformServerRedirect(with: navigationAction)

        case .navigationActionReceived, .approved, .responseReceived, .finished, .failed, .willPerformClientRedirect, .redirected:
            assertionFailure("unexpected state \(self.state)")
        }
    }

    func willStart() {
        guard case .navigationActionReceived = self.state else {
            assertionFailure("unexpected state \(self.state)")
            return
        }
        self.state = .approved
    }

    func started(_ navigation: WKNavigation?) {
        self.resolve(with: navigation)

        guard case .approved = self.state else {
            assertionFailure("unexpected state \(self.state)")
            return
        }

        self.state = .started
        isCurrent = true
    }

    func didResignCurrent() {
        guard isCurrent else { return }
        isCurrent = false
    }

    func challengeRececived() {
        self.didReceiveAuthenticationChallenge = true
    }

    func committed(_ navigation: WKNavigation?) {
        self.resolve(with: navigation)
        assert(state == .started || state.isResponseReceived)
        self.isCommitted = true
    }

    func receivedResponse(_ response: NavigationResponse) {
        assert(state == .started)
        self.navigationResponse = response
        self.state = .responseReceived
    }

    func didFinish(_ navigation: WKNavigation? = nil) {
        self.resolve(with: navigation)

        switch self.state {
        case .willPerformClientRedirect:
            // expecting didPerformClientRedirect/didCancelClientRedirect/didFail
            return
        case .started, .redirected:
            self.state = .finished
        case .responseReceived:
            // regular flow
            self.state = .finished
        case .navigationActionReceived where navigationAction.navigationType.isSameDocumentNavigation:
            self.state = .finished
        case .approved where navigationAction.navigationType.isBackForward:
            self.state = .finished
        case .expected, .navigationActionReceived, .approved, .finished, .failed:
            assertionFailure("unexpected state \(self.state)")
        }
    }

    func didFail(_ navigation: WKNavigation? = nil, with error: WKError) {
        assert(!state.isExpected, "non-started navigations should‘t receive didFail")
        if let navigation {
            self.resolve(with: navigation)
        }

        if case .willPerformClientRedirect = self.state {
            // expecting didPerformClientRedirect/didCancelClientRedirect/didFail
            return
        }

        self.state = .failed(error)
    }

    func willPerformServerRedirect(with navigationAction: NavigationAction) {
        assert(navigationAction.navigationType == .redirect(.server))

        switch state {
        case .started:
            self.state = .redirected(.server)
            self.navigationActions.append(navigationAction)
        case .expected, .navigationActionReceived, .approved, .responseReceived, .finished, .failed, .willPerformClientRedirect, .redirected:
            assertionFailure("unexpected state \(self.state)")
        }
    }

    func didReceiveServerRedirect(for navigation: WKNavigation?) {
        self.resolve(with: navigation)
        switch state {
        case .redirected(.server):
            // expected didReceiveServerRedirect
            self.state = .started
        case .started:
            // duplicate(cyclic) server redirect called without decidePolicyForNavigationAction:
            self.navigationActions.append(self.navigationActions.last!)
        case .expected, .navigationActionReceived, .approved, .failed, .finished, .responseReceived, .willPerformClientRedirect, .redirected:
            assertionFailure("didReceiveServerRedirect should happen after decidePolicyForNavigationAction")
        }
    }

    func willPerformClientRedirect(to url: URL, delay: TimeInterval) {
        switch state {
        case .started, .responseReceived:
            self.state = .willPerformClientRedirect(delay: delay)
        case .expected, .navigationActionReceived, .approved, .finished, .failed, .willPerformClientRedirect, .redirected:
            assertionFailure("unexpected state \(self.state)")
        }
    }

    func didPerformClientRedirect(with navigationAction: NavigationAction) {
        guard case .willPerformClientRedirect(delay: let delay) = state else {
            assertionFailure("unexpected didPerformClientRedirect")
            return
        }

        self.state = .redirected(.client(delay: delay))
        for responder in navigationResponders {
            responder.didReceiveRedirect(navigationAction, for: self)
        }
    }

    func didSendDidPerformClientRedirectToResponders(with error: WKError? = nil) {
        guard case .redirected(.client) = state else {
            assertionFailure("unexpected didPerformClientRedirect")
            return
        }
        if let error {
            self.state = .failed(error)
        } else {
            self.state = .finished
        }
    }

    func didCancelClientRedirect() {
        guard case .willPerformClientRedirect = state else {
            assertionFailure("unexpected didPerformClientRedirect")
            return
        }
        self.state = .responseReceived
    }

}

extension Navigation: CustomDebugStringConvertible {
    public nonisolated var debugDescription: String {
        guard Thread.isMainThread else {
            assertionFailure("Accessing Navigation from background thread")
            return "<ExpectedNavigation ?>"
        }
        return MainActor.assumeIsolated {
            "<\(identity) #\(navigationAction.identifier): url:\(url.absoluteString) state:\(state)\(isCommitted ? "(committed)" : "") type:\(navigationActions.last?.navigationType.debugDescription ?? "<nil>")\(isCurrent ? "" : " non-current")>"
        }
    }
}

extension NavigationIdentity: CustomStringConvertible {
    public var description: String {
        "WKNavigation: " + (value?.hexValue ?? "nil")
    }
}
