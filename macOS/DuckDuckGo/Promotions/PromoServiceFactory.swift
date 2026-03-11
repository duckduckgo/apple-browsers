//
//  PromoServiceFactory.swift
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

import AppKit
import Combine
import Persistence

struct PromoServiceFactory {
    static var includeTestPromos: Bool {
        let buildType = StandardApplicationBuildType()
        return buildType.isDebugBuild || buildType.isReviewBuild
    }

    @MainActor
    static func makePromoService(dependencies: PromoDependencies) -> PromoService {
        let promos = makeAllPromos(dependencies: dependencies)
        let stateQueue = DispatchQueue(label: "com.duckduckgo.promoService.state")
        let historyStore = PromoHistoryStore(store: dependencies.keyValueStore, queue: stateQueue)
        return PromoService(
            promos: promos,
            historyStore: historyStore,
            triggerPublisher: PromoTrigger.triggerPublisher,
            initialExternalActivation: dependencies.isExternallyActivated,
            stateQueue: stateQueue
        )
    }

    @MainActor
    private static func makeAllPromos(dependencies: PromoDependencies) -> [Promo] {
        var promos: [Promo] = [
            remoteMessageNewTabPage(model: dependencies.activeRemoteMessageModel),
            remoteMessageTabBar(model: dependencies.activeRemoteMessageModel),
            nextSteps
    ]

        if includeTestPromos {
            promos.append(contentsOf: testPromos)
        }

        return promos
    }
}
