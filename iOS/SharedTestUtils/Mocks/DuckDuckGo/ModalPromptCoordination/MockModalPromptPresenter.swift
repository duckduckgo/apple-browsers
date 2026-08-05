//
//  MockModalPromptPresenter.swift
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

import UIKit
@testable import DuckDuckGo

/// Completes presentation synchronously without establishing `presentedViewController`, unlike real UIKit.
/// Ordering-sensitive tests must use `DeferredCompletionModalPromptPresenter` or establish the presentation relationship manually.
@MainActor
final class MockModalPromptPresenter: ModalPromptPresenter {
    var presentedViewController: UIViewController?
    var modalPromptPresentationViewController: UIViewController?

    private(set) var didCallPresent = false
    private(set) var capturedViewController: UIViewController?
    private(set) var capturedAnimated: Bool?
    private(set) var capturedCompletion: (() -> Void)?
    var shouldCompletePresentation = true

    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
        didCallPresent = true
        capturedViewController = viewControllerToPresent
        capturedAnimated = flag
        capturedCompletion = completion
        if shouldCompletePresentation {
            completion?()
        }
    }

    func reset() {
        didCallPresent = false
        capturedViewController = nil
        capturedAnimated = nil
        capturedCompletion = nil
    }
}

@MainActor
final class MockDismissibleViewController: UIViewController {
    private(set) var didCallDismiss = false
    private(set) var dismissCallCount = 0
    private(set) var capturedDismissAnimated: Bool?
    var dismissCompletion: (() -> Void)?

    private(set) var didCallPresent = false
    private(set) var capturedPresentedViewController: UIViewController?

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        didCallDismiss = true
        dismissCallCount += 1
        capturedDismissAnimated = flag
        dismissCompletion = completion
        completion?()
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        didCallPresent = true
        capturedPresentedViewController = viewControllerToPresent
        completion?()
    }
}

@MainActor
final class MockModalPromptScheduler: ModalPromptScheduling {
    private final class ScheduledBlock {
        let execute: @MainActor () -> Void
        var isCancelled = false

        init(execute: @escaping @MainActor () -> Void) {
            self.execute = execute
        }
    }

    private(set) var didCallSchedule = false
    private(set) var capturedScheduledDelay: TimeInterval?
    private var delayedBlocks = [ScheduledBlock]()
    private var nextMainTurnBlocks = [ScheduledBlock]()

    @discardableResult
    func schedule(after delay: TimeInterval, execute: @escaping @MainActor () -> Void) -> ModalPromptScheduledTask {
        didCallSchedule = true
        capturedScheduledDelay = delay
        let scheduledBlock = ScheduledBlock(execute: execute)
        delayedBlocks.append(scheduledBlock)
        return ModalPromptScheduledTask {
            scheduledBlock.isCancelled = true
        }
    }

    @discardableResult
    func scheduleOnNextMainTurn(execute: @escaping @MainActor () -> Void) -> ModalPromptScheduledTask {
        let scheduledBlock = ScheduledBlock(execute: execute)
        nextMainTurnBlocks.append(scheduledBlock)
        return ModalPromptScheduledTask {
            scheduledBlock.isCancelled = true
        }
    }

    @MainActor
    func executeScheduledBlock(includingCancelled: Bool = false) {
        guard !delayedBlocks.isEmpty else {
            return
        }

        let scheduledBlock = delayedBlocks.removeFirst()
        guard includingCancelled || !scheduledBlock.isCancelled else {
            return
        }
        scheduledBlock.execute()
    }

    @MainActor
    func executeNextMainTurnBlock(includingCancelled: Bool = false) {
        guard !nextMainTurnBlocks.isEmpty else {
            return
        }

        let scheduledBlock = nextMainTurnBlocks.removeFirst()
        guard includingCancelled || !scheduledBlock.isCancelled else {
            return
        }
        scheduledBlock.execute()
    }
}
