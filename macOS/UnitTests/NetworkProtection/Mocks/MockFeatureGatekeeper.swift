//
//  MockFeatureGatekeeper.swift
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

import Combine
import Foundation
import NetworkProtectionUI
@testable import DuckDuckGo_Privacy_Browser

/// Suspends `canStartVPN()` calls until a test releases them, so tests control when a visibility update resumes.
final class CanStartVPNGate: @unchecked Sendable {

    let pendingCount = CurrentValueSubject<Int, Never>(0)

    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Bool, Never>] = []

    func suspend() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            continuations.append(continuation)
            let count = continuations.count
            lock.unlock()
            pendingCount.send(count)
        }
    }

    func release(_ result: Bool) {
        lock.lock()
        let released = continuations
        continuations = []
        lock.unlock()
        pendingCount.send(0)
        released.forEach { $0.resume(returning: result) }
    }
}

struct MockVPNFeatureGatekeeper: VPNFeatureGatekeeper {

    var isInstalled: Bool
    var onboardStatusPublisher: AnyPublisher<NetworkProtectionUI.OnboardingStatus, Never>

    private var canStartVPNOverride: Bool
    private var isVPNVisibleOverride: Bool
    private var canStartVPNGate: CanStartVPNGate?

    init(canStartVPN: Bool,
         isInstalled: Bool,
         isVPNVisible: Bool,
         onboardStatusPublisher: AnyPublisher<NetworkProtectionUI.OnboardingStatus, Never>,
         canStartVPNGate: CanStartVPNGate? = nil) {

        self.canStartVPNGate = canStartVPNGate
        canStartVPNOverride = canStartVPN
        self.isInstalled = isInstalled
        isVPNVisibleOverride = isVPNVisible
        self.onboardStatusPublisher = onboardStatusPublisher
    }

    func canStartVPN() async throws -> Bool {
        if let canStartVPNGate {
            return await canStartVPNGate.suspend()
        }
        return canStartVPNOverride
    }

    func isVPNVisible() -> Bool {
        isVPNVisibleOverride
    }
}
