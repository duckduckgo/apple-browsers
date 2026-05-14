//
//  PromoTypeTests.swift
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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class PromoTypeTests: XCTestCase {

    func testDefaultPromoType_SeverityMappings() {
        let highSeverity: [DefaultPromoType] = [.enhancedFeatureTip, .appModal, .specialPage]
        let mediumSeverity: [DefaultPromoType] = [
            .nextSteps, .remoteMessage, .banner, .featureTip, .infoBar,
            .semiModal, .contentCoverSheet, .progressiveEmphasisButton
        ]
        let lowSeverity: [DefaultPromoType] = [
            .inlineMessage, .nudgeButton, .emptyStateMessage, .inlineTip,
            .textBadge, .dotBadge, .menuItemHighlight, .settingsRecommendedAction
        ]

        for type in highSeverity {
            XCTAssertEqual(PromoType(type).severity, .high, "\(type) should have high severity")
        }
        for type in mediumSeverity {
            XCTAssertEqual(PromoType(type).severity, .medium, "\(type) should have medium severity")
        }
        for type in lowSeverity {
            XCTAssertEqual(PromoType(type).severity, .low, "\(type) should have low severity")
        }
    }

    func testDefaultPromoType_TimeoutIntervalMappings() {
        XCTAssertEqual(PromoType(.featureTip).timeoutInterval, .seconds(5))
        XCTAssertEqual(PromoType(.enhancedFeatureTip).timeoutInterval, .seconds(10))
        XCTAssertEqual(PromoType(.progressiveEmphasisButton).timeoutInterval, .seconds(30))
        XCTAssertEqual(PromoType(.dotBadge).timeoutInterval, .days(3))
        XCTAssertEqual(PromoType(.inlineTip).timeoutInterval, .days(5))
        XCTAssertEqual(PromoType(.textBadge).timeoutInterval, .days(5))
        XCTAssertEqual(PromoType(.menuItemHighlight).timeoutInterval, .days(5))
        XCTAssertEqual(PromoType(.nudgeButton).timeoutInterval, .days(7))

        let noTimeoutTypes: [DefaultPromoType] = [
            .nextSteps, .remoteMessage, .specialPage, .banner, .infoBar,
            .semiModal, .appModal, .contentCoverSheet, .inlineMessage,
            .emptyStateMessage, .settingsRecommendedAction
        ]
        for type in noTimeoutTypes {
            XCTAssertNil(PromoType(type).timeoutInterval, "\(type) should have nil timeout")
        }
    }

    func testDefaultPromoType_TimeoutResultMappings() {
        let ignoredWithDayCooldown: [DefaultPromoType] = [.featureTip, .enhancedFeatureTip, .progressiveEmphasisButton]
        for type in ignoredWithDayCooldown {
            switch PromoType(type).timeoutResult {
            case .ignored(let cooldown):
                XCTAssertEqual(cooldown, .day, "\(type) should have .day cooldown")
            default:
                XCTFail("\(type) should return .ignored(cooldown: .day), got \(PromoType(type).timeoutResult)")
            }
        }

        let ignoredPermanent: [DefaultPromoType] = [.nudgeButton, .inlineTip, .textBadge, .dotBadge, .menuItemHighlight]
        for type in ignoredPermanent {
            switch PromoType(type).timeoutResult {
            case .ignored(let cooldown):
                XCTAssertNil(cooldown, "\(type) should have nil cooldown (permanent)")
            default:
                XCTFail("\(type) should return .ignored(), got \(PromoType(type).timeoutResult)")
            }
        }

        let noChangeTypes: [DefaultPromoType] = [
            .nextSteps, .remoteMessage, .specialPage, .banner, .infoBar,
            .semiModal, .appModal, .contentCoverSheet, .inlineMessage,
            .emptyStateMessage, .settingsRecommendedAction
        ]
        for type in noChangeTypes {
            switch PromoType(type).timeoutResult {
            case .noChange:
                continue // Expected case
            default:
                XCTFail("\(type) should return .noChange, got \(PromoType(type).timeoutResult)")
            }
        }
    }

    func testPromoType_CustomTimeoutsOverrideDefaultTimeouts() {
        let type = PromoType(.appModal, customTimeoutInterval: .seconds(1), customTimeoutResult: .actioned)

        XCTAssertEqual(type.timeoutInterval, .seconds(1), "Custom timeout interval should override default")
        guard case .actioned = type.timeoutResult else {
            XCTFail("Custom timeout result should override default, got \(type.timeoutResult)")
            return
        }
    }
}
