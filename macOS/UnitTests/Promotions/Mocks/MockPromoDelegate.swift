//
//  MockPromoDelegate.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
@testable import DuckDuckGo_Privacy_Browser

final class MockPromoDelegate: PromoDelegate {

    let isEligibleSubject: CurrentValueSubject<Bool, Never>
    var isEligible: Bool {
        isEligibleSubject.value
    }
    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        isEligibleSubject.eraseToAnyPublisher()
    }

    private(set) var refreshEligibilityCallCount = 0
    func refreshEligibility() {
        refreshEligibilityCallCount += 1
    }

    private(set) var hideCallCount = 0
    @MainActor
    func hide() {
        hideCallCount += 1
        if let continuation = showContinuation {
            showContinuation = nil
            continuation.resume(returning: .noChange)
        }
    }

    private var showContinuation: CheckedContinuation<PromoResult, Never>?
    private var pendingShowResult: PromoResult?

    init(isEligible: Bool = true) {
        self.isEligibleSubject = CurrentValueSubject(isEligible)
    }

    func setEligible(_ value: Bool) {
        isEligibleSubject.send(value)
    }

    /// Configures the result that show() will return. Call before triggering show().
    /// If not set, show() will suspend until hide() is called (then returns .noChange).
    func setShowResult(_ result: PromoResult) {
        pendingShowResult = result
    }

    /// Completes a suspended show() with the given result. Call after show() has been invoked.
    func completeShow(with result: PromoResult) {
        if let continuation = showContinuation {
            showContinuation = nil
            continuation.resume(returning: result)
        } else {
            pendingShowResult = result
        }
    }

    private(set) var showCallCount = 0
    @MainActor
    func show(history: PromoHistoryRecord, force: Bool = false) async -> PromoResult {
        showCallCount += 1
        if let result = pendingShowResult {
            pendingShowResult = nil
            return result
        }
        return await withCheckedContinuation { continuation in
            self.showContinuation = continuation
        }
    }
}
