//
//  ClientToolPermissionCoordinator.swift
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

/// The browser's own permission prompt for one chat. The web page never sees or answers it.
@MainActor
public protocol ClientToolPermissionPrompting: AnyObject {
    /// Shows the prompt; the answer comes back through `ClientToolPermissionCoordinator.respond`,
    /// possibly synchronously. Returns false when it cannot be shown, which cancels the call.
    func presentClientToolPermissionPrompt(_ prompt: ClientToolPermissionPrompt) -> Bool

    /// Closes a prompt whose call finished without an answer: deadline, chat gone or cancelled.
    func withdrawClientToolPermissionPrompt(requestID: String)
}

public struct ClientToolPermissionPrompt: Equatable, Sendable {
    public let requestID: String
    public let callID: String
    public let toolName: String
}

/// Allow once · Always · Never, or the prompt closed without a choice. A prompt left unanswered until
/// the deadline is denied for that call, as Duck.ai asks again after `cancelled`.
public enum ClientToolPermissionDecision: Equatable, Sendable {
    case allowOnce
    case always
    case never
    case dismiss
}

@MainActor
public protocol ClientToolPermissionCoordinating: AnyObject {
    func authorize(callID: String, tool: any BrowserTool, prompter: (any ClientToolPermissionPrompting)?) async -> ClientToolPermissionAuthorization
}

public enum ClientToolPermissionAuthorization {
    case granted(performExecution: @MainActor (@escaping @MainActor () async -> BrowserToolResult) async -> BrowserToolResult?)
    case refused(ClientToolError)
}

@MainActor
public final class ClientToolPermissionCoordinator: ClientToolPermissionCoordinating {
    /// Shorter than Duck.ai's 150 s `executeClientTool` deadline, which ignores later replies, so the
    /// call is settled while Duck.ai still waits for it.
    private static let permissionTimeout: TimeInterval = 120

    private enum State {
        case queued
        case awaitingDecision
        case granted
        case executing
    }

    private final class Entry {
        let requestID: String
        let callID: String
        let tool: any BrowserTool
        weak var prompter: (any ClientToolPermissionPrompting)?
        let requiresPrompter: Bool
        let deadline: TimeInterval
        let cancellation: ClientToolCancellationSignal
        var state: State = .queued
        var continuation: CheckedContinuation<ClientToolPermissionAuthorization, Never>?
        var executionContinuation: CheckedContinuation<BrowserToolResult?, Never>?
        var executionTask: Task<Void, Never>?
        var timeout: Task<Void, Never>?

        init(requestID: String, callID: String, tool: any BrowserTool,
             prompter: (any ClientToolPermissionPrompting)?, deadline: TimeInterval,
             cancellation: ClientToolCancellationSignal, continuation: CheckedContinuation<ClientToolPermissionAuthorization, Never>) {
            self.requestID = requestID
            self.callID = callID
            self.tool = tool
            self.prompter = prompter
            requiresPrompter = prompter != nil
            self.deadline = deadline
            self.cancellation = cancellation
            self.continuation = continuation
        }

        var isCancelled: Bool {
            cancellation.isCancelled || (requiresPrompter && prompter == nil)
        }
    }

    private let permissions: BrowserToolPermissionStoring
    private let now: () -> TimeInterval
    private let sleepUntil: (TimeInterval) async throws -> Void
    private var entries: [String: Entry] = [:]
    /// One prompt per tool at a time, across chats, keyed by tool name.
    private var queues: [String: [String]] = [:]
    private var queueKeysPendingProcessing: Set<String> = []
    private var isProcessingPermissionQueues = false
    private var isCancellingPrompter = false

    public convenience init(permissions: BrowserToolPermissionStoring) {
        self.init(permissions: permissions,
                  now: { ProcessInfo.processInfo.systemUptime },
                  sleepUntil: { deadline in
                      let remaining = max(0, deadline - ProcessInfo.processInfo.systemUptime)
                      try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                  })
    }

