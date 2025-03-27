//
//  UsageSegmentationTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Foundation
import XCTest
@testable import BrowserServicesKit
@testable import Common

final class UsageSegmentationTests: XCTestCase {

    var defaultCalculatorResult: [String: String]? = [:]
    var searchAtbs: [Atb] = []
    var appUseAtbs: [Atb] = []

    func testWhenActivitiesOccur_ThenAtbsStoredAccordingToType() {
        var pixelFired = false
        let pixelHandler = EventMapping<UsageSegmentationPixel> { event, error, params, onComplete in
            if case .usageSegments = event {
                pixelFired = true
            }
        }

        let sut = makeSubject(pixelEvents: pixelHandler)
        let installAtb = Atb(version: "v100-1", updateVersion: nil)
        let todayAtb = Atb(version: "v100-2", updateVersion: nil)

        // Installation, just the install atb gets added, calcluator does not get used
        sut.processATB(installAtb, withInstallAtb: installAtb, andActivityType: .appUse)

        XCTAssertEqual([installAtb], appUseAtbs)
        XCTAssertEqual([], searchAtbs)

        // App use on the next day
        pixelFired = false
        sut.processATB(todayAtb, withInstallAtb: installAtb, andActivityType: .appUse)
        XCTAssertEqual([installAtb, todayAtb], appUseAtbs)
        XCTAssertEqual([], searchAtbs)
        XCTAssert(pixelFired)

        // Then a search
        pixelFired = false
        sut.processATB(todayAtb, withInstallAtb: installAtb, andActivityType: .search)
        XCTAssertEqual([installAtb, todayAtb], appUseAtbs)
        XCTAssertEqual([installAtb, todayAtb], searchAtbs)
        XCTAssert(pixelFired)

        // Then another search shouldn't change anything else
        sut.processATB(todayAtb, withInstallAtb: installAtb, andActivityType: .search)
        XCTAssertEqual([installAtb, todayAtb], appUseAtbs)
        XCTAssertEqual([installAtb, todayAtb], searchAtbs)
    }

    /// Activity type is not relevant here, that's tested elsewhere.
    func testWhenValidATBReceivedAndCalculatorReturnsNoResult_ThenNoPixelFired() {

        defaultCalculatorResult = nil

        var pixelFired = false
        let pixelHandler = EventMapping<UsageSegmentationPixel> { event, error, params, onComplete in
            if case .usageSegments = event {
                pixelFired = true
            }
        }
        let sut = makeSubject(pixelEvents: pixelHandler)

        let installAtb = Atb(version: "v100-1", updateVersion: nil)
        let atb = Atb(version: "v100-2", updateVersion: nil)
        sut.processATB(atb, withInstallAtb: installAtb, andActivityType: .search)

        XCTAssertEqual(searchAtbs, [installAtb, atb])
        XCTAssertFalse(pixelFired)

    }

    func testWhenSearchATBReceivedWithSameInstallAtbThatHasVariant_ThenStoredAndPixelFired() {
        assertWhenATBReceivedWithSameInstallAtb_ThenStoredAndPixelFired(.search,
                                                                          installAtb: "v123-1ru",
                                                                          atb: "v123-1")
    }

    func testWhenAppATBReceivedWithSameInstallAtbThatHasVariant_ThenStoredAndPixelFired() {
        assertWhenATBReceivedWithSameInstallAtb_ThenStoredAndPixelFired(.appUse,
                                                                          installAtb: "v123-1ru",
                                                                          atb: "v123-1")
    }

    func testWhenAppATBReceivedWithSameInstallAtb_ThenStoredAndPixelFired() {
        assertWhenATBReceivedWithSameInstallAtb_ThenStoredAndPixelFired(.appUse)
    }

    func testWhenSearchATBReceivedWithSameInstallAtb_ThenStoredAndPixelFired() {
        assertWhenATBReceivedWithSameInstallAtb_ThenStoredAndPixelFired(.search)
    }

    func testWhenNewAppATBReceivedWithInstallAtb_ThenBothStoredAndPixelFired() {
        assertWhenNewATBReceivedWithInstallAtb_ThenBothStoredAndPixelFired(.appUse)
    }

    func testWhenNewSearchATBReceivedWithInstallAtb_ThenBothStoredAndPixelFired() {
        assertWhenNewATBReceivedWithInstallAtb_ThenBothStoredAndPixelFired(.search)
    }

