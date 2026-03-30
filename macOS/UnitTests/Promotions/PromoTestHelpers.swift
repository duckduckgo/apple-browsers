//
//  PromoTestHelpers.swift
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

enum PromoTestHelpers {

    static func makePromo(
        id: String = "test-promo",
        triggers: Set<PromoTrigger> = [.appLaunched],
        initiated: PromoInitiated = .app,
        promoType: PromoType = PromoType(.banner),
        context: PromoContext = .global,
        coexistingPromoIDs: Set<String> = [],
        respectsGlobalCooldown: Bool = true,
        setsGlobalCooldown: Bool = true,
        delegate: (any AnyPromoDelegate)? = nil
    ) -> Promo {
        Promo(
            id: id,
            triggers: triggers,
            initiated: initiated,
            promoType: promoType,
            context: context,
            coexistingPromoIDs: coexistingPromoIDs,
            respectsGlobalCooldown: respectsGlobalCooldown,
            setsGlobalCooldown: setsGlobalCooldown,
            delegate: delegate
        )
    }

    /// Creates a controllable trigger publisher for tests. Use triggerSubject.send(.appLaunched) etc. to emit triggers.
    static func makeTriggerPublisher() -> (subject: PassthroughSubject<PromoTrigger, Never>, publisher: AnyPublisher<PromoTrigger, Never>) {
        let subject = PassthroughSubject<PromoTrigger, Never>()
        let publisher = subject.eraseToAnyPublisher()
        return (subject, publisher)
    }
}
