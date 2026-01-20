//
//  DataBrokerProtectionStageDurationCalculatorTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import SecureStorage
import XCTest
import PixelKit
@testable import DataBrokerProtectionCore
@testable import DataBrokerProtectionCoreTestsUtils

final class DataBrokerProtectionStageDurationCalculatorTests: XCTestCase {
    let handler = MockDataBrokerProtectionPixelsHandler()

    override func tearDown() {
        handler.clear()
    }

    func testWhenErrorIs404_thenWeFireScanNoResultsPixel() {
        let sut = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com", dataBrokerVersion: "1.1.1", handler: handler, vpnConnectionState: "disconnected", vpnBypassStatus: "no", featureFlagger: MockDBPFeatureFlagger())

        sut.fireScanError(error: DataBrokerProtectionError.httpError(code: 404))

        XCTAssertTrue(MockDataBrokerProtectionPixelsHandler.lastPixelsFired.count == 1)

        if let failurePixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.last {
            switch failurePixel {
            case .scanNoResults(let broker, let brokerVersion, _, _, _, _, _, _, _, _):
                XCTAssertEqual(broker, "broker.com")
                XCTAssertEqual(brokerVersion, "1.1.1")
            default: XCTFail("The scan no results pixel should be fired")
            }
        } else {
            XCTFail("A pixel should be fired")
        }
    }

    func testWhenErrorIs403_thenWeFireScanErrorPixelWithClientErrorCategory() {
        let sut = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com", dataBrokerVersion: "1.1.1", handler: handler, vpnConnectionState: "disconnected", vpnBypassStatus: "no", featureFlagger: MockDBPFeatureFlagger())

        sut.fireScanError(error: DataBrokerProtectionError.httpError(code: 403))

        XCTAssertTrue(MockDataBrokerProtectionPixelsHandler.lastPixelsFired.count == 1)

        if let failurePixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.last {
            switch failurePixel {
            case .scanError(_, _, _, let category, _, _, _, _, _, _, _):
                XCTAssertEqual(category, ErrorCategory.clientError(httpCode: 403).toString)
            default: XCTFail("The scan error pixel should be fired")
            }
        } else {
            XCTFail("A pixel should be fired")
        }
    }

    func testWhenErrorIs500_thenWeFireScanErrorPixelWithServerErrorCategory() {
        let sut = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com", dataBrokerVersion: "1.1.1", handler: handler, vpnConnectionState: "disconnected", vpnBypassStatus: "no", featureFlagger: MockDBPFeatureFlagger())

        sut.fireScanError(error: DataBrokerProtectionError.httpError(code: 500))

        XCTAssertTrue(MockDataBrokerProtectionPixelsHandler.lastPixelsFired.count == 1)

        if let failurePixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.last {
            switch failurePixel {
            case .scanError(_, _, _, let category, _, _, _, _, _, _, _):
                XCTAssertEqual(category, ErrorCategory.serverError(httpCode: 500).toString)
            default: XCTFail("The scan error pixel should be fired")
            }
        } else {
            XCTFail("A pixel should be fired")
        }
    }

    func testScanErrorIncludesActionContextWhenAvailable() {
        let sut = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com", dataBrokerVersion: "1.1.1", handler: handler, vpnConnectionState: "disconnected", vpnBypassStatus: "no", featureFlagger: MockDBPFeatureFlagger())

        sut.setLastAction(ClickAction(id: "action-123", actionType: .click))
        sut.fireScanError(error: DataBrokerProtectionError.httpError(code: 500))

        guard let failurePixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.last else {
            XCTFail("A pixel should be fired")
            return
        }

        switch failurePixel {
        case .scanError(_, _, _, _, _, _, _, _, _, let actionId, let actionType):
            XCTAssertEqual(actionId, "action-123")
            XCTAssertEqual(actionType, "click")
        default:
            XCTFail("The scan error pixel should be fired")
        }
    }

    func testScanErrorDefaultsToUnknownActionContextWhenNotSet() {
        let sut = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com", dataBrokerVersion: "1.1.1", handler: handler, vpnConnectionState: "disconnected", vpnBypassStatus: "no", featureFlagger: MockDBPFeatureFlagger())

        sut.fireScanError(error: DataBrokerProtectionError.httpError(code: 500))

        guard let failurePixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.last else {
            XCTFail("A pixel should be fired")
            return
        }

        switch failurePixel {
        case .scanError(_, _, _, _, _, _, _, _, _, let actionId, let actionType):
            XCTAssertEqual(actionId, "unknown")
            XCTAssertEqual(actionType, "unknown")
        default:
            XCTFail("The scan error pixel should be fired")
        }
    }

    func testScanErrorIncludesParentWhenAvailable() {
        let sut = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com",
                                                              dataBrokerVersion: "1.1.1",
                                                              handler: handler,
                                                              parentURL: "parent.com",
                                                              vpnConnectionState: "disconnected",
                                                              vpnBypassStatus: "no",
                                                              featureFlagger: MockDBPFeatureFlagger())

