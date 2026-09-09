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
import ConcurrencyExtensions
import Foundation

/// Shares the quit survey's visibility with the promo queue.
final class QuitSurveyPromoObserver: ExternalPromoDelegate {

    private let visibilitySubject = CurrentValueSubject<Bool, Never>(false)

    var isVisible: Bool { visibilitySubject.value }

    var isVisiblePublisher: AnyPublisher<Bool, Never> {
        visibilitySubject.removeDuplicates().eraseToAnyPublisher()
    }

    var resultWhenHidden: PromoResult { .ignored() }

    func reportVisible() {
        visibilitySubject.send(true)
    }

    func reportHidden() {
        visibilitySubject.send(false)
    }
}

/// Waits for the quit survey's dismissal to reach promo history before the app finishes quitting.
struct QuitSurveyDismissalGate {

    private let historyProvider: any PromoHistoryProviding

    init(historyProvider: any PromoHistoryProviding) {
        self.historyProvider = historyProvider
    }

    func wait(for timeout: @escaping @Sendable () async -> Void = { try? await Task.sleep(interval: 0.5) }) async {
        let dismissalRecorded = historyProvider.historyPublisher(for: PromoServiceFactory.quitSurveyPromoID)
            .compactMap { $0?.lastDismissed }
            .values

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in dismissalRecorded { break }
            }
            group.addTask {
                await timeout()
            }
            await group.next()
            group.cancelAll()
        }
    }
}
