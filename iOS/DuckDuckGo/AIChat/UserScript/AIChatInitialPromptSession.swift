//
//  AIChatInitialPromptSession.swift
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

/// Owns the initial attachment prompt independently of the tab's replaceable script.
@MainActor
final class AIChatInitialPromptSession {
    enum PromptSource {
        case sharedHandler
        case tabSession(AIChatNativePrompt?)
    }

    /// A replaceable bridge connection. Retaining an old handler never extends its access to the session.
    @MainActor
    final class Connection {
        private weak var session: AIChatInitialPromptSession?
        private let id: UUID

        fileprivate init(session: AIChatInitialPromptSession, id: UUID) {
            self.session = session
            self.id = id
        }

        private var currentSession: AIChatInitialPromptSession? {
            guard session?.connectionID == id else { return nil }
            return session
        }

        func isConnected(to session: AIChatInitialPromptSession) -> Bool {
            currentSession === session
        }

        func consumeInitialPrompt() -> PromptSource {
            currentSession?.consumeInitialPrompt() ?? .tabSession(nil)
        }

        func captureInitialPromptWait() -> (@MainActor () async -> Bool)? {
            guard let session = currentSession else { return { false } }
            guard let delivery = session.delivery else { return nil }
            return { [weak self, weak session] in
                guard self?.currentSession != nil else { return false }
                let result = await delivery.waitUntilConsumed()
                guard self?.currentSession != nil else { return false }
                if result == .timedOut, session?.delivery === delivery {
                    session?.delivery = nil
                }
                return result != .cancelled
            }
        }

        func cancel() {
            currentSession?.cancel()
        }

        func disconnect() {
            currentSession?.connectionID = nil
        }
    }

    private var preparation: AIChatInitialPromptPreparation?
    private var preparationID: UUID?
    private var delivery: AIChatInitialPromptDelivery?
    private var usesTabSessionInitialPrompt = false
    private var awaitsNavigation = false
    private var hasFailedNavigation = false
    private var navigation: (any WebViewNavigation & AnyObject)?
    private var connectionID: UUID?

    deinit {
        let preparation = preparation
        let delivery = delivery
        Task { @MainActor in
            preparation?.cancel()
            delivery?.cancel()
        }
    }

    var isProtectedFromCacheEviction: Bool {
        preparation != nil || delivery?.protectsRecipientFromEviction == true
    }

    func prepare(_ prompt: AIChatNativePrompt, request: MultiTabAttachmentRequest,
                 completion: @escaping (AIChatInitialPromptDelivery?) -> Void) {
        guard preparation == nil else {
            request.cancel()
            completion(nil)
            return
        }
        let id = UUID()
        preparationID = id
        preparation = AIChatInitialPromptPreparation(prompt: prompt, request: request) { [weak self] delivery in
            if self?.preparationID == id {
                self?.preparation = nil
                self?.preparationID = nil
            }
            completion(delivery)
        }
    }

    func install(_ delivery: AIChatInitialPromptDelivery) {
        cancel()
        usesTabSessionInitialPrompt = true
        awaitsNavigation = true
        self.delivery = delivery
    }

    func connect() -> Connection {
        let id = UUID()
        connectionID = id
        return Connection(session: self, id: id)
    }

    func consumeInitialPrompt() -> PromptSource {
        guard usesTabSessionInitialPrompt else { return .sharedHandler }
        let delivery = delivery
        self.delivery = nil
        hasFailedNavigation = false
        return .tabSession(delivery?.consume())
    }

    func cancel() {
        let preparation = preparation
        self.preparation = nil
        preparationID = nil
        delivery?.cancel()
        delivery = nil
        awaitsNavigation = false
        hasFailedNavigation = false
        preparation?.cancel()
    }

    /// Returns whether the script's pending submissions must also be cancelled.
    @discardableResult
    func willLoad(isInternalRetry: Bool) -> Bool {
        if isInternalRetry, delivery?.hasPendingPrompt == true {
            awaitsNavigation = true
            return false
        }
        cancel()
        return true
    }

    @discardableResult
    func willRetryFailedNavigation() -> Bool {
        guard hasFailedNavigation, delivery?.hasPendingPrompt == true else { return false }
        awaitsNavigation = true
        return true
    }

    @discardableResult
    func didStartNavigation(_ navigation: (any WebViewNavigation & AnyObject)?) -> Bool {
        let shouldCancel = !awaitsNavigation
        if shouldCancel {
            cancel()
            usesTabSessionInitialPrompt = false
        }
        awaitsNavigation = false
        hasFailedNavigation = false
        self.navigation = navigation
        return shouldCancel
    }

    @discardableResult
    func didFailNavigation(_ navigation: (any WebViewNavigation & AnyObject)?) -> Bool {
        guard let navigation, self.navigation === navigation, !awaitsNavigation else { return false }
        if delivery?.hasPendingPrompt == true {
            hasFailedNavigation = true
        } else {
            cancel()
        }
        return true
    }
}
