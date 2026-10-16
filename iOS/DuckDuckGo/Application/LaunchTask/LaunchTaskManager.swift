//
//  LaunchTaskManager.swift
//  DuckDuckGo
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
import UIKit
import Core

protocol LaunchTaskManaging: AnyObject {

    func register(task: LaunchTask)

}

/// Manages and runs a sequence of launch-time tasks using a background operation queue with iOS background execution support.
///
/// `LaunchTaskManager` lets you register multiple `LaunchTask`s to be executed serially in the background
/// during app startup. Tasks are wrapped in `LaunchOperation`s and executed in order on a single-threaded `OperationQueue`.
///
/// The manager also integrates with iOS background task APIs (`beginBackgroundTask`) to ensure
/// task execution can continue even if the app transitions to the background.
///
/// Use `register(task:)` to enqueue tasks, and `start()` to begin execution.
/// Ideal for structured app initialization flows that must run reliably and in sequence.
final class LaunchTaskManager: LaunchTaskManaging {

    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .background
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var hasStarted = false
    private var tasks: [LaunchTask] = []

    func register(task: LaunchTask) {
        assert(!hasStarted, "Registering tasks after starting the manager has no effect.")
        Logger.lifecycle.info("📦 Registered LaunchTask: \(task.name)")
        tasks.append(task)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        let operations = tasks.map { LaunchOperation(task: $0) }
        queue.addOperations(operations, waitUntilFinished: false)
    }

}

/// An `Operation` wrapper that runs a single `LaunchTask` with lifecycle control.
///
/// `LaunchOperation` provides thread-safe tracking of execution state and delivers a
/// `LaunchTaskContext` to the task, allowing it to check for cancellation and signal completion.
/// The operation will not finish until `context.finish()` is called, ensuring serialized flow.
///
/// Used internally by `LaunchTaskManager` to coordinate task execution.
final class LaunchOperation: Operation, @unchecked Sendable {

    private let task: LaunchTask
    private var taskContext: LaunchTaskContext?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    init(task: LaunchTask) {
        self.task = task
        super.init()
    }

    private let lock = NSRecursiveLock()
    private var _isExecuting = false
    override var isExecuting: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isExecuting
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            willChangeValue(forKey: #keyPath(isExecuting))
            _isExecuting = newValue
            didChangeValue(forKey: #keyPath(isExecuting))
        }
    }

    private var _isFinished = false
    override var isFinished: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isFinished
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            willChangeValue(forKey: #keyPath(isFinished))
            _isFinished = newValue
            didChangeValue(forKey: #keyPath(isFinished))
        }
    }

    override var isAsynchronous: Bool { true }

    override func start() {
        guard !isCancelled else {
            finish()
            return
        }

        isExecuting = true

        Logger.lifecycle.info("▶️ Starting LaunchTask: \(self.task.name)")

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "LaunchTask - \(task.name)") { [weak self] in
            self?.cancel()
            self?.finish()
        }

        let context = LaunchTaskContext(
            isCancelled: { [weak self] in self?.isCancelled ?? true },
            finish: { [weak self] in self?.finish() }
        )
        taskContext = context
        task.run(context: context)
    }

    private func finish() {
        Logger.lifecycle.info("✅ Finished LaunchTask: \(self.task.name)")
        endBackgroundTask()
        isExecuting = false
        isFinished = true
    }

    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

}
