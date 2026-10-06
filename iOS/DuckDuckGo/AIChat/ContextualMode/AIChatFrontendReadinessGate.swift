//
//  AIChatFrontendReadinessGate.swift
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

import Foundation

@MainActor
final class AIChatFrontendReadinessGate {
    private(set) var isReady = false
    private var frontendReadinessContinuation: CheckedContinuation<Bool, Never>?
    private var frontendReadinessTimeoutTask: Task<Void, Never>?
    private var frontendReadinessRequestID: UUID?

    func waitUntilReady(timeout: TimeInterval, onWaitStarted: (() -> Void)? = nil) async -> Bool {
        guard !isReady else { return true }

        resolveFrontendReadinessRequest(result: false)
        let requestID = UUID()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                let timeoutNanoseconds = UInt64(max(0, timeout) * 1_000_000_000)
                let timeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task<Never, Never>.sleep(nanoseconds: timeoutNanoseconds)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    self?.resolveFrontendReadinessRequest(requestID: requestID, result: false)
                }
                frontendReadinessRequestID = requestID
                frontendReadinessContinuation = continuation
                frontendReadinessTimeoutTask = timeoutTask
                onWaitStarted?()

                if isReady {
                    resolveFrontendReadinessRequest(requestID: requestID, result: true)
                } else if Task.isCancelled {
                    resolveFrontendReadinessRequest(requestID: requestID, result: false)
                }
            }
        }, onCancel: {
            Task { @MainActor [weak self] in
                self?.resolveFrontendReadinessRequest(requestID: requestID, result: false)
            }
        })
    }

    func markReady() {
        guard !isReady else { return }
        isReady = true
        resolveFrontendReadinessRequest(result: true)
    }

    func reset() {
        isReady = false
        resolveFrontendReadinessRequest(result: false)
    }

    private func resolveFrontendReadinessRequest(requestID: UUID, result: Bool) {
        guard frontendReadinessRequestID == requestID else { return }
        resolveFrontendReadinessRequest(result: result)
    }

    private func resolveFrontendReadinessRequest(result: Bool) {
        guard let continuation = frontendReadinessContinuation else { return }
        frontendReadinessContinuation = nil
        frontendReadinessRequestID = nil
        frontendReadinessTimeoutTask?.cancel()
        frontendReadinessTimeoutTask = nil
        continuation.resume(returning: result)
    }
}
