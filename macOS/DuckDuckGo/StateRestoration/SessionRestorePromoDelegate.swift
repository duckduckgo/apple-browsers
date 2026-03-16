//
//  SessionRestorePromoDelegate.swift
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

/// Promo delegate for the session restore prompt. Visibility is driven by SessionRestorePromptCoordinator.
/// External promo: PromoService subscribes to isVisiblePublisher and applies result that temporarily dismisses the promo.
final class SessionRestorePromoDelegate: ExternalPromoDelegate {

    private let coordinator: SessionRestorePromptCoordinating
    private let visibilitySubject: CurrentValueSubject<Bool, Never>
    private var cancellables = Set<AnyCancellable>()

    var isVisible: Bool { visibilitySubject.value }
    var isVisiblePublisher: AnyPublisher<Bool, Never> { visibilitySubject.eraseToAnyPublisher() }

    /// When the session restore prompt is dismissed, treat as temporarily dismissed (eligible again when the coordinator shows the prompt).
    var resultWhenHidden: PromoResult {
        switch coordinator.state {
        case .promptDismissed:
            return .ignored(cooldown: 0)
        default:
            return .noChange
        }
    }

    init(coordinator: SessionRestorePromptCoordinating) {
        self.coordinator = coordinator
        self.visibilitySubject = CurrentValueSubject(coordinator.state.isVisible)

        coordinator.statePublisher
            .map { $0.isVisible }
            .removeDuplicates()
            .sink { [weak self] visible in
                self?.visibilitySubject.send(visible)
            }
            .store(in: &cancellables)
    }
}
