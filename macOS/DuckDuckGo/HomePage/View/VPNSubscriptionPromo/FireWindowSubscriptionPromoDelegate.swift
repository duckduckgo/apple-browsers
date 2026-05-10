//
//  FireWindowSubscriptionPromoDelegate.swift
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

/// Promo delegate for the subscription promo on the Fire Window home page.
/// External promo: PromoService subscribes to isVisiblePublisher and records history.
/// Visibility is driven by SubscriptionPromoViewModel, which owns all display rules.
final class FireWindowSubscriptionPromoDelegate: ExternalPromoDelegate {

    private let visibilitySubject = CurrentValueSubject<Bool, Never>(false)

    var isVisible: Bool { visibilitySubject.value }
    var isVisiblePublisher: AnyPublisher<Bool, Never> { visibilitySubject.eraseToAnyPublisher() }

    var resultWhenHidden: PromoResult { .ignored(cooldown: .days(SubscriptionPromoConstants.dismissCooldownDays)) }

    func updateVisibility(_ isVisible: Bool) {
        guard isVisible != visibilitySubject.value else { return }
        visibilitySubject.send(isVisible)
    }
}
