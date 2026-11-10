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

@MainActor
public protocol ClientToolPermissionPushing: AnyObject {
    /// Delivery may synchronously respond or cancel requests from this source.
    func pushClientToolPermissionRequested(_ prompt: ClientToolPermissionRequested) -> Bool
}

@MainActor
public protocol ClientToolPermissionCoordinating: AnyObject {
    func authorize(callID: String, tool: any BrowserTool, source: (any ClientToolPermissionPushing)?) async -> ClientToolPermissionAuthorization
}

public enum ClientToolPermissionAuthorization {
    case granted(performExecution: @MainActor (@escaping @MainActor () async -> BrowserToolResult) async -> BrowserToolResult?)
    case refused(ClientToolError)
}

@MainActor
public final class ClientToolPermissionCoordinator: ClientToolPermissionCoordinating {
    private static let permissionTimeout: TimeInterval = 120

    private enum State {
        case queued
        case awaitingDecision
        case granted
        case executing
    }

    private struct QueueKey: Hashable {
        let toolName: String
        let sourceID: ObjectIdentifier?
    }

    private final class Entry {
        let requestID: String
        let callID: String
        let tool: any BrowserTool
        weak var source: (any ClientToolPermissionPushing)?
        let requiresSource: Bool
        let queueKey: QueueKey
        let deadline: TimeInterval
        let cancellation: ClientToolCancellationSignal
        var state: State = .queued
        var continuation: CheckedContinuation<ClientToolPermissionAuthorization, Never>?
        var executionContinuation: CheckedContinuation<BrowserToolResult?, Never>?
        var executionTask: Task<Void, Never>?
        var timeout: Task<Void, Never>?

        init(requestID: String, callID: String, tool: any BrowserTool,
             source: (any ClientToolPermissionPushing)?, queueKey: QueueKey, deadline: TimeInterval,
             cancellation: ClientToolCancellationSignal, continuation: CheckedContinuation<ClientToolPermissionAuthorization, Never>) {
            self.requestID = requestID
            self.callID = callID
            self.tool = tool
            self.source = source
            requiresSource = source != nil
            self.queueKey = queueKey
            self.deadline = deadline
            self.cancellation = cancellation
            self.continuation = continuation
        }

        var isCancelled: Bool {
            cancellation.isCancelled || (requiresSource && source == nil)
        }
    }

    private let permissions: BrowserToolPermissionStoring
    private let now: () -> TimeInterval
    private let sleepUntil: (TimeInterval) async throws -> Void
    private var entries: [String: Entry] = [:]
    private var queues: [QueueKey: [String]] = [:]
    private var queueKeysPendingProcessing: Set<QueueKey> = []
    private var isProcessingPermissionQueues = false
    private var isCancellingSource = false

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
    public func authorize(callID: String, tool: any BrowserTool, source: (any ClientToolPermissionPushing)?) async -> ClientToolPermissionAuthorization {
        let cancellation = ClientToolCancellationSignal()
        let requestID = UUID().uuidString
        let deadline = now() + Self.permissionTimeout
        return await withTaskCancellationHandler {
            guard !Task.isCancelled, !cancellation.isCancelled else { return .refused(.cancelled) }
            return await withCheckedContinuation { continuation in
                let queueKey = QueueKey(toolName: tool.name, sourceID: source.map { ObjectIdentifier($0) })
                let entry = Entry(requestID: requestID, callID: callID, tool: tool, source: source,
                                  queueKey: queueKey, deadline: deadline, cancellation: cancellation, continuation: continuation)
                entries[requestID] = entry
                queues[entry.queueKey, default: []].append(requestID)
                entry.timeout = Task { [weak self, sleepUntil] in
                    do {
                        try await sleepUntil(deadline)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    self?.expire(requestID)
                }
                processPermissionQueue(for: entry.queueKey)
            }
        } onCancel: {
            cancellation.cancel()
            Task { @MainActor [weak self] in
                self?.finish(requestID, error: .cancelled)
            }
        }
    }

    @discardableResult
    public func respond(to response: RespondToClientToolPermissionRequest,
                        from source: any ClientToolPermissionPushing) -> RespondToClientToolPermissionResponse {
        defer { processPendingPermissionQueues() }
        guard let entry = entries[response.requestId],
              case .awaitingDecision = entry.state,
              entry.callID == response.callId, entry.source === source else {
            return .init()
        }
        guard !entry.isCancelled, now() < entry.deadline else {
            finish(entry.requestID, error: .cancelled)
            return .init()
        }
        switch response.decision {
        case .always:
            permissions.setState(.allow, forToolNamed: entry.tool.name)
            grant(entry)
        case .allow:
            grant(entry)
        case .never:
            permissions.setState(.deny, forToolNamed: entry.tool.name)
            finish(entry.requestID, error: .denied)
        case .decline:
            finish(entry.requestID, error: .denied)
        case .cancel:
            finish(entry.requestID, error: .cancelled)
        }
        return .init()
    }

    public func cancelRequests(from source: any ClientToolPermissionPushing) {
        let matching = entries.values.filter { $0.source === source }
        isCancellingSource = true
        for entry in matching {
            entry.cancellation.cancel()
            finish(entry.requestID, error: .cancelled)
        }
        isCancellingSource = false
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
        finish(requestID, error: .cancelled)
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

    private func finish(_ requestID: String, error: ClientToolError) {
        guard let entry = entries.removeValue(forKey: requestID) else { return }
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
        queues[entry.queueKey]?.removeAll { $0 == entry.requestID }
        if queues[entry.queueKey]?.isEmpty == true {
            queues.removeValue(forKey: entry.queueKey)
        }
        queueKeysPendingProcessing.insert(entry.queueKey)
    }

    private func processPermissionQueue(for queueKey: QueueKey) {
        queueKeysPendingProcessing.insert(queueKey)
        processPendingPermissionQueues()
    }

    private func processPendingPermissionQueues() {
        guard !isProcessingPermissionQueues, !isCancellingSource else { return }
        isProcessingPermissionQueues = true
        defer { isProcessingPermissionQueues = false }
        while let queueKey = queueKeysPendingProcessing.first {
            queueKeysPendingProcessing.remove(queueKey)
            guard let requestID = queues[queueKey]?.first, let entry = entries[requestID] else { continue }
            guard !entry.isCancelled, now() < entry.deadline else {
                finish(requestID, error: .cancelled)
                continue
            }
            guard case .queued = entry.state else { continue }
            switch permissions.effectiveState(for: entry.tool) {
            case .allow:
                grant(entry)
            case .deny:
                finish(requestID, error: .denied)
            case .ask:
                pushPrompt(for: entry)
            }
        }
    }

    private func pushPrompt(for entry: Entry) {
        guard let source = entry.source else {
            finish(entry.requestID, error: .cancelled)
            return
        }
        guard let prompt = try? ClientToolPermissionRequested(requestId: entry.requestID, callId: entry.callID,
                                                              message: entry.tool.permissionReason, choices: [.allow, .always, .never]) else {
            finish(entry.requestID, error: .executionFailed)
            return
        }
        entry.state = .awaitingDecision
        let delivered = source.pushClientToolPermissionRequested(prompt)
        if !delivered, entries[entry.requestID] === entry, case .awaitingDecision = entry.state {
            finish(entry.requestID, error: .cancelled)
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
