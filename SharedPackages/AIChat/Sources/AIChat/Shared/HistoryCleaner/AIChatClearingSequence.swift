//
//  AIChatClearingSequence.swift
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

/// Clears every origin, and every requested chat, even when an earlier step fails,
/// so one failure doesn't leave the rest of the user's Duck.ai data behind.
@MainActor
struct AIChatClearingSequence {

    let origins: [URL]
    let loadOrigin: @MainActor (URL) async -> Result<Void, Error>
    /// Clears one chat, or everything when `chatID` is `nil`, on the currently loaded origin.
    let clear: @MainActor (_ chatID: String?) async -> Result<Void, Error>
    /// Whether the page must be reloaded after this failed clear, before clearing the next chat.
    let requiresReload: (Error) -> Bool

    /// An origin that left this many chats in a row unanswered won't answer the rest, so waiting on each would only add timeouts.
    private static let unansweredChatsBeforeSkippingOrigin = 2

    /// - Returns: `.success` only if every step succeeded; otherwise the first failure.
    func run(chatIDs: [String]?) async -> Result<Void, Error> {
        var errors: [Error] = []
        for origin in origins {
            errors += await clearOrigin(origin, chatIDs: chatIDs)
        }
        return errors.first.map { .failure($0) } ?? .success(())
    }

    private func clearOrigin(_ origin: URL, chatIDs: [String]?) async -> [Error] {
        if let error = await loadOrigin(origin).error {
            return [error]
        }

        guard let chatIDs else {
            return [await clear(nil).error].compactMap { $0 }
        }

        var errors: [Error] = []
        var needsReload = false
        var unansweredInARow = 0
        for chatID in chatIDs {
            if needsReload, let error = await loadOrigin(origin).error {
                return errors + [error]
            }
            let error = await clear(chatID).error
            errors += [error].compactMap { $0 }
            needsReload = error.map(requiresReload) ?? false
            unansweredInARow = needsReload ? unansweredInARow + 1 : 0
            if unansweredInARow == Self.unansweredChatsBeforeSkippingOrigin {
                return errors
            }
        }
        return errors
    }
}

private extension Result {
    var error: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
