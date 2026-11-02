//
//  BrowserToolPageAccess.swift
//  DuckDuckGo
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

import AIChat
import Combine
import Foundation
import WebKit

@MainActor
protocol BrowserToolPageContentReading: AnyObject {
    func pageContext(for tab: Tab, scope: BrowserToolScope) async -> AIChatPageContextData?
}

@MainActor
final class BrowserToolPageLease {
    let page: MultiTabAttachmentPage
    private let scope: BrowserToolScope
    private let tab: Tab
    private let reservation: MultiTabAttachmentPage.Reservation
    private var identity: MultiTabAttachmentPage.Identity
    private var permitsInitialNavigation: Bool
    private var invalidated = false
    private var readyURL: URL?

    init?(scope: BrowserToolScope, tab: Tab) {
        guard !Task.isCancelled else {
            return nil
        }
        guard scope.contains(tab) else {
            return nil
        }
        guard let url = tab.link?.url else {
            return nil
        }
        guard scope.isAttachableURL(url) else {
            return nil
        }
        guard let reservation = scope.source.acquirePage(tab) else {
            return nil
        }
        guard let controller = scope.controller(tab) else {
            reservation.release()
            return nil
        }
        controller.loadViewIfNeeded()
        guard let page = scope.source.pageProvider(tab) else {
            reservation.release()
            return nil
        }
        page.loadIfNeeded()
        guard let state = page.state(), !state.hasTerminatedProcess else {
            reservation.release()
            return nil
        }
        self.scope = scope
        self.tab = tab
        self.page = page
        self.reservation = reservation
        self.identity = state.identity
        self.permitsInitialNavigation = state.isInitialRequestPending
    }

    func release() {
        invalidated = true
        reservation.release()
    }

    func isValid() -> Bool {
        guard !invalidated, scope.contains(tab), let state = page.state(), !state.hasTerminatedProcess else {
            invalidated = true
            return false
        }
        if let readyURL, state.url != readyURL || tab.link?.url != readyURL || !state.isAttachable {
            invalidated = true
            return false
        }
        if state.identity != identity {
            guard permitsInitialNavigation, !state.isInitialRequestPending,
                  state.identity.webView == identity.webView else {
                invalidated = true
                return false
            }
            identity = state.identity
            permitsInitialNavigation = false
        }
        if !state.isInitialRequestPending {
            permitsInitialNavigation = false
        }
        return true
    }

    var changes: AnyPublisher<Void, Never> {
        let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect().map { _ in () }
        return page.changes.merge(with: page.processTerminations, timer).eraseToAnyPublisher()
    }

    func ready() async -> MultiTabAttachmentPage.State? {
        let changes = changes.prepend(())
            .filter { !self.isValid() || self.page.state()?.isLoading != true }.eraseToAnyPublisher()
        let outcome = await MultiTabAttachmentWaiter.firstValue(from: changes, timeout: 5)
        guard case .value = outcome, !Task.isCancelled, isValid() else {
            return nil
        }
        guard let ready = page.state() else {
            return nil
        }
        guard ready.isLoaded, !ready.isLoading, ready.isAttachable, let url = ready.url,
              scope.isAttachableURL(url) else {
            return nil
        }
        readyURL = url
        return ready
    }
}

@MainActor
final class BrowserToolPageContentReader: BrowserToolPageContentReading {
    func pageContext(for tab: Tab, scope: BrowserToolScope) async -> AIChatPageContextData? {
        guard let lease = BrowserToolPageLease(scope: scope, tab: tab) else {
            return nil
        }
        defer { lease.release() }
        guard let ready = await lease.ready(), let url = ready.url else {
            return nil
        }
        let result = await lease.page.collect(url, { lease.isValid() })
        guard !Task.isCancelled, lease.isValid(), let final = lease.page.state(), final.identity == ready.identity,
              final.isLoaded, !final.isLoading, final.isAttachable, final.url == url,
              tab.link?.url == url, case .collected(let context) = result,
              context.url == url.absoluteString, context.hasAttachedPage, context.attachable != false else {
            return nil
        }
        return context.withTabId(tab.uid)
    }
}

enum BrowserToolHighlightOutcome: Equatable {
    case painted(count: UInt?)
    case notFound
    case cancelled
}

@MainActor
protocol BrowserToolPageHighlighting: AnyObject {
    func isFindBarVisible(in tab: Tab, scope: BrowserToolScope) -> Bool
    func highlight(_ quote: String, in tab: Tab, scope: BrowserToolScope) async -> BrowserToolHighlightOutcome
}

@MainActor
final class WebViewPageHighlighter: BrowserToolPageHighlighting {
    func isFindBarVisible(in tab: Tab, scope: BrowserToolScope) -> Bool {
        guard let controller = scope.controller(tab) else { return false }
        if controller.findInPage != nil { return true }
        if #available(iOS 16.0, *) {
            return controller.webView?.findInteraction?.isFindNavigatorVisible == true
        }
        return false
    }

    func highlight(_ quote: String, in tab: Tab, scope: BrowserToolScope) async -> BrowserToolHighlightOutcome {
        guard !Task.isCancelled, !isFindBarVisible(in: tab, scope: scope),
              let lease = BrowserToolPageLease(scope: scope, tab: tab) else { return .cancelled }
        defer { lease.release() }
        guard let ready = await lease.ready(), !isFindBarVisible(in: tab, scope: scope),
              let webView = scope.controller(tab)?.webView else { return .cancelled }
        let configuration = WKFindConfiguration()
        configuration.caseSensitive = true
        configuration.wraps = true
        let completion = PassthroughSubject<Bool?, Never>()
        let invalidation = lease.changes.filter { !lease.isValid() || self.isFindBarVisible(in: tab, scope: scope) }
            .map { _ -> Bool? in nil }
        let result = await MultiTabAttachmentWaiter.firstValue(
            from: completion.merge(with: invalidation).eraseToAnyPublisher(), timeout: 5,
            afterSubscription: {
                webView.find(quote, configuration: configuration) { result in
                    completion.send(result.matchFound)
                }
            })
        guard case .value(let found) = result, let found, !Task.isCancelled,
              lease.isValid(), !isFindBarVisible(in: tab, scope: scope), scope.controller(tab)?.webView === webView,
              let current = lease.page.state(), current.identity == ready.identity,
              !current.isLoading, !current.hasTerminatedProcess else { return .cancelled }
        return found ? .painted(count: nil) : .notFound
    }
}
