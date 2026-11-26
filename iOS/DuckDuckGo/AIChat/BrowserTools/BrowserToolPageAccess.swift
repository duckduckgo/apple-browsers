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

@MainActor
enum BrowserToolTargetTab {
    enum Resolution {
        case resolved(Tab)
        case failure(BrowserToolFailure)
    }

    static func resolve(tabIDArgument: JSONValue?, context: BrowserToolCallContext, scope: BrowserToolScope) -> Resolution {
        let tabID: String
        switch tabIDArgument {
        case .none, .some(.null): tabID = context.ownerTabID
        case .some(.string(let value)):
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            tabID = trimmed.isEmpty ? context.ownerTabID : trimmed
        default: return .failure(.invalidArguments)
        }
        guard scope.accepts(context) else { return .failure(.unavailable) }
        guard let tab = scope.source.tabsProvider().first(where: { $0.uid == tabID }) else { return .failure(.notFound) }
        guard scope.contains(tab) else { return .failure(.unavailable) }
        return .resolved(tab)
    }
}

@MainActor
protocol BrowserToolPageContentReading: AnyObject {
    func pageContext(for tab: Tab, in scope: BrowserToolScope) async -> AIChatPageContextData?
}

@MainActor
final class BrowserToolPageContentReader: BrowserToolPageContentReading {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 5) {
        self.timeout = timeout
    }

    func pageContext(for tab: Tab, in scope: BrowserToolScope) async -> AIChatPageContextData? {
        guard !Task.isCancelled, scope.canRead(tab), let url = tab.link?.url,
              !AIChatTabMetadata.shouldExcludeFromTabPicker(url),
              let reservation = scope.source.acquirePage(tab) else {
            return nil
        }
        defer { reservation.release() }

        guard let page = scope.source.pageProvider(tab) else { return nil }
        page.loadIfNeeded()

        guard let initial = page.state(), !initial.hasTerminatedProcess else {
            return nil
        }

        let lease = BrowserToolDocumentLease(tab: tab, scope: scope, page: page, initial: initial)

        var subscriptions = Set<AnyCancellable>()
        let events = page.changes.merge(with: scope.revocations).eraseToAnyPublisher()
        events.sink { lease.check() }.store(in: &subscriptions)

        page.processTerminations.sink {
            lease.invalidate()
        }.store(in: &subscriptions)

        scope.source.tabsPublisher?.sink { _ in lease.check() }.store(in: &subscriptions)
        defer { subscriptions.removeAll() }

        guard !Task.isCancelled, lease.isValid, let loaded = page.state(),
              loaded.isLoaded || loaded.isLoading, timeout > 0 else { return nil }

        if loaded.isLoading {
            let finished = lease.events.prepend(())
                .filter { !lease.isValid || page.state()?.isLoading != true }
                .eraseToAnyPublisher()

            let readiness = await MultiTabAttachmentWaiter.firstValue(from: finished, timeout: timeout)
            guard case .value = readiness else { return nil }
        }

        guard !Task.isCancelled, lease.isValid, let ready = page.state(), ready.isLoaded,
              !ready.isLoading, ready.isAttachable, let documentURL = ready.url else {
            return nil
        }

        let completion = PassthroughSubject<MultiTabAttachmentCollectionResult, Never>()
        let outcome = completion.merge(with: lease.events.compactMap { _ in
            lease.isValid ? nil : MultiTabAttachmentCollectionResult.cancelled
        }).eraseToAnyPublisher()

        var collection: Task<Void, Never>?
        defer { collection?.cancel() }

        let result = await MultiTabAttachmentWaiter.firstValue(from: outcome, timeout: timeout) {
            collection = Task { @MainActor in
                guard !Task.isCancelled, lease.pin(ready) else { completion.send(.cancelled); return }

                let collected = await page.collect(documentURL, { lease.isValid && !Task.isCancelled })
                completion.send(collected)
            }
        }

        guard !Task.isCancelled, lease.isValid, case .value(.collected(let context)) = result,
              context.url == lease.documentURL?.absoluteString,
              context.hasAttachedPage, context.attachable != false else {
            return nil
        }

        return context
    }
}

@MainActor
private final class BrowserToolDocumentLease {
    let events = PassthroughSubject<Void, Never>()
    private let tab: Tab
    private let scope: BrowserToolScope
    private let page: MultiTabAttachmentPage
    private var identity: MultiTabAttachmentPage.Identity
    private var permitsInitialNavigation: Bool
    private var invalidated = false
    private var document: MultiTabAttachmentPage.State?

    var documentURL: URL? { document?.url }

    init(tab: Tab, scope: BrowserToolScope, page: MultiTabAttachmentPage, initial: MultiTabAttachmentPage.State) {
        self.tab = tab
        self.scope = scope
        self.page = page
        self.identity = initial.identity
        self.permitsInitialNavigation = initial.isInitialRequestPending
    }

    var isValid: Bool {
        guard !invalidated, scope.canRead(tab), let state = page.state(),
              !state.hasTerminatedProcess, state.identity.webView == identity.webView else {
            invalidated = true
            return false
        }
        if let document {
            guard state.identity == document.identity, state.url == document.url, tab.link?.url == document.url,
                  state.isLoaded, !state.isLoading, state.isAttachable else {
                invalidated = true
                return false
            }
        }
        if state.identity != identity {
            guard permitsInitialNavigation, !state.isInitialRequestPending else {
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

    func pin(_ state: MultiTabAttachmentPage.State) -> Bool {
        guard isValid, let url = state.url, tab.link?.url == url,
              !AIChatTabMetadata.shouldExcludeFromTabPicker(url) else { return false }
        document = state
        return isValid
    }

    func check() {
        _ = isValid
        events.send(())
    }

    func invalidate() {
        invalidated = true
        events.send(())
    }
}
