//
//  MultiTabAttachmentPreparation.swift
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
import Common
import Foundation

/// Owned by one draft attachment, then by its submitted message.
@MainActor
final class MultiTabAttachmentPreparation: TabObserver {
    let tab: Tab
    private(set) var attachment: UnifiedToggleInputTabAttachment
    private let source: MultiTabAttachmentSource
    private let isEnabled: () -> Bool
    private let onChange: (UnifiedToggleInputTabAttachment?) -> Void
    private let navigationTimeout: TimeInterval
    private let now: () -> TimeInterval
    private var navigationDeadline: TimeInterval?
    private var pageReservation: MultiTabAttachmentPage.Reservation?
    private var subscriptions = Set<AnyCancellable>()
    private var pageSubscription: AnyCancellable?
    private var processTerminationSubscription: AnyCancellable?
    private var page: MultiTabAttachmentPage?
    private var pageIdentity: MultiTabAttachmentPage.Identity?
    private var pageURL: URL?
    private(set) var operationID = UUID()
    private var task: Task<MultiTabAttachmentCollectionResult, Never>?
    private var isCancelled = false
    private var requiresProcessRecovery = false

    init(attachment: UnifiedToggleInputTabAttachment,
         tab: Tab,
         source: MultiTabAttachmentSource,
         navigationTimeout: TimeInterval = 5,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         isEnabled: @escaping () -> Bool,
         onChange: @escaping (UnifiedToggleInputTabAttachment?) -> Void) {
        self.attachment = attachment
        self.tab = tab
        self.source = source
        self.navigationTimeout = navigationTimeout
        self.now = now
        self.isEnabled = isEnabled
        self.onChange = onChange
        tab.addObserver(self)
        source.tabsPublisher?
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        if isEnabled(), isSourceValid, let url = tab.link?.url,
           !AIChatTabMetadata.shouldExcludeFromTabPicker(url) {
            navigationDeadline = now() + navigationTimeout
            pageReservation = source.acquirePage(tab)
        }
        refresh()
    }

    deinit {
        task?.cancel()
    }

    nonisolated func didChange(tab: Tab) {
        Task { @MainActor [weak self] in self?.refresh() }
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        operationID = UUID()
        task?.cancel()
        task = nil
        page = nil
        pageSubscription = nil
        processTerminationSubscription = nil
        subscriptions.removeAll()
        tab.removeObserver(self)
        pageReservation?.release()
        pageReservation = nil
    }

    private var isSourceValid: Bool {
        !isCancelled && tab.mode == source.mode && source.tabsProvider().contains { $0 === tab }
    }

    /// Once a message has received valid context, eligible navigation must not discard it while other tabs finish.
    var canDeliverPreparedContext: Bool {
        guard isEnabled(), isSourceValid, let link = tab.link,
              !AIChatTabMetadata.shouldExcludeFromTabPicker(link.url) else { return false }
        let state = source.pageProvider(tab)?.state()
        if let state, !state.isLoading, !state.isAttachable {
            return false
        }
        return !AIChatTabMetadata.shouldExcludeFromTabPicker(state?.url ?? link.url)
    }

    func refresh() {
        guard !isCancelled else { return }
        guard isSourceValid, let link = tab.link,
              !AIChatTabMetadata.shouldExcludeFromTabPicker(link.url) else {
            cancel()
            onChange(nil)
            return
        }
        let nextPage = source.pageProvider(tab)
        let state = nextPage?.state()
        if state?.hasTerminatedProcess == true, !requiresProcessRecovery {
            invalidateTerminatedPage()
        }
        if let state, !state.isLoading, !state.isAttachable {
            cancel()
            onChange(nil)
            return
        }
        let url = state?.url ?? link.url
        guard !AIChatTabMetadata.shouldExcludeFromTabPicker(url) else {
            cancel()
            onChange(nil)
            return
        }
        if requiresProcessRecovery, let state, !state.hasTerminatedProcess, isEnabled() {
            // Ordinary browsing may restore the page before Send. Resume with fresh protection and a new navigation budget.
            requiresProcessRecovery = false
            navigationDeadline = now() + navigationTimeout
            replacePageReservation()
        }
        let updated = UnifiedToggleInputTabAttachment(id: attachment.id, tabId: tab.uid,
                                                       title: link.displayTitle, url: url,
                                                       favicon: url.host == attachment.url.host ? attachment.favicon : nil)
        if updated != attachment {
            attachment = updated
            onChange(updated)
        }
        let samePage = pageIdentity == state?.identity && pageURL?.equals(url, by: .sameDocument) == true
        guard !samePage || task == nil else { return }
        task?.cancel()
        operationID = UUID()
        pageIdentity = state?.identity
        pageURL = url
        observePage(nextPage)
        startCollection()
    }

