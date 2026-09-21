//
//  MultiTabAttachmentContext.swift
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
import Foundation

/// Applies source and feature policy before preparation and at message delivery.
@MainActor
final class MultiTabAttachmentContext {
    private let feature: AIChatContextualAttachMoreTabsFeatureProviding
    private let source: MultiTabAttachmentSource?

    init(source: MultiTabAttachmentSource? = nil, feature: AIChatContextualAttachMoreTabsFeatureProviding) {
        self.source = source
        self.feature = feature
    }

    private var isEnabled: Bool {
        if case .available = feature.state { return true }
        return false
    }

    func prepare(_ attachment: UnifiedToggleInputTabAttachment,
                 onChange: @escaping (UnifiedToggleInputTabAttachment?) -> Void) -> MultiTabAttachmentPreparation? {
        guard isEnabled, let source, attachment.tabId != source.currentTabID,
              let tab = source.tabsProvider().first(where: { $0.uid == attachment.tabId && $0.mode == source.mode }) else { return nil }
        return MultiTabAttachmentPreparation(attachment: attachment, tab: tab, source: source,
                                             isEnabled: { [feature] in
                                                 if case .available = feature.state { return true }
                                                 return false
                                             }, onChange: onChange)
    }

    func makeRequest(preparations: [MultiTabAttachmentPreparation]) -> MultiTabAttachmentRequest? {
        guard !preparations.isEmpty else { return nil }
        return makeRequest {
            MultiTabAttachmentRequest(contexts: {
                var results: [AIChatPageContextData] = []
                for preparation in preparations {
                    guard !Task.isCancelled else { return [] }
                    if let context = await preparation.value() {
                        results.append(context)
                    }
                }
                return results
            }, didConsume: {
                preparations.forEach { $0.cancel() }
            }, cancel: {
                preparations.forEach { $0.cancel() }
            }, validate: { contexts in
                contexts.filter { context in
                    preparations.first(where: { $0.tab.uid == context.tabId })?.canDeliverPreparedContext == true
                }
            })
        }
    }

    func makeRequest(using provider: () -> MultiTabAttachmentRequest?) -> MultiTabAttachmentRequest? {
        guard isEnabled, let request = provider() else { return nil }
        return MultiTabAttachmentRequest(contexts: { [feature] in
            guard case .available = feature.state else { return [] }
            let contexts = await request.contexts()
            guard !Task.isCancelled, case .available = feature.state else { return [] }
            return request.validate(contexts)
        }, didConsume: { [feature] in
            guard case .available = feature.state else { return }
            request.didConsume()
        }, cancel: request.cancel, validate: { [feature] contexts in
            guard case .available = feature.state else { return [] }
            return request.validate(contexts)
        })
    }
}
