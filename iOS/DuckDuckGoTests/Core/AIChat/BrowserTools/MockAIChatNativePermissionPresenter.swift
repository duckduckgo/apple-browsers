//
//  MockAIChatNativePermissionPresenter.swift
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

import AIChat
import UIKit
@testable import DuckDuckGo

@MainActor
final class MockAIChatNativePermissionPresenter: AIChatNativePermissionPresenting {
    var isAvailable = true
    var autoAnswer: ClientToolPermissionDecision? = .allowOnce
    var holdDismissal = false
    var onPresent: (() -> Void)?
    private(set) var prompts: [ClientToolPermissionPrompt] = []
    private(set) var withdrawals: [String] = []
    private var active: (ClientToolPermissionPrompt, @MainActor (ClientToolPermissionDecision) -> Void)?
    private var completions: [@MainActor () -> Void] = []
    var isPresentingPermission: Bool { active != nil }

    var isSurfaceAvailable: Bool { isAvailable }

    func owns(_ viewController: UIViewController) -> Bool { false }

    func present(_ prompt: ClientToolPermissionPrompt, decision: @escaping @MainActor (ClientToolPermissionDecision) -> Void) -> Bool {
        guard isAvailable, active == nil else { return false }
        active = (prompt, decision)
        prompts.append(prompt)
        onPresent?()
        if let autoAnswer { select(autoAnswer) }
        return true
    }

    func select(_ decision: ClientToolPermissionDecision) {
        guard let active else { return }
        withdraw(requestID: active.0.requestID) { active.1(decision) }
    }

    func withdraw(requestID: String, completion: @escaping @MainActor () -> Void) {
        guard active?.0.requestID == requestID else { completion(); return }
        withdrawals.append(requestID)
        completions.append(completion)
        if !holdDismissal { completeDismissal() }
    }

    func withdrawActive(completion: @escaping @MainActor () -> Void) {
        guard let active else { completion(); return }
        withdraw(requestID: active.0.requestID, completion: completion)
    }

    func completeDismissal() {
        active = nil
        let pending = completions
        completions.removeAll()
        pending.forEach { $0() }
    }
}