    init(permissions: BrowserToolPermissionStoring,
         now: @escaping () -> TimeInterval,
         sleepUntil: @escaping (TimeInterval) async throws -> Void) {
        self.permissions = permissions
        self.now = now
        self.sleepUntil = sleepUntil
    }

    /// Queues the call and awaits authorization from a stored decision or user response.
    /// `grant` or `finish` resumes the continuation, returning its result from this method.
    /// Queue time counts toward the permission timeout.
    /// Task cancellation marks the request immediately, then schedules MainActor cleanup
    /// to remove it and resume any pending wait as `.refused(.cancelled)`.
    public func authorize(callID: String, tool: any BrowserTool, prompter: (any ClientToolPermissionPrompting)?) async -> ClientToolPermissionAuthorization {
        let cancellation = ClientToolCancellationSignal()
        let requestID = UUID().uuidString
        let deadline = now() + Self.permissionTimeout
        return await withTaskCancellationHandler {
            guard !Task.isCancelled, !cancellation.isCancelled else { return .refused(.cancelled) }
            return await withCheckedContinuation { continuation in
                let entry = Entry(requestID: requestID, callID: callID, tool: tool, prompter: prompter,
                                  deadline: deadline, cancellation: cancellation, continuation: continuation)
                entries[requestID] = entry
                queues[tool.name, default: []].append(requestID)
                entry.timeout = Task { [weak self, sleepUntil] in
                    do {
                        try await sleepUntil(deadline)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    self?.expire(requestID)
                }
                processPermissionQueue(for: tool.name)
            }
        } onCancel: {
            cancellation.cancel()
            Task { @MainActor [weak self] in
                self?.finish(requestID, error: .cancelled)
            }
        }
    }

    /// The user's answer to a prompt shown by `prompter`. Answers for another prompter, call or a
    /// prompt that is no longer shown are ignored.
    public func respond(to prompt: ClientToolPermissionPrompt, decision: ClientToolPermissionDecision,
                        from prompter: any ClientToolPermissionPrompting) {
        defer { processPendingPermissionQueues() }
        guard let entry = entries[prompt.requestID],
              case .awaitingDecision = entry.state,
              entry.callID == prompt.callID, entry.prompter === prompter else {
            return
        }
        guard !entry.isCancelled else {
            finish(entry.requestID, error: .cancelled, withdrawingPrompt: false)
            return
        }
        guard now() < entry.deadline else {
            finish(entry.requestID, error: .denied, withdrawingPrompt: false)
            return
        }
        switch decision {
        case .always:
            permissions.setState(.allow, forToolNamed: entry.tool.name)
            grant(entry)
        case .allowOnce:
            grant(entry)
        case .never:
            permissions.setState(.deny, forToolNamed: entry.tool.name)
            finish(entry.requestID, error: .denied, withdrawingPrompt: false)
        case .dismiss:
            finish(entry.requestID, error: .cancelled, withdrawingPrompt: false)
        }
    }

    public func cancelRequests(from prompter: any ClientToolPermissionPrompting) {
        let matching = entries.values.filter { $0.prompter === prompter }
        isCancellingPrompter = true
        for entry in matching {
            entry.cancellation.cancel()
            finish(entry.requestID, error: .cancelled)
        }
        isCancellingPrompter = false
        processPendingPermissionQueues()
    }

    private func performExecution(requestID: String,
                                  operation: @escaping @MainActor () async -> BrowserToolResult) async -> BrowserToolResult? {
        guard let entry = entries[requestID], case .granted = entry.state,
              !Task.isCancelled, !entry.isCancelled else {
            finish(requestID, error: .cancelled)
            return nil
        }
        entry.state = .executing
        let cancellation = entry.cancellation
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard entries[requestID] === entry, !entry.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                entry.executionContinuation = continuation
                entry.executionTask = Task { [weak self] in
                    let result = await operation()
                    self?.completeExecution(requestID, result: result)
                }
            }
        } onCancel: {
            cancellation.cancel()
            Task { @MainActor [weak self] in
                self?.finish(requestID, error: .cancelled)
            }
        }
    }

    private func completeExecution(_ requestID: String, result: BrowserToolResult) {
        guard let entry = entries.removeValue(forKey: requestID) else { return }
        entry.executionTask = nil
        let continuation = entry.executionContinuation
        entry.executionContinuation = nil
        continuation?.resume(returning: entry.isCancelled ? nil : result)
    }

    private func expire(_ requestID: String) {
        guard let entry = entries[requestID] else { return }
        if case .granted = entry.state { return }
        if case .executing = entry.state { return }
        guard now() >= entry.deadline else { return }
        finish(requestID, error: .denied)
    }

    private func grant(_ entry: Entry) {
        guard entries[entry.requestID] === entry else { return }
        entry.state = .granted
        releaseQueue(entry)
        let continuation = entry.continuation
        entry.continuation = nil
        let requestID = entry.requestID
        continuation?.resume(returning: .granted(performExecution: { [weak self] operation in
            await self?.performExecution(requestID: requestID, operation: operation)
        }))
        processPendingPermissionQueues()
    }

    /// - Parameter withdrawingPrompt: false when the prompt is already gone: answered or never shown.
    private func finish(_ requestID: String, error: ClientToolError, withdrawingPrompt: Bool = true) {
        guard let entry = entries.removeValue(forKey: requestID) else { return }
        if withdrawingPrompt, case .awaitingDecision = entry.state {
            entry.prompter?.withdrawClientToolPermissionPrompt(requestID: requestID)
        }
        entry.executionTask?.cancel()
        entry.executionTask = nil
        let executionContinuation = entry.executionContinuation
        entry.executionContinuation = nil
        releaseQueue(entry)
        let continuation = entry.continuation
        entry.continuation = nil
        continuation?.resume(returning: .refused(error))
        executionContinuation?.resume(returning: nil)
        processPendingPermissionQueues()
    }

    private func releaseQueue(_ entry: Entry) {
        entry.timeout?.cancel()
        entry.timeout = nil
        let queueKey = entry.tool.name
        queues[queueKey]?.removeAll { $0 == entry.requestID }
        if queues[queueKey]?.isEmpty == true {
            queues.removeValue(forKey: queueKey)
        }
        queueKeysPendingProcessing.insert(queueKey)
    }

    private func processPermissionQueue(for queueKey: String) {
        queueKeysPendingProcessing.insert(queueKey)
        processPendingPermissionQueues()
    }

    private func processPendingPermissionQueues() {
        guard !isProcessingPermissionQueues, !isCancellingPrompter else { return }
        isProcessingPermissionQueues = true
        defer { isProcessingPermissionQueues = false }
        while let queueKey = queueKeysPendingProcessing.first {
            queueKeysPendingProcessing.remove(queueKey)
            guard let requestID = queues[queueKey]?.first, let entry = entries[requestID] else { continue }
            guard !entry.isCancelled else {
                finish(requestID, error: .cancelled)
                continue
            }
            guard now() < entry.deadline else {
                finish(requestID, error: .denied)
                continue
            }
            guard case .queued = entry.state else { continue }
            switch permissions.effectiveState(for: entry.tool) {
            case .allow:
                grant(entry)
            case .deny:
                finish(requestID, error: .denied)
            case .ask:
                presentPrompt(for: entry)
            }
        }
    }

    private func presentPrompt(for entry: Entry) {
        guard let prompter = entry.prompter else {
            finish(entry.requestID, error: .cancelled)
            return
        }
        entry.state = .awaitingDecision
        let shown = prompter.presentClientToolPermissionPrompt(.init(requestID: entry.requestID, callID: entry.callID, toolName: entry.tool.name))
        if !shown, entries[entry.requestID] === entry, case .awaitingDecision = entry.state {
            finish(entry.requestID, error: .cancelled, withdrawingPrompt: false)
        }
    }
}

private final class ClientToolCancellationSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
