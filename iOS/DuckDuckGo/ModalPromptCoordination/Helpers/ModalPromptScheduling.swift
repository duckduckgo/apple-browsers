//
//  ModalPromptScheduling.swift
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

/// An idempotently cancellable handle for scheduled modal-prompt work.
@MainActor
final class ModalPromptScheduledTask {
    private var cancellationHandler: (() -> Void)?

    init(cancellationHandler: @escaping () -> Void = {}) {
        self.cancellationHandler = cancellationHandler
    }

    func cancel() {
        let cancellationHandler = cancellationHandler
        self.cancellationHandler = nil
        cancellationHandler?()
    }
}

/// Schedules modal-prompt work while allowing tests to substitute deterministic timing.
@MainActor
protocol ModalPromptScheduling {
    @discardableResult
    func schedule(after delay: TimeInterval, execute: @escaping @MainActor () -> Void) -> ModalPromptScheduledTask

    @discardableResult
    func scheduleOnNextMainTurn(execute: @escaping @MainActor () -> Void) -> ModalPromptScheduledTask
}

@MainActor
final class ModalPromptScheduler: ModalPromptScheduling {
    @discardableResult
    func schedule(after delay: TimeInterval, execute: @escaping @MainActor () -> Void) -> ModalPromptScheduledTask {
        let workItem = DispatchWorkItem(block: execute)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        return ModalPromptScheduledTask {
            workItem.cancel()
        }
    }

    @discardableResult
    func scheduleOnNextMainTurn(execute: @escaping @MainActor () -> Void) -> ModalPromptScheduledTask {
        let workItem = DispatchWorkItem(block: execute)
        DispatchQueue.main.async(execute: workItem)
        return ModalPromptScheduledTask {
            workItem.cancel()
        }
    }
}
