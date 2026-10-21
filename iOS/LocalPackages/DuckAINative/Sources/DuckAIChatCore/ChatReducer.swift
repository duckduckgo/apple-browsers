//
//  ChatReducer.swift
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

public extension ChatState {

    /// The reducer. Pure: the same state and action give the same state and effects.
    /// Out-of-phase actions are no-ops that return `[]`, so double taps, late events and a repeated `opened` converge.
    ///
    /// - `opened`: `[.prepareProvider]`; if no message was sent yet and `context.opening` exists, append the first user
    ///   message (context parts, then the request or the prompt text) and begin a reply. A second `opened` returns
    ///   `[.prepareProvider]` only.
    /// - `send`: needs `canSend` and non-empty trimmed text. The first user message also carries `context.contextParts`.
    ///   Clears `.failed`. Begins a reply.
    /// - `redo`: needs `canRedo`. Drops a trailing assistant message, clears `.failed`, begins a reply.
    /// - Begin a reply: mint the next id, build the turn with `PromptBuilder.turn`. On failure, `phase = .failed(error)`.
    ///   Otherwise `phase = .responding(live)` with stage `.waitingForModel` when not `.ready`, `.queued` when
    ///   `streamInFlight` is set, else `.starting` with `streamInFlight = id` and effect `.startReply(id, turn)`.
    /// - `stop`: only while responding. Commit the live reply as `.stopped` (dropped when empty), `phase = .idle`.
    ///   If its stream started, effect `.requestStop(id)`; `streamInFlight` stays set until `.providerEnded`.
    /// - `provider(id, event)`: ignored unless `id` is the live reply's.
    ///   `.stage(s)`: stage = `.provider(s)`. `.reasoningDelta`: extend the trailing reasoning or append one timed
    ///   `.thinking(since: at)`. `.textDelta`: close open reasoning with `.done(at - since)`, extend the trailing text or
    ///   append one. `.refusal(r)`: append it, commit `.completed(nil)`, idle. `.finished(stats)`: empty parts give
    ///   `.failed(.emptyResponse)`, otherwise commit `.completed(stats)` and idle.
    /// - `providerFailed(id, error)`: for the live reply only. Commit as `.interrupted` (dropped when empty),
    ///   `phase = .failed(error)`.
    /// - `providerEnded(id)`: if `id == streamInFlight`, clear it. A live reply with that id that saw no terminal event
    ///   is finished as `.finished(nil)`. Then a `.queued` live reply starts: `.starting`, `streamInFlight = its id`,
    ///   effect `.startReply`.
    /// - `availabilityChanged(a)`: store it. `.unsupported(r)` drops a live reply and fails with `.modelUnavailable(r)`.
    ///   `.ready` starts a `.waitingForModel` live reply (or queues it when a stream is in flight).
    /// - Committing closes open reasoning at `at` and appends `.assistant` with the live reply's id, unless parts are empty.
    mutating func apply(_ action: ChatAction) -> [ChatEffect] {
        fatalError("not implemented")
    }
}
