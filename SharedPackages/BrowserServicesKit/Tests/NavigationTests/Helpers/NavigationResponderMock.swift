//
//  NavigationResponderMock.swift
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
import Navigation
import WebKit
import Common

enum TestsNavigationEvent: TestComparable {
    case navigationAction(NavAction, NavigationPreferences = .default, line: UInt = #line)
    case didCancel(NavAction, expected: Int? = nil, line: UInt = #line)
    case navActionWillBecomeDownload(NavAction, line: UInt = #line)
    case navActionBecameDownload(NavAction, String, line: UInt = #line)
    case willStart(Nav, line: UInt = #line)
    case didStart(Nav, line: UInt = #line)
    case didReceiveAuthenticationChallenge(URLProtectionSpace, Nav?, line: UInt = #line)

    enum EitherResponseOrNavigation: Equatable {
        case response(NavResponse, navigation: Nav?)
        case navigation(Nav)
        var response: NavigationResponse {
            switch self {
            case .response(let resp, navigation: _): return resp.response
            case .navigation(let nav): return nav.response!.response
            }
        }
        static func == (lhs: TestsNavigationEvent.EitherResponseOrNavigation, rhs: TestsNavigationEvent.EitherResponseOrNavigation) -> Bool {
            switch lhs {
            case .response(let resp1, navigation: let nav1):
                if case .response(let resp2, navigation: let nav2) = rhs {
                    return NavigationResponse.difference(between: resp1.response, and: resp2.response) == nil && nav1 == nav2
                }
            case .navigation(let nav):
                if case .navigation(nav) = rhs {
                    return true
                }
            }
            return false
        }
    }
    case navigationResponse(EitherResponseOrNavigation, line: UInt = #line)
    case navResponseWillBecomeDownload(Int, line: UInt = #line)
    case navResponseBecameDownload(Int, URL, line: UInt = #line)
    case didCommit(Nav, line: UInt = #line)
    case didSameDocumentNavigation(Nav?, Int, line: UInt = #line)
    case didReceiveRedirect(NavAction, Nav, line: UInt = #line)
    case didFinish(Nav, line: UInt = #line)
    case didFail(Nav, /*code:*/ Int, line: UInt = #line)
    case didTerminate(WKProcessTerminationReason?, line: UInt = #line)

    static func navigationAction(_ navigationAction: NavigationAction, _ prefs: NavigationPreferences = .default, line: UInt = #line) -> TestsNavigationEvent {
        return .navigationAction(NavAction(navigationAction), prefs, line: line)
    }
    static func navActionWillBecomeDownload(_ navigationAction: NavigationAction, line: UInt = #line) -> TestsNavigationEvent {
        return .navActionWillBecomeDownload(NavAction(navigationAction), line: line)
    }
    static func navActionBecameDownload(_ navigationAction: NavAction, _ url: URL, line: UInt = #line) -> TestsNavigationEvent {
        return .navActionBecameDownload(navigationAction, url.string.dropping(suffix: "/"), line: line)
    }

    static func didReceiveRedirect(_ nav: Nav, line: UInt = #line) -> TestsNavigationEvent {
        return .didReceiveRedirect(nav.navigationAction, nav, line: line)
    }

    var redirectEvent: Nav? {
        if case .didReceiveRedirect(_, let nav, line: _) = self { return nav }
        return nil
    }

    var line: UInt {
        Mirror(reflecting: Mirror(reflecting: self).children.first!.value).children.first(where: { $0.label == "line" })?.value as! UInt
    }

    var type: String {
        let descr = String(describing: self)
        if let idx = descr.range(of: ".")?.lowerBound {
            return String(descr[..<idx])
        } else {
            return descr
        }
    }

    static func difference(between lhs: TestsNavigationEvent, and rhs: TestsNavigationEvent) -> String? {
        let caseMirror1 = Mirror(reflecting: lhs).children.first!
        let caseMirror2 = Mirror(reflecting: rhs).children.first!
        return compare(caseMirror1.label!, caseMirror1.label!, caseMirror2.label)
        ?? {
            let values1 = Mirror(reflecting: caseMirror1.value).children.map { $0.value }
            for (idx, child2) in Mirror(reflecting: caseMirror2.value).children.enumerated() {
                let label: String
                if child2.label == "line" { continue }
                if let childLabel = child2.label, !childLabel.matches(regex("\\.\\d+")) {
                    label = childLabel
                } else {
                    label = ""
                }
                func compareAnyTestComparable(_ lhs: any TestComparable, _ rhs: (any TestComparable)?) -> String? {
                    func compareSomeTestComparable<T: TestComparable>(_ lhs: T, _ rhs: (any TestComparable)?) -> String? {
                        compare(label, .some(lhs), rhs as? T)
                    }
                    return compareSomeTestComparable(lhs, rhs)
                }
                func compareAnyTestComparable(_ lhs: (any TestComparable)?, _ rhs: any TestComparable) -> String? {
                    func compareSomeTestComparable<T: TestComparable>(_ lhs: (any TestComparable)?, _ rhs: T) -> String? {
                        compare(label, lhs as? T, .some(rhs))
                    }
                    return compareSomeTestComparable(lhs, rhs)
                }
                func compareAnyEquatable(_ lhs: any Equatable, _ rhs: any Equatable) -> String? {
                    func compareSomeEquatable<T: Equatable>(_ lhs: T, _ rhs: any Equatable) -> String? {
                        compare(label, lhs, rhs as? T)
                    }
                    return compareSomeEquatable(lhs, rhs)
                }

                if let testComparable = values1[idx] as? any TestComparable {
                    if let diff = compareAnyTestComparable(testComparable, child2.value as? any TestComparable) {
                        return diff
                    }
                } else if let testComparable2 = child2.value as? any TestComparable {
                    if let diff = compareAnyTestComparable(values1[idx] as? any TestComparable, testComparable2) {
                        return diff
                    }
                } else if let equatable = values1[idx] as? any Equatable {
                    if let diff = compareAnyEquatable(equatable, child2.value as! any Equatable) {
                        return diff
                    }
                } else {
                    fatalError("non-equatable")
                }
            }
            return nil
        }()
    }

}

struct NavAction: Equatable, TestComparable {
    let navigationAction: NavigationAction

    init(_ request: URLRequest, _ navigationType: NavigationType, from currentHistoryItemIdentity: HistoryItemIdentity? = nil, redirects: [NavAction]? = nil, _ isUserInitiated: NavigationAction.UserInitiated? = nil, src: FrameInfo, targ: FrameInfo?, _ shouldDownload: NavigationAction.ShouldDownload? = nil) {
        self.navigationAction = .init(request: request, navigationType: navigationType, currentHistoryItemIdentity: currentHistoryItemIdentity, redirectHistory: redirects?.map(\.navigationAction), isUserInitiated: isUserInitiated != nil, sourceFrame: src, targetFrame: targ, shouldDownload: shouldDownload != nil, mainFrameNavigation: nil)
    }
    init(_ request: URLRequest, _ navigationType: NavigationType, from currentHistoryItemIdentity: HistoryItemIdentity? = nil, redirects: [NavAction]? = nil, _ isUserInitiated: NavigationAction.UserInitiated? = nil, src: FrameInfo, _ shouldDownload: NavigationAction.ShouldDownload? = nil) {
        self.init(request, navigationType, from: currentHistoryItemIdentity, redirects: redirects, isUserInitiated, src: src, targ: src, shouldDownload)
    }

    init(_ navigationAction: NavigationAction) {
        self.navigationAction = navigationAction
    }

    static func difference(between lhs: NavAction, and rhs: NavAction) -> String? {
        NavigationAction.difference(between: lhs.navigationAction, and: rhs.navigationAction)
    }

    static func == (lhs: NavAction, rhs: NavAction) -> Bool {
        return NavigationAction.difference(between: lhs.navigationAction, and: rhs.navigationAction) == nil
    }
}

class NavigationResponderMock: NavigationResponder {

    var history: [TestsNavigationEvent] = []
    private(set) var navigations: [Navigation] = []
    var navigationActionsCache: (dict: [UInt64: NavAction], max: UInt64) = ([:], 0)
    private(set) var navigationResponses: [NavResponse] = []

    static let defaultHandler: ((TestsNavigationEvent) -> Void) = {
        fatalError("not handled: \($0)")
    }
    var defaultHandler: ((TestsNavigationEvent) -> Void)

    var mainFrame: FrameInfo? {
        for event in history {
            if case .navigationAction(let navAction, _, _) = event,
               navAction.navigationAction.sourceFrame.isMainFrame {

                return navAction.navigationAction.sourceFrame
            }
        }
        return nil
    }

    init(defaultHandler: @escaping ((TestsNavigationEvent) -> Void) = NavigationResponderMock.defaultHandler) {
        self.defaultHandler = defaultHandler
    }

    func reset(defaultHandler: @escaping ((TestsNavigationEvent) -> Void)) {
        clear()

        onNavigationAction = nil
        onWillStart = nil
        onDidStart = nil
        onDidReceiveAuthenticationChallenge = nil
        onDidReceiveRedirect = nil
        onNavigationResponse = nil
        onDidFail = nil
        onDidFinish = nil
        onDidCommit = nil
        onDidTerminate = nil

        onNavActionWillBecomeDownload = nil
        onNavActionBecameDownload = nil

        onNavResponseWillBecomeDownload = nil
        onNavResponseBecameDownload = nil

        self.defaultHandler = defaultHandler
    }
    func clear() {
        history = []
    }

    private func append(_ event: TestsNavigationEvent) -> TestsNavigationEvent {
        history.append(event)
        return event
    }

    var onNavigationAction: (@MainActor (NavigationAction, inout NavigationPreferences) async -> NavigationActionPolicy?)?
    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        navigationActionsCache.dict[navigationAction.identifier] = .init(navigationAction)
        navigationActionsCache.max = max(navigationActionsCache.max, navigationAction.identifier)

        let event = append(.navigationAction(navigationAction, preferences))
        guard let onNavigationAction = onNavigationAction else {
            defaultHandler(event)
            return.next
        }
        return await onNavigationAction(navigationAction, &preferences)
    }

    var onDidCancelNavigationAction: (@MainActor (NavigationAction, [ExpectedNavigation]?) -> Void)?
    func didCancelNavigationAction(_ navigationAction: NavigationAction, withRedirectNavigations expectedNavigations: [ExpectedNavigation]?) {
        let event = append(.didCancel(NavAction(navigationAction), expected: expectedNavigations?.count))
        onDidCancelNavigationAction?(navigationAction, expectedNavigations) ?? defaultHandler(event)
    }

    var onNavActionWillBecomeDownload: (@MainActor (NavigationAction) -> Void)?
    func navigationAction(_ navigationAction: NavigationAction, willBecomeDownloadIn webView: WKWebView) {
        let event = append(.navActionWillBecomeDownload(navigationAction))
        onNavActionWillBecomeDownload?(navigationAction) ?? defaultHandler(event)
    }

    var onNavActionBecameDownload: (@MainActor (NavigationAction, WebKitDownload) -> Void)?
    func navigationAction(_ navigationAction: NavigationAction, didBecome download: WebKitDownload) {
        let event = append(.navActionBecameDownload(NavAction(navigationAction), download.originalRequest!.url!))
        onNavActionBecameDownload?(navigationAction, download) ?? defaultHandler(event)
    }

    var onWillStart: (@MainActor (Navigation) -> Void)?
    func willStart(_ navigation: Navigation) {
        if navigationActionsCache.dict[navigation.navigationAction.identifier] == nil {
            navigationActionsCache.dict[navigation.navigationAction.identifier] = .init(navigation.navigationAction)
            navigationActionsCache.max = max(navigationActionsCache.max, navigation.navigationAction.identifier)
        }

        navigations.append(navigation)
        let event = append(.willStart(Nav(navigation)))
        onWillStart?(navigation) ?? defaultHandler(event)
    }

    @MainActor
    func Nav(_ navigation: Navigation) -> Nav {
        NavigationTests.Nav(action: .init(navigation.navigationAction),
                            redirects: navigation.redirectHistory.map { NavAction($0) },
                            navigation.state,
                            resp: navigation.navigationResponse.map(NavResponse.init),
                            navigation.isCommitted ? .committed : nil,
                            navigation.didReceiveAuthenticationChallenge ? .gotAuth : nil,
                            isCurrent: navigation.isCurrent)
    }
    @MainActor
    func Nav(_ navigation: Navigation?) -> Nav? {
        navigation == nil ? nil : .some(Nav(navigation!))
    }

    var onDidStart: (@MainActor (Navigation) -> Void)?
    func didStart(_ navigation: Navigation) {
        let event = append(.didStart(Nav(navigation)))
        onDidStart?(navigation) ?? defaultHandler(event)
    }

    var onDidReceiveAuthenticationChallenge: (@MainActor (URLAuthenticationChallenge, Navigation?) async -> AuthChallengeDisposition?)?
    @MainActor
    func didReceive(_ authenticationChallenge: URLAuthenticationChallenge, for navigation: Navigation?) async -> AuthChallengeDisposition? {
        let event = append(.didReceiveAuthenticationChallenge(authenticationChallenge.protectionSpace, Nav(navigation)))
        return await onDidReceiveAuthenticationChallenge?(authenticationChallenge, navigation) ?? {
            defaultHandler(event)
            return .next
        }()
    }

    var onDidReceiveRedirect: (@MainActor (NavigationAction, Navigation) -> Void)?
    @MainActor
    func didReceiveRedirect(_ navigationAction: NavigationAction, for navigation: Navigation) {
        let event = append(.didReceiveRedirect(NavAction(navigationAction), Nav(navigation)))
        onDidReceiveRedirect?(navigationAction, navigation) ?? {
            defaultHandler(event)
        }()
    }

    var onNavigationResponse: (@MainActor (NavigationResponse) async -> NavigationResponsePolicy?)?
    @MainActor
    func decidePolicy(for navigationResponse: NavigationResponse) async -> NavigationResponsePolicy? {
        navigationResponses.append(NavResponse(response: navigationResponse))
        let event = append(.navigationResponse(navigationResponse.isForMainFrame ? .navigation(Nav(navigationResponse.mainFrameNavigation!))
                                               : .response(NavResponse(response: navigationResponse), navigation: Nav(navigationResponse.mainFrameNavigation))))
        return await onNavigationResponse?(navigationResponse) ?? {
            defaultHandler(event)
            return .next
        }()

    }

    var onNavResponseWillBecomeDownload: (@MainActor (NavigationResponse) -> Void)?
    func navigationResponse(_ navigationResponse: NavigationResponse, willBecomeDownloadIn webView: WKWebView) {
        let event = append(.navResponseWillBecomeDownload(navigationResponses.firstIndex(of: NavResponse(response: navigationResponse))!))
        onNavResponseWillBecomeDownload?(navigationResponse) ?? defaultHandler(event)
    }

    var onNavResponseBecameDownload: (@MainActor (NavigationResponse, WebKitDownload) -> Void)?
    @MainActor
    func navigationResponse(_ navigationResponse: NavigationResponse, didBecome download: WebKitDownload) {
        let event = append(.navResponseBecameDownload(navigationResponses.firstIndex(of: NavResponse(response: navigationResponse))!, download.originalRequest!.url!))
        onNavResponseBecameDownload?(navigationResponse, download) ?? defaultHandler(event)
    }

    var onDidCommit: (@MainActor (Navigation) -> Void)?
    func didCommit(_ navigation: Navigation) {
        let event = append(.didCommit(Nav(navigation)))
        onDidCommit?(navigation) ?? defaultHandler(event)
    }

    var onSameDocumentNavigation: (@MainActor (Navigation?, WKSameDocumentNavigationType?) -> Void)?
    @MainActor
    func navigation(_ navigation: Navigation, didSameDocumentNavigationOf navigationType: WKSameDocumentNavigationType) {
        if navigationActionsCache.dict[navigation.navigationAction.identifier] == nil {
            navigationActionsCache.dict[navigation.navigationAction.identifier] = .init(navigation.navigationAction)
            navigationActionsCache.max = max(navigationActionsCache.max, navigation.navigationAction.identifier)
        }

        let event = append(.didSameDocumentNavigation(Nav(navigation), navigationType.rawValue))
        onSameDocumentNavigation?(navigation, navigationType) ?? defaultHandler(event)
    }

    var onDidFinish: (@MainActor (Navigation) -> Void)?
    func navigationDidFinish(_ navigation: Navigation) {
        let event = append(.didFinish(Nav(navigation)))
        onDidFinish?(navigation) ?? defaultHandler(event)
    }

    var onDidFail: (@MainActor (Navigation, WKError) -> Void)?
    func navigation(_ navigation: Navigation, didFailWith error: WKError) {
        let event = append(.didFail(Nav(navigation), error.code.rawValue))
        onDidFail?(navigation, error) ?? defaultHandler(event)
    }

    var onDidTerminate: (@MainActor (WKProcessTerminationReason?) -> Void)?
    func webContentProcessDidTerminate(with reason: WKProcessTerminationReason?) {
        onDidTerminate?(reason)
    }

}