        sut.fireScanError(error: DataBrokerProtectionError.httpError(code: 500))

        guard let failurePixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.last else {
            XCTFail("A pixel should be fired")
            return
        }

        switch failurePixel {
        case .scanError(_, _, _, _, _, _, _, _, let parent, _, _):
            XCTAssertEqual(parent, "parent.com")
        default:
            XCTFail("The scan error pixel should be fired")
        }
    }

    func testWhenErrorIsNotHttp_thenWeFireScanErrorPixelWithValidationErrorCategory() {
        let sut = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com", dataBrokerVersion: "1.1.1", handler: handler, vpnConnectionState: "disconnected", vpnBypassStatus: "no", featureFlagger: MockDBPFeatureFlagger())

        sut.fireScanError(error: DataBrokerProtectionError.actionFailed(actionID: "Action-ID", message: "Some message"))

        XCTAssertTrue(MockDataBrokerProtectionPixelsHandler.lastPixelsFired.count == 1)

        if let failurePixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.last {
            switch failurePixel {
            case .scanError(_, _, _, let category, _, _, _, _, _, _, _):
                XCTAssertEqual(category, ErrorCategory.validationError.toString)
            default: XCTFail("The scan error pixel should be fired")
            }
        } else {
            XCTFail("A pixel should be fired")
        }
    }

    func testWhenErrorIsNotDBPErrorButItIsNSURL_thenWeFireScanErrorPixelWithNetworkErrorErrorCategory() {
        let sut = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com", dataBrokerVersion: "1.1.1", handler: handler, vpnConnectionState: "disconnected", vpnBypassStatus: "no", featureFlagger: MockDBPFeatureFlagger())
        let nsURLError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)

        sut.fireScanError(error: nsURLError)

        XCTAssertTrue(MockDataBrokerProtectionPixelsHandler.lastPixelsFired.count == 1)

        if let failurePixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.last {
            switch failurePixel {
            case .scanError(_, _, _, let category, _, _, _, _, _, _, _):
                XCTAssertEqual(category, ErrorCategory.networkError.toString)
            default: XCTFail("The scan error pixel should be fired")
            }
        } else {
            XCTFail("A pixel should be fired")
        }
    }

    func testWhenErrorIsSecureVaultError_thenWeFireScanErorrPixelWithDatabaseErrorCategory() {
        let sut = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com", dataBrokerVersion: "1.1.1", handler: handler, vpnConnectionState: "disconnected", vpnBypassStatus: "no", featureFlagger: MockDBPFeatureFlagger())
        let error = SecureStorageError.encodingFailed

        sut.fireScanError(error: error)

        XCTAssertTrue(MockDataBrokerProtectionPixelsHandler.lastPixelsFired.count == 1)

        if let failurePixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.last {
            switch failurePixel {
            case .scanError(_, _, _, let category, _, _, _, _, _, _, _):
                XCTAssertEqual(category, "database-error-SecureVaultError-13")
            default: XCTFail("The scan error pixel should be fired")
            }
        } else {
            XCTFail("A pixel should be fired")
        }
    }

    func testWhenErrorIsNotDBPErrorAndNotURL_thenWeFireScanErrorPixelWithUnclassifiedErrorCategory() {
        let sut = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com", dataBrokerVersion: "1.1.1", handler: handler, vpnConnectionState: "disconnected", vpnBypassStatus: "no", featureFlagger: MockDBPFeatureFlagger())
        let error = NSError(domain: NSCocoaErrorDomain, code: -1)

        sut.fireScanError(error: error)

        XCTAssertTrue(MockDataBrokerProtectionPixelsHandler.lastPixelsFired.count == 1)

        if let failurePixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.last {
            switch failurePixel {
            case .scanError(_, _, _, let category, _, _, _, _, _, _, _):
                XCTAssertEqual(category, ErrorCategory.unclassified.toString)
            default: XCTFail("The scan error pixel should be fired")
            }
        } else {
            XCTFail("A pixel should be fired")
        }
    }

    // MARK: - Click Action Delay Reduction Optimization Feature Flag Tests

    func testWhenClickActionDelayReductionOptimizationFeatureFlagIsOn_thenOptOutStartPixelIncludesClickDelayOptimizationTrue() {
        let featureFlagger = MockDBPFeatureFlagger(isClickActionDelayReductionOptimizationOn: true)
        let sut = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com",
                                                              dataBrokerVersion: "1.0",
                                                              handler: handler,
                                                              vpnConnectionState: "disconnected",
                                                              vpnBypassStatus: "no",
                                                              featureFlagger: featureFlagger)

        sut.fireOptOutStart()

        guard let pixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.last else {
            XCTFail("A pixel should be fired")
            return
        }

        switch pixel {
        case .optOutStart(_, _, _, let clickDelayOptimization):
            XCTAssertTrue(clickDelayOptimization, "clickActionDelayReductionOptimization should be true when feature flag is ON")
        default:
            XCTFail("Expected optOutStart pixel")
        }
    }

    func testWhenClickActionDelayReductionOptimizationFeatureFlagIsOff_thenOptOutStartPixelIncludesClickDelayOptimizationFalse() {
        let featureFlagger = MockDBPFeatureFlagger(isClickActionDelayReductionOptimizationOn: false)
        let sut = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com",
                                                              dataBrokerVersion: "1.0",
                                                              handler: handler,
                                                              vpnConnectionState: "disconnected",
                                                              vpnBypassStatus: "no",
                                                              featureFlagger: featureFlagger)

        sut.fireOptOutStart()

        guard let pixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.last else {
            XCTFail("A pixel should be fired")
            return
        }

        switch pixel {
        case .optOutStart(_, _, _, let clickDelayOptimization):
            XCTAssertFalse(clickDelayOptimization, "clickActionDelayReductionOptimization should be false when feature flag is OFF")
        default:
            XCTFail("Expected optOutStart pixel")
        }
    }

    func testWhenClickActionDelayReductionOptimizationFeatureFlagIsOn_thenOptOutFailurePixelIncludesClickDelayOptimizationTrue() {
        let featureFlagger = MockDBPFeatureFlagger(isClickActionDelayReductionOptimizationOn: true)
        let sut = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com",
                                                              dataBrokerVersion: "1.0",
                                                              handler: handler,
                                                              vpnConnectionState: "disconnected",
                                                              vpnBypassStatus: "no",
                                                              featureFlagger: featureFlagger)

        sut.fireOptOutFailure(tries: 1, error: DataBrokerProtectionError.cancelled)

        guard let pixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.last else {
            XCTFail("A pixel should be fired")
            return
        }

        switch pixel {
        case .optOutFailure(_, _, _, _, _, _, _, _, _, _, _, _, _, _, let clickDelayOptimization):
            XCTAssertTrue(clickDelayOptimization, "clickActionDelayReductionOptimization should be true when feature flag is ON")
        default:
            XCTFail("Expected optOutFailure pixel")
        }
    }

    func testWhenClickActionDelayReductionOptimizationFeatureFlagIsOff_thenOptOutFailurePixelIncludesClickDelayOptimizationFalse() {
        let featureFlagger = MockDBPFeatureFlagger(isClickActionDelayReductionOptimizationOn: false)
        let sut = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com",
                                                              dataBrokerVersion: "1.0",
                                                              handler: handler,
                                                              vpnConnectionState: "disconnected",
                                                              vpnBypassStatus: "no",
                                                              featureFlagger: featureFlagger)

        sut.fireOptOutFailure(tries: 1, error: DataBrokerProtectionError.cancelled)

        guard let pixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.last else {
            XCTFail("A pixel should be fired")
            return
        }

        switch pixel {
        case .optOutFailure(_, _, _, _, _, _, _, _, _, _, _, _, _, _, let clickDelayOptimization):
            XCTAssertFalse(clickDelayOptimization, "clickActionDelayReductionOptimization should be false when feature flag is OFF")
        default:
            XCTFail("Expected optOutFailure pixel")
        }
    }

    func testWhenClickActionDelayReductionOptimizationFeatureFlagIsOn_thenOptOutSubmitPixelIncludesClickDelayOptimizationTrue() {
        let featureFlagger = MockDBPFeatureFlagger(isClickActionDelayReductionOptimizationOn: true)
        let sut = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com",
                                                              dataBrokerVersion: "1.0",
                                                              handler: handler,
                                                              vpnConnectionState: "disconnected",
                                                              vpnBypassStatus: "no",
                                                              featureFlagger: featureFlagger)

        sut.fireOptOutSubmit()

        guard let pixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.last else {
            XCTFail("A pixel should be fired")
            return
        }

        switch pixel {
        case .optOutSubmit(_, _, _, _, _, _, _, let clickDelayOptimization):
            XCTAssertTrue(clickDelayOptimization, "clickActionDelayReductionOptimization should be true when feature flag is ON")
        default:
            XCTFail("Expected optOutSubmit pixel")
        }
    }

    func testWhenClickActionDelayReductionOptimizationFeatureFlagIsOff_thenOptOutSubmitPixelIncludesClickDelayOptimizationFalse() {
        let featureFlagger = MockDBPFeatureFlagger(isClickActionDelayReductionOptimizationOn: false)
        let sut = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com",
                                                              dataBrokerVersion: "1.0",
                                                              handler: handler,
                                                              vpnConnectionState: "disconnected",
                                                              vpnBypassStatus: "no",
                                                              featureFlagger: featureFlagger)

        sut.fireOptOutSubmit()

        guard let pixel = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.last else {
            XCTFail("A pixel should be fired")
            return
        }

        switch pixel {
        case .optOutSubmit(_, _, _, _, _, _, _, let clickDelayOptimization):
            XCTAssertFalse(clickDelayOptimization, "clickActionDelayReductionOptimization should be false when feature flag is OFF")
        default:
            XCTFail("Expected optOutSubmit pixel")
        }
    }
}
