//
//  AIChatElicitationCoordinator.swift
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

/// Delivers `elicitation/create` to whoever made the call. A page-backed pusher writes to the
/// bridge; the DEBUG panel answers it itself.
@MainActor
public protocol AIChatElicitationPushing: AnyObject {

    /// False when nothing can receive the prompt, so the call fails now rather than at the timeout.
    func pushElicitationCreate(_ params: MCPElicitationCreateParams) -> Bool
}

/// A prompt awaiting an answer, as exposed for diagnostics.
public struct PendingElicitation: Equatable, Sendable {
    public let id: String
    public let ownerTabID: String
    public let toolName: String
    public let message: String
}

/// Correlates a pushed prompt with the `elicitation/response` that answers it. An unanswered prompt
/// resolves as `cancel` when the timeout lapses.
@MainActor
public final class AIChatElicitationCoordinator {

    private struct Entry {
        let info: PendingElicitation
        let continuation: CheckedContinuation<MCPElicitationResult, Never>
        let timeout: Task<Void, Never>
    }

    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private let timeout: TimeInterval
    private let makeID: () -> String

    public init(timeout: TimeInterval = MCPProtocol.elicitationTimeout,
                makeID: @escaping () -> String = { UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }) {
        self.timeout = timeout
        self.makeID = makeID
    }

    public var pendingPrompts: [PendingElicitation] {
        order.compactMap { entries[$0]?.info }
    }

    public func elicit(toolName: String,
                       message: String,
                       requestedSchema: JSONValue,
                       ownerTabID: String,
                       pusher: (any AIChatElicitationPushing)?) async -> MCPElicitationResult {
        guard let pusher else { return .cancel }
        let id = makeID()
        let params = MCPElicitationCreateParams(id: id, message: message, requestedSchema: requestedSchema)
        let info = PendingElicitation(id: id, ownerTabID: ownerTabID, toolName: toolName, message: message)

        return await withCheckedContinuation { continuation in
            // Registered before the push so an answer that arrives synchronously still correlates.
            let timeoutTask = Task { [weak self, timeout] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.complete(id: id, result: .cancel)
            }
            entries[id] = Entry(info: info, continuation: continuation, timeout: timeoutTask)
            order.append(id)

            if !pusher.pushElicitationCreate(params) {
                complete(id: id, result: .cancel)
            }
        }
    }

    /// False when nothing is pending under `id` — already answered, timed out, or never issued.
    @discardableResult
    public func complete(id: String, result: MCPElicitationResult) -> Bool {
        guard let entry = entries.removeValue(forKey: id) else { return false }
        order.removeAll { $0 == id }
        entry.timeout.cancel()
        entry.continuation.resume(returning: result)
        return true
    }
}
