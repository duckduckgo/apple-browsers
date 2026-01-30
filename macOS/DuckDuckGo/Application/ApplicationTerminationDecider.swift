//
//  ApplicationTerminationDecider.swift
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

import AppKit
import os.log

// MARK: - Termination Response

/// Represents a decision about whether the application should terminate.
enum TerminationDecision {
    /// Continue to the next decider in the chain. If no more deciders, terminate the app.
    case next

    /// Cancel the termination request entirely.
    case cancel
}

// MARK: - Termination Query

/// Represents either a synchronous or asynchronous termination decision.
enum TerminationQuery {
    /// A synchronous decision that is available immediately.
    case sync(TerminationDecision)

    /// An asynchronous decision that will be resolved via a Task.
    /// The task should complete with a TerminationDecision.
    case async(Task<TerminationDecision, Never>)
}

// MARK: - Protocol

/// A protocol for objects that participate in the application termination decision process.
///
/// Deciders are consulted in sequence when the application is about to terminate. Each decider
/// can either make an immediate decision (synchronous) or defer the decision to an asynchronous
/// operation (e.g., showing an alert and waiting for user input).
@MainActor
protocol ApplicationTerminationDecider {
    /// Determines whether the application should terminate.
    ///
    /// - Parameter isAsync: `true` if the termination sequence has already been deferred by a
    ///   previous decider (e.g., a confirmation dialog is already shown). Use this to avoid
    ///   showing multiple confirmation dialogs.
    ///
    /// - Returns: A `TerminationQuery` indicating either:
    ///   - `.sync(decision)`: An immediate decision
    ///   - `.async(task)`: A deferred decision that will be resolved asynchronously
    func shouldTerminate(isAsync: Bool) -> TerminationQuery

    /// Called when the application termination decider sequence is completed.
    ///
    /// - Parameter shouldProceed: `true` if the action should proceed (terminate or close), `false` if the action was cancelled.
    func deciderSequenceCompleted(shouldProceed: Bool)
}
extension ApplicationTerminationDecider {
    func deciderSequenceCompleted(shouldProceed: Bool) {}
}
/// A decider that executes a closure to determine whether the application should terminate.
final class ClosureApplicationTerminationDecider: ApplicationTerminationDecider {
    private let shouldTerminate: (/*isAsync:*/ Bool) -> TerminationQuery
    init(_ shouldTerminate: @escaping (/*isAsync:*/ Bool) -> TerminationQuery) {
        self.shouldTerminate = shouldTerminate
    }
    func shouldTerminate(isAsync: Bool) -> TerminationQuery {
        return shouldTerminate(isAsync)
    }
}
extension ApplicationTerminationDecider where Self == ClosureApplicationTerminationDecider {
    /// Creates a decider that executes a closure to determine whether the application should terminate.
    static func terminationDecider(_ shouldTerminate: @escaping (/*isAsync:*/ Bool) -> TerminationQuery) -> Self {
        return Self(shouldTerminate)
    }
    /// Creates a decider that executes a closure without deferring the decision.
    static func perform(_ action: @escaping () -> Void) -> Self {
        return Self { _ in
            action()
            return .sync(.next)
        }
    }
}

// MARK: - Termination Decider Handler

/// Handles the execution of termination deciders in sequence.
@MainActor
final class TerminationDeciderHandler {
    private let replyToApplicationShouldTerminate: (@MainActor (Bool) -> Void)?
    private var terminationTask: Task<Void, Never>?
    private let deciders: [ApplicationTerminationDecider]

    @MainActor
    init(deciders: [ApplicationTerminationDecider], replyToApplicationShouldTerminate: (@MainActor (Bool) -> Void)? = nil) {
        self.replyToApplicationShouldTerminate = replyToApplicationShouldTerminate ?? NSApp.reply(toApplicationShouldTerminate:)
        self.deciders = deciders
    }

    func executeTerminationDeciders() -> NSApplication.TerminateReply {
        return executeTerminationDeciders(deciders, isAsync: false)
    }

    private func executeTerminationDeciders(_ deciders: [ApplicationTerminationDecider], isAsync: Bool) -> NSApplication.TerminateReply {
        // Prevent reentry if already processing termination
        if !isAsync && terminationTask != nil {
            return .terminateLater
        }

        var remainingDeciders = deciders

        while !remainingDeciders.isEmpty {
            let decider = remainingDeciders.removeFirst()
            let deciderType = String(describing: type(of: decider))
            let query = decider.shouldTerminate(isAsync: isAsync)

            switch query {
            case .sync(let decision):
                switch decision {
                case .next:
                    Logger.general.debug("TerminationDeciderHandler: \(deciderType) returned .sync(.next), continuing")
                    continue  // Move to next decider
                case .cancel:
                    Logger.general.debug("TerminationDeciderHandler: \(deciderType) returned .sync(.cancel)")
                    if isAsync {
                        deciderSequenceCompleted(async: true, shouldProceed: false, invokedDeciders: self.deciders.count - remainingDeciders.count)
                    }
                    return .terminateCancel
                }

            case .async(let task):
                Logger.general.debug("TerminationDeciderHandler: \(deciderType) returned .async, deferring termination")
                // Store task and continue asynchronously
                terminationTask = Task { @MainActor in
                    let decision = await task.value
                    self.terminationTask = nil

                    switch decision {
                    case .next:
                        Logger.general.debug("TerminationDeciderHandler: \(deciderType) async task completed with .next")
                        // Continue with remaining deciders in async mode
                        _ = self.executeTerminationDeciders(remainingDeciders, isAsync: true)
                    case .cancel:
                        Logger.general.debug("TerminationDeciderHandler: \(deciderType) async task completed with .cancel")
                        deciderSequenceCompleted(async: true, shouldProceed: false, invokedDeciders: self.deciders.count - remainingDeciders.count)
                    }
                }

                return .terminateLater
            }
        }

        // All deciders returned .next
        Logger.general.debug("TerminationDeciderHandler: All deciders completed, terminating")
        deciderSequenceCompleted(async: isAsync, shouldProceed: true, invokedDeciders: self.deciders.count)
        return .terminateNow
    }

    private func deciderSequenceCompleted(async: Bool, shouldProceed: Bool, invokedDeciders: Int) {
        /// If the decision is asynchronous and the action should not proceed, cancel the termination.
        if async && !shouldProceed {
            replyToApplicationShouldTerminate?(false)
        }

        /// Notify all deciders up to the one that was invoked that the sequence has completed.
        for decider in deciders[..<invokedDeciders] {
            decider.deciderSequenceCompleted(shouldProceed: shouldProceed)
        }

        /// If the decision is asynchronous and the action should proceed, allow the termination.
        if async && shouldProceed {
            replyToApplicationShouldTerminate?(true)
        }
        // For synchronous responses, the decision is defined by the returned NSApplication.TerminateReply.
    }

}
