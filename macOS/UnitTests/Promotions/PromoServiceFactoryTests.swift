//
//  PromoServiceFactoryTests.swift
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

import PersistenceTestingUtils
import RemoteMessagingTestsUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class PromoServiceFactoryTests: XCTestCase {

    private var dependencies: PromoDependencies!

    override func setUp() {
        super.setUp()
        dependencies = makeDependencies()
    }

    override func tearDown() {
        dependencies = nil
        super.tearDown()
    }

    func testFactoryCreatesRMFPromosWithCorrectConfiguration() async {
        let ntpPromo = await PromoServiceFactory.remoteMessageNewTabPage(model: dependencies.activeRemoteMessageModel)
        let tabBarPromo = await PromoServiceFactory.remoteMessageTabBar(model: dependencies.activeRemoteMessageModel)

        for promo in [ntpPromo, tabBarPromo] {
            XCTAssertTrue(promo.triggers.isEmpty)
            XCTAssertEqual(promo.initiated, .app)
            XCTAssertEqual(promo.promoType.severity, .medium)
            XCTAssertFalse(promo.respectsGlobalCooldown)
            XCTAssertTrue(promo.setsGlobalCooldown)
            XCTAssertNotNil(promo.delegate)
        }

        XCTAssertEqual(ntpPromo.id, "remote-message-ntp")
        XCTAssertEqual(tabBarPromo.id, "remote-message-tabbar")
        XCTAssertEqual(ntpPromo.context, .newTabPage)
        XCTAssertEqual(tabBarPromo.context, .global)
    }

    func testFactoryCreatesNextStepsPromoWithCorrectConfiguration() {
        let promo = PromoServiceFactory.nextSteps

        XCTAssertEqual(promo.id, "next-steps-cards")
        XCTAssertTrue(promo.triggers.isEmpty)
        XCTAssertEqual(promo.initiated, .app)
        XCTAssertEqual(promo.promoType.severity, .medium)
        XCTAssertEqual(promo.context, .newTabPage)
        XCTAssertFalse(promo.respectsGlobalCooldown)
        XCTAssertTrue(promo.setsGlobalCooldown)
        XCTAssertNil(promo.delegate)
    }

}

extension PromoServiceFactoryTests {
    private func makeDependencies() -> PromoDependencies {
        let activeRemoteMessageModel = ActiveRemoteMessageModel(
            remoteMessagingStore: MockRemoteMessagingStore(),
            remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProvider(),
            openURLHandler: { _ in },
            navigateToFeedbackHandler: { },
            navigateToPIRHandler: { },
            navigateToSoftwareUpdateHandler: { }
        )
        return PromoDependencies(
            keyValueStore: InMemoryThrowingKeyValueStore(),
            isExternallyActivated: false,
            activeRemoteMessageModel: activeRemoteMessageModel
        )
    }
}
