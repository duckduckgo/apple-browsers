//
//  DuckAIPromptAttribution.swift
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

import Foundation

/// What a Duck.ai prompt metric pixel says about where the prompt came from.
struct DuckAIPromptPixelContext: Equatable {
    /// `nil` when nothing attributes the page; sent as `unattributed`.
    let source: AIChatEntryPointSource?
    let surface: UnifiedToggleInputPixelSurface
}

/// Read when the Duck.ai page reports a prompt, which can happen off the main thread.
protocol DuckAIPromptPixelContextProviding: AnyObject {
    var minutesSincePageLoad: Int? { get }
    /// Consumes a pending address-bar hand-over, so call it once per reported prompt.
    func contextForSubmittedPrompt() -> DuckAIPromptPixelContext
}

/// The prompt attribution of the Duck.ai page loaded in one tab. The door is set once per page load:
/// any new load, including reload and back/forward, starts over, and in-page New chat keeps it.
final class DuckAIPromptAttribution: DuckAIPromptPixelContextProviding {

    private struct LoadedPage {
        let source: AIChatEntryPointSource?
        let loadedAt: Date
    }

    /// A hand-over belongs to the page it is delivered to and lapses when another page loads.
    private enum AddressBarHandover {
        case none
        case awaitingPage
        case onPage
    }

    private let lock = NSLock()
    private let dateProvider: () -> Date
    private var loadedPage: LoadedPage?
    private var addressBarHandover = AddressBarHandover.none

    init(dateProvider: @escaping () -> Date = Date.init) {
        self.dateProvider = dateProvider
    }

    func pageDidCommit(isDuckAI: Bool, entrySource: AIChatEntryPointSource?) {
        lock.withLock {
            loadedPage = isDuckAI ? LoadedPage(source: entrySource, loadedAt: dateProvider()) : nil
            addressBarHandover = isDuckAI && addressBarHandover == .awaitingPage ? .onPage : .none
        }
    }

    /// The address bar is about to hand a prompt to this tab's Duck.ai page, which reports it as its next prompt.
    func addressBarWillHandOverPrompt() {
        lock.withLock { addressBarHandover = .awaitingPage }
    }

    var minutesSincePageLoad: Int? {
        lock.withLock { loadedPage.map { Int(dateProvider().timeIntervalSince($0.loadedAt) / 60) } }
    }

    func contextForSubmittedPrompt() -> DuckAIPromptPixelContext {
        lock.withLock {
            let surface: UnifiedToggleInputPixelSurface = addressBarHandover == .none ? .duckAI : .addressBar
            addressBarHandover = .none
            return DuckAIPromptPixelContext(source: loadedPage?.source, surface: surface)
        }
    }
}

/// Every prompt in the Ask about page sheet, typed natively or in the sheet's page.
final class ContextualChatPromptPixelContext: DuckAIPromptPixelContextProviding {

    let minutesSincePageLoad: Int? = nil

    func contextForSubmittedPrompt() -> DuckAIPromptPixelContext {
        DuckAIPromptPixelContext(source: .contextualChat, surface: .contextualChat)
    }
}
