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
    /// - `availabilityChanged(a)`: store it. `.unsupported(r)` drops a live reply, fails with `.modelUnavailable(r)`, and
    ///   asks its stream to stop if it started.
    ///   `.ready` starts a `.waitingForModel` live reply (or queues it when a stream is in flight).
    /// - Committing closes open reasoning at `at` and appends `.assistant` with the live reply's id, unless parts are empty.
    mutating func apply(_ action: ChatAction) -> [ChatEffect] {
        let replyAt: Date
        var effects: [ChatEffect] = []
        switch action {
        case .rejected(let error):
            phase = .failed(error)
            return []
        case .opened(let at):
            effects = [.prepareProvider]
            guard messages.isEmpty, let opening = context.opening else { return effects }
            var parts = context.contextParts.map(UserPart.context) + context.attachments.map(UserPart.attachment)
            switch opening {
            case .prompt(let text): parts.append(.text(text))
            case .request: break
            }
            lastID += 1
            messages.append(.user(UserMessage(id: MessageID(rawValue: lastID), createdAt: at, parts: parts)))
            replyAt = at
        case .send(let text, let attachments, let at):
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard canSend, !text.isEmpty || !attachments.isEmpty else { return [] }
            let parts = messages.isEmpty ? context.contextParts.map(UserPart.context) : []
            lastID += 1
            messages.append(.user(UserMessage(id: MessageID(rawValue: lastID), createdAt: at, parts: parts + attachments.map(UserPart.attachment) + [.text(text)])))
            replyAt = at
        case .redo(let at):
            guard canRedo else { return [] }
            if case .assistant = messages.last { messages.removeLast() }
            replyAt = at
        case .stop(let at):
            guard let live = liveReply else { return [] }
            messages += committedReply(live, ending: .stopped, at: at)
            phase = .idle
            return streamInFlight == live.id ? [.requestStop(live.id)] : []
        case .provider(let id, let event, let at):
            guard let live = liveReply, live.id == id else { return [] }
            let updated = updatedReply(live, event: event, at: at)
            switch event {
            case .refusal:
                messages += committedReply(updated, ending: .completed(nil), at: at)
                phase = .idle
            case .finished(let stats):
                messages += committedReply(updated, ending: .completed(stats), at: at)
                phase = updated.parts.isEmpty ? .failed(.emptyResponse) : .idle
            default:
                phase = .responding(updated)
            }
            return []
        case .providerFailed(let id, let error, let at):
            guard let live = liveReply, live.id == id else { return [] }
            messages += committedReply(live, ending: .interrupted, at: at)
            phase = .failed(error)
            return []
        case .providerEnded(let id, let at):
            streamInFlight = streamInFlight == id ? nil : streamInFlight
            _ = apply(.provider(id, .finished(nil), at: at))
            guard streamInFlight == nil, var live = liveReply, live.stage == .queued else { return [] }
            live.stage = .starting
            phase = .responding(live)
            streamInFlight = live.id
            return [.startReply(live.id, live.turn)]
        case .availabilityChanged(let availability):
            self.availability = availability
            switch availability {
            case .unsupported(let reason):
                guard let live = liveReply else { return [] }
                phase = .failed(.modelUnavailable(reason: reason))
                return streamInFlight == live.id ? [.requestStop(live.id)] : []
            case .ready:
                guard let live = liveReply, live.stage == .waitingForModel else { return [] }
                let scheduled = scheduledReply(live, availability: availability, streamInFlight: streamInFlight)
                phase = .responding(scheduled.live)
                streamInFlight = scheduled.stream
                return scheduled.effects
            default:
                break
            }
            return []
        }

        return effects + beginReply(at: replyAt)
    }

    private mutating func beginReply(at date: Date) -> [ChatEffect] {
        lastID += 1
        let id = MessageID(rawValue: lastID)
        if case .unsupported(let reason) = availability {
            phase = .failed(.modelUnavailable(reason: reason))
            return []
        }
        switch PromptBuilder.turn(conversation: conversation, messages: messages, budget: budget) {
        case .failure(let error):
            phase = .failed(error)
            return []
        case .success(let turn):
            let live = LiveReply(id: id, startedAt: date, turn: turn, stage: .waitingForModel)
            let scheduled = scheduledReply(live, availability: availability, streamInFlight: streamInFlight)
            phase = .responding(scheduled.live)
            streamInFlight = scheduled.stream
            return scheduled.effects
        }
    }
}

private func closingReasoning(_ parts: [AssistantPart], at: Date) -> [AssistantPart] {
    parts.map { part in
        guard case .reasoning(var reasoning) = part, case .thinking(let since) = reasoning.timing else { return part }
        reasoning.timing = .done(.seconds(at.timeIntervalSince(since)))
        return .reasoning(reasoning)
    }
}

private func committedReply(_ live: LiveReply, ending: ReplyEnding, at: Date) -> [Message] {
    guard !live.parts.isEmpty else { return [] }
    return [.assistant(AssistantMessage(id: live.id, createdAt: live.startedAt,
                                        parts: closingReasoning(live.parts, at: at), ending: ending))]
}

private func updatedReply(_ live: LiveReply, event: ProviderEvent, at: Date) -> LiveReply {
    var live = live
    switch event {
    case .stage(let stage):
        live.stage = .provider(stage)
    case .reasoningDelta(let text):
        if case .reasoning(var reasoning) = live.parts.last {
            reasoning.text += text
            live.parts[live.parts.count - 1] = .reasoning(reasoning)
        } else {
            live.parts.append(.reasoning(Reasoning(text: text, timing: .thinking(since: at))))
        }
    case .textDelta(let text):
        live.parts = closingReasoning(live.parts, at: at)
        if case .text(let previous) = live.parts.last {
            live.parts[live.parts.count - 1] = .text(previous + text)
        } else {
            live.parts.append(.text(text))
        }
    case .refusal(let refusal):
        live.parts.append(.refusal(refusal))
    case .finished:
        break
    }
    return live
}

private func scheduledReply(_ live: LiveReply, availability: ProviderAvailability,
                            streamInFlight: MessageID?) -> (live: LiveReply, stream: MessageID?, effects: [ChatEffect]) {
    var live = live
    live.stage = availability != .ready ? .waitingForModel : (streamInFlight == nil ? .starting : .queued)
    guard live.stage == .starting else { return (live, streamInFlight, []) }
    return (live, live.id, [.startReply(live.id, live.turn)])
}
