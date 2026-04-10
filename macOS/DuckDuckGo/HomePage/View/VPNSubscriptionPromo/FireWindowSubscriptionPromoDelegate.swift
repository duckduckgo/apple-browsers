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

protocol PromoVisibilityReporting: AnyObject {
    func updateVisibility(_ isVisible: Bool, for source: AnyObject)
}

/// Promo delegate for the subscription promo on the Fire Window home page.
/// External promo: PromoService subscribes to isVisiblePublisher and records history.
/// Visibility is driven by SubscriptionPromoViewModel, which owns all display rules.
///
/// Multiple fire windows can exist simultaneously, each with its own ViewModel.
/// Tracks visibility per-ViewModel so closing one window doesn't hide the promo
/// while another window is still showing it.
final class FireWindowSubscriptionPromoDelegate: ExternalPromoDelegate, PromoVisibilityReporting {

    private let visibilitySubject = CurrentValueSubject<Bool, Never>(false)
    private var visibleSources = Set<ObjectIdentifier>()

    var isVisible: Bool { visibilitySubject.value }
    var isVisiblePublisher: AnyPublisher<Bool, Never> { visibilitySubject.eraseToAnyPublisher() }

    /// ViewModel handles its own dismissal persistence, so no cooldown needed here.
    var resultWhenHidden: PromoResult { .ignored(cooldown: 0) }

    func updateVisibility(_ isVisible: Bool, for source: AnyObject) {
        dispatchPrecondition(condition: .onQueue(.main))
        if isVisible {
            visibleSources.insert(ObjectIdentifier(source))
        } else {
            visibleSources.remove(ObjectIdentifier(source))
        }
        let newValue = !visibleSources.isEmpty
        guard newValue != visibilitySubject.value else { return }
        visibilitySubject.send(newValue)
    }
}
