//
//  PendingRepliesActor.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// An actor that serializes access to the pending‐replies queue.
actor PendingRepliesActor {
    typealias MessageReplyHandler = (String?) -> Void

    private var pendingReplies = [String: [MessageReplyHandler]]()

    /// Register a new reply handler for `messageType`, cancelling any existing ones for the same message type
    func register(_ handler: @escaping MessageReplyHandler, for messageType: String) {
        var replies = pendingReplies[messageType] ?? []

        if !replies.isEmpty {
            let toCancel = replies
            replies.removeAll()
            Task { @MainActor in
                for previous in toCancel {
                    previous(AutofillUserScript.NoActionResponse.successJSONString)
                }
            }
        }

        replies.append(handler)
        pendingReplies[messageType] = replies
    }

    /// Send a reply for the first handler registered under `messageType`.
    func send(response: String?, for messageType: String) {
        guard var replies = pendingReplies[messageType], let first = replies.first else {
            return
        }

        replies.removeFirst()
        pendingReplies[messageType] = replies

        Task { @MainActor in
            first(response)
        }
    }

    /// Cancel all pending replies, clearing the entire queue.
    func cancelAll() {
        let all = pendingReplies.values.flatMap { $0 }
        pendingReplies.removeAll()
        Task { @MainActor in
            for reply in all {
                reply(AutofillUserScript.NoActionResponse.successJSONString)
            }
        }
    }
}
