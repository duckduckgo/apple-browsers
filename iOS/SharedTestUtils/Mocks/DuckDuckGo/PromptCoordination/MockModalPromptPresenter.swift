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

@MainActor
final class MockModalPromptPresenter: ModalPromptPresenter {
    var presentedViewController: UIViewController?

    private(set) var didCallPresent = false
    private(set) var capturedViewController: UIViewController?
    private(set) var capturedAnimated: Bool?
    private(set) var capturedCompletion: (() -> Void)?

    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
        didCallPresent = true
        capturedViewController = viewControllerToPresent
        capturedAnimated = flag
        capturedCompletion = completion
        completion?()
    }

    func reset() {
        didCallPresent = false
        capturedViewController = nil
        capturedAnimated = nil
        capturedCompletion = nil
    }
}

final class MockModalPromptScheduler: ModalPromptScheduling {
    private(set) var didCallSchedule = false
    private(set) var capturedScheduledDelay: TimeInterval?
    private var scheduledBlock: (@MainActor () -> Void)?

    func schedule(after delay: TimeInterval, execute: @escaping @MainActor () -> Void) {
        didCallSchedule = true
        capturedScheduledDelay = delay
        scheduledBlock = execute
    }

    @MainActor
    func executeScheduledBlock() {
        scheduledBlock?()
    }
}
