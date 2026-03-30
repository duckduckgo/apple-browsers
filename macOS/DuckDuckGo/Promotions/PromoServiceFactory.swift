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

        let dateProvider: () -> Date
        let resetDebugDate: (() -> Void)?
        let buildType = StandardApplicationBuildType()
        if buildType.isDebugBuild || buildType.isReviewBuild {
            let debugSimulatedDateStore = DebugSimulatedDateStore(keyValueStore: dependencies.keyValueStore)
            dateProvider = { debugSimulatedDateStore.simulatedDate ?? Date() }
            resetDebugDate = { debugSimulatedDateStore.reset() }
        } else {
            dateProvider = Date.init
            resetDebugDate = nil
        }

        return PromoService(
            promos: promos,
            historyStore: historyStore,
            triggerPublisher: PromoTrigger.triggerPublisher,
            initialExternalActivation: dependencies.isExternallyActivated,
            isOnboardingCompletedProvider: dependencies.isOnboardingCompletedProvider,
            stateQueue: stateQueue,
            dateProvider: dateProvider,
            resetDebugDate: resetDebugDate
        )
    }

    @MainActor
    private static func makeAllPromos(dependencies: PromoDependencies) -> [Promo] {
        var promos: [Promo] = [
            sessionRestore(coordinator: dependencies.sessionRestoreCoordinator),
            remoteMessageNewTabPage(model: dependencies.activeRemoteMessageModel),
            freemiumDBP,
            remoteMessageTabBar(model: dependencies.activeRemoteMessageModel),
            nextSteps,
            defaultBrowserAndDockPopover(service: dependencies.defaultBrowserAndDockPromptService),
            defaultBrowserAndDockBanner(service: dependencies.defaultBrowserAndDockPromptService),
            defaultBrowserAndDockInactiveModal(service: dependencies.defaultBrowserAndDockPromptService)
        ]

        if includeTestPromos {
            promos.append(contentsOf: testPromos)
        }

        return promos
    }
}
