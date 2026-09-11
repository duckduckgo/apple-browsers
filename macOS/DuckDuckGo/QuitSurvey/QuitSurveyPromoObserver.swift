//
//  QuitSurveyPromoObserver.swift
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

import Combine
import Foundation

/// Shares the quit survey's visibility with the promo queue.
final class QuitSurveyPromoObserver: ExternalPromoDelegate {

    private let visibilitySubject = CurrentValueSubject<Bool, Never>(false)
    @MainActor private var pendingReport: (isVisible: Bool, continuation: CheckedContinuation<Void, Never>)?

    var isVisible: Bool { visibilitySubject.value }

    var isVisiblePublisher: AnyPublisher<Bool, Never> {
        visibilitySubject.removeDuplicates().eraseToAnyPublisher()
    }

    var resultWhenHidden: PromoResult { .ignored() }

    @MainActor
    func reportVisible() async {
        await reportVisibility(true)
    }

    @MainActor
    func reportHidden() async {
        await reportVisibility(false)
    }

    @MainActor
    func promoServiceDidApplyVisibility(_ isVisible: Bool) {
        guard let pendingReport, pendingReport.isVisible == isVisible else { return }
        self.pendingReport = nil
        pendingReport.continuation.resume()
    }

    @MainActor
    private func reportVisibility(_ isVisible: Bool) async {
        guard visibilitySubject.value != isVisible else { return }
        precondition(pendingReport == nil)
        await withCheckedContinuation { continuation in
            pendingReport = (isVisible, continuation)
            visibilitySubject.send(isVisible)
        }
    }
}