    private func observePage(_ nextPage: MultiTabAttachmentPage?) {
        page = nextPage
        pageSubscription = nextPage?.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
        processTerminationSubscription = nextPage?.processTerminations
            .sink { [weak self] in self?.invalidateTerminatedPage() }
    }

    private func invalidateTerminatedPage() {
        guard !isCancelled else { return }
        requiresProcessRecovery = true
        navigationDeadline = nil
        operationID = UUID()
        task?.cancel()
        task = nil
    }

    private func replacePageReservation() {
        let previous = pageReservation
        pageReservation = source.acquirePage(tab)
        previous?.release()
    }

    private func recoverPageAtSend() {
        guard isEnabled(), isSourceValid else { return }
        requiresProcessRecovery = false
        navigationDeadline = now() + navigationTimeout
        replacePageReservation()
        guard isEnabled(), isSourceValid else { return }
        task?.cancel()
        task = nil
        observePage(source.pageProvider(tab))
        page?.loadIfNeeded()
        refresh()
    }

    private func isValid(operation: UUID) -> Bool {
        guard operationID == operation, isEnabled(), isSourceValid,
              let expectedURL = pageURL, let state = page?.state(),
              state.identity == pageIdentity, !state.hasTerminatedProcess,
              state.url?.equals(expectedURL, by: .sameDocument) == true || (state.isLoading && state.url == nil),
              !AIChatTabMetadata.shouldExcludeFromTabPicker(expectedURL) else { return false }
        return state.isLoading || state.isAttachable
    }

    private func startCollection() {
        let operation = operationID
        guard isEnabled(), isSourceValid, !requiresProcessRecovery,
              let page, page.state()?.hasTerminatedProcess == false else {
            task = Task { .unavailable }
            return
        }
        if navigationDeadline == nil {
            navigationDeadline = now() + navigationTimeout
        }
        let deadline = navigationDeadline ?? now()
        guard deadline > now() else {
            task = Task { .timedOut }
            return
        }
        // refresh() has already subscribed to page changes so a restored-page reload cannot emit changes before we subscribe.
        page.loadIfNeeded()
        guard let state = page.state(), state.isLoaded || state.isLoading else {
            task = Task { .unavailable }
            return
        }
        let now = self.now
        let isValid: @MainActor () -> Bool = { [weak self] in self?.isValid(operation: operation) == true }
        task = Task { @MainActor [weak self] in
            guard !Task.isCancelled, isValid() else { return .cancelled }
            let timeout = max(0, deadline - now())
            guard timeout > 0 else { return .timedOut }
            if state.isLoading {
                let finished = page.changes.prepend(())
                    .filter { !isValid() || page.state()?.isLoading != true }
                    .eraseToAnyPublisher()
                switch await MultiTabAttachmentWaiter.firstValue(from: finished, timeout: timeout) {
                case .timedOut: return .timedOut
                case .cancelled: return .cancelled
                case .finished: return .unavailable
                case .value: break
                }
            }
            guard !Task.isCancelled, isValid(), let ready = page.state(),
                  ready.isLoaded, !ready.isLoading, ready.isAttachable, let url = ready.url else { return .unavailable }
            self?.navigationDeadline = nil
            return await page.collect(url, isValid)
        }
    }

    /// Extraction failures and process recovery share one retry at Send.
    func value() async -> AIChatPageContextData? {
        var retried = false
        while !Task.isCancelled && !isCancelled && isEnabled() {
            refresh()
            if requiresProcessRecovery {
                guard !retried else { return nil }
                retried = true
                recoverPageAtSend()
            }
            let operation = operationID
            let pending = task
            let result: MultiTabAttachmentCollectionResult = await withTaskCancellationHandler(
                operation: {
                    guard let pending else {
                        return .unavailable
                    }

                    return await pending.value
                },
                onCancel: {
                    pending?.cancel()
                }
            )
            guard !Task.isCancelled, !isCancelled, isEnabled() else { return nil }
            refresh()
            guard operation == operationID else { continue }
            switch result {
            case .collected(let context):
                return validated(context)
            case .failed, .timedOut:
                guard !retried else { return nil }
                retried = true
                navigationDeadline = nil
                startCollection()
            default:
                return nil
            }
        }
        return nil
    }

    func validated(_ context: AIChatPageContextData) -> AIChatPageContextData? {
        guard isValid(operation: operationID), let state = page?.state(),
              !state.isLoading, state.isLoaded, state.isAttachable,
              let url = URL(string: context.url), let pageURL, url.equals(pageURL, by: .sameDocument),
              tab.link?.url.equals(url, by: .sameDocument) == true,
              context.hasAttachedPage, context.attachable != false else { return nil }
        return context.withTabId(tab.uid)
    }
}
