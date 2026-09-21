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
    private var subscriptions = Set<AnyCancellable>()
    private var pageSubscription: AnyCancellable?
    private var page: MultiTabAttachmentPage?
    private var pageIdentity: MultiTabAttachmentPage.Identity?
    private var pageURL: URL?
    private(set) var operationID = UUID()
    private var task: Task<MultiTabAttachmentCollectionResult, Never>?
    private var isCancelled = false

    init(attachment: UnifiedToggleInputTabAttachment,
         tab: Tab,
         source: MultiTabAttachmentSource,
         navigationTimeout: TimeInterval = 5,
         isEnabled: @escaping () -> Bool,
         onChange: @escaping (UnifiedToggleInputTabAttachment?) -> Void) {
        self.attachment = attachment
        self.tab = tab
        self.source = source
        self.navigationTimeout = navigationTimeout
        self.isEnabled = isEnabled
        self.onChange = onChange
        tab.addObserver(self)
        source.tabsPublisher?
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
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
        subscriptions.removeAll()
        tab.removeObserver(self)
    }

    private var isSourceValid: Bool {
        !isCancelled && tab.mode == source.mode && source.tabsProvider().contains { $0 === tab }
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
        page = nextPage
        pageIdentity = state?.identity
        pageURL = url
        pageSubscription = nextPage?.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
        startCollection()
    }

    private func isValid(operation: UUID) -> Bool {
        guard operationID == operation, isEnabled(), isSourceValid,
              let expectedURL = pageURL, let state = page?.state(),
              state.identity == pageIdentity,
              state.url?.equals(expectedURL, by: .sameDocument) == true || (state.isLoading && state.url == nil),
              !AIChatTabMetadata.shouldExcludeFromTabPicker(expectedURL) else { return false }
        return state.isLoading || state.isAttachable
    }

    private func startCollection() {
        let operation = operationID
        guard isEnabled(), let page, let state = page.state(), state.isLoaded || state.isLoading else {
            // TODO: Support unloaded tabs: https://app.asana.com/1/137249556945/project/1208671677432066/task/1218243444968029?focus=true
            task = Task { .unavailable }
            return
        }
        let timeout = navigationTimeout
        let isValid: @MainActor () -> Bool = { [weak self] in self?.isValid(operation: operation) == true }
        task = Task { @MainActor in
            guard !Task.isCancelled, isValid() else { return .cancelled }
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
            return await page.collect(url, isValid)
        }
    }

    /// Tapping send button retries extraction failure once, including failure of an operation it first awaited.
    func value() async -> AIChatPageContextData? {
        var retried = false
        while !Task.isCancelled && !isCancelled && isEnabled() {
            refresh()
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