    func testWhenSearchActivityATBReceivedTwice_ThenNotStoredAndNoPixelFired() {
        assertWhenATBReceivedTwice_ThenNotStoredAndNoPixelFired(.search)
    }

    func testWhenAppActivityATBReceivedTwice_ThenNotStoredAndNoPixelFired() {
        assertWhenATBReceivedTwice_ThenNotStoredAndNoPixelFired(.appUse)
    }

    private func assertWhenATBReceivedWithSameInstallAtb_ThenStoredAndPixelFired(_ activityType: UsageActivityType, installAtb: String = "v100-1", atb: String = "v100-1", file: StaticString = #filePath, line: UInt = #line) {
        var pixelFired = false
        var pixelParams: [String: String]?
        let pixelHandler = EventMapping<UsageSegmentationPixel> { event, error, params, onComplete in
            if case .usageSegments = event {
                pixelFired = true
                pixelParams = params
            }
        }
        let sut = makeSubject(pixelEvents: pixelHandler)

        let installAtb = Atb(version: installAtb, updateVersion: nil)
        let atb = Atb(version: atb, updateVersion: nil)
        sut.processATB(atb, withInstallAtb: installAtb, andActivityType: activityType)

        XCTAssertEqual(activityType == .appUse ? appUseAtbs : searchAtbs, [installAtb])
        XCTAssert(pixelFired, file: file, line: line)
        XCTAssertEqual([:], pixelParams)
    }

    private func assertWhenNewATBReceivedWithInstallAtb_ThenBothStoredAndPixelFired(_ activityType: UsageActivityType, file: StaticString = #filePath, line: UInt = #line) {
        var pixelFired = false
        var pixelParams: [String: String]?
        let pixelHandler = EventMapping<UsageSegmentationPixel> { event, error, params, onComplete in
            if case .usageSegments = event {
                pixelFired = true
                pixelParams = params
            }
        }
        let sut = makeSubject(pixelEvents: pixelHandler)

        let installAtb = Atb(version: "v100-1", updateVersion: nil)
        let atb = Atb(version: "v100-2", updateVersion: nil)
        sut.processATB(atb, withInstallAtb: installAtb, andActivityType: activityType)

        XCTAssertEqual(activityType == .appUse ? appUseAtbs : searchAtbs, [installAtb, atb], file: file, line: line)
        XCTAssert(pixelFired, file: file, line: line)
        XCTAssertEqual([:], pixelParams)
    }

    private func assertWhenATBReceivedTwice_ThenNotStoredAndNoPixelFired(_ activityType: UsageActivityType, file: StaticString = #filePath, line: UInt = #line) {
        var pixelFired = false
        let pixelHandler = EventMapping<UsageSegmentationPixel> { event, error, params, onComplete in
            if case .usageSegments = event {
                pixelFired = true
            }
        }
        let sut = makeSubject(pixelEvents: pixelHandler)

        let installAtb = Atb(version: "v100-1", updateVersion: nil)
        let atb = Atb(version: "v100-2", updateVersion: nil)

        if activityType == .appUse {
            self.appUseAtbs = [installAtb, atb]
        } else {
            self.searchAtbs = [installAtb, atb]
        }

        sut.processATB(atb, withInstallAtb: installAtb, andActivityType: activityType)

        XCTAssertEqual(activityType == .appUse ? appUseAtbs : searchAtbs, [installAtb, atb], file: file, line: line)
        XCTAssertFalse(pixelFired, file: file, line: line)
    }

    private func makeSubject(pixelEvents: EventMapping<UsageSegmentationPixel>) -> UsageSegmenting {
        return UsageSegmentation(pixelEvents: pixelEvents, storage: self, calculatorFactory: self)
    }

}

extension UsageSegmentationTests: UsageSegmentationStoring {

}

extension UsageSegmentationTests: UsageSegmentationCalculatorMaking {

    func make(installAtb: Atb) -> any UsageSegmentationCalculating {
        return MockUsageSegmentationCalculator(installAtb, defaultCalculatorResult)
    }

}

final class MockUsageSegmentationCalculator: UsageSegmentationCalculating {

    let installAtb: Atb
    let result: [String: String]?
    init(_ installAtb: Atb, _ result: [String: String]?) {
        self.installAtb = installAtb
        self.result = result
    }

    func processAtb(_ atb: Atb, forActivityType activityType: UsageActivityType) -> [String: String]? {
        return result
    }

}
