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
    /// Whether a failed clear may still get a late reply, which would complete the next request.
    let mayReplyLate: (Error) -> Bool

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
        for chatID in chatIDs {
            // Reloading drops the late reply, so it can't complete this chat's request.
            if needsReload, let error = await loadOrigin(origin).error {
                return errors + [error]
            }
            let error = await clear(chatID).error
            errors += [error].compactMap { $0 }
            needsReload = error.map(mayReplyLate) ?? false
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
