//
//  PromoServiceFactory+AgeSignal.swift
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

import BrowserServicesKit
import Foundation
import Persistence

extension PromoServiceFactory {

    @MainActor
    static func ageSignal(dependencies: PromoDependencies) -> Promo {
        let requester = AgeSignalRequester(service: DefaultAgeRangeService(),
                                           storage: dependencies.keyValueStore.throwingKeyedStoring())
        let delegate = AgeSignalPromoDelegate(requester: requester,
                                              reinstallUserDetection: DefaultReinstallUserDetection(keyValueStore: dependencies.keyValueStore),
                                              featureFlagger: dependencies.featureFlagger,
                                              windowControllersManager: dependencies.windowControllersManager)

        // Apple's age range sheet can't be retracted, so it shows over visible promos rather than queueing behind them.
        return InternalPromo(id: "age-signal",
                             triggers: [.appLaunched, .windowBecameKey],
                             initiated: .app,
                             promoType: PromoType(.appModal),
                             context: .global,
                             respectsGlobalCooldown: false,
                             setsGlobalCooldown: false,
                             showsOverVisiblePromos: true,
                             delegate: delegate)
    }
}
