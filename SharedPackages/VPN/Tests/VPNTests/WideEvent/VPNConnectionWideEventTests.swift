//
//  VPNConnectionWideEventTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import XCTest
import PixelKit
@testable import VPN

final class VPNConnectionWideEventTests: XCTestCase {

    func testPixelParameters_setupWithCompleteSuccessfulFlow() {
        let eventData = VPNConnectionWideEventData(
            extensionType: .system,
            startupMethod: .manualByMainApp,
            contextData: WideEventContextData(name: "Test-Context")
        )

        let base = Date()
        eventData.browserStartDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.0)
        )
        eventData.controllerStartDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(2.0)
        )
        eventData.oauthDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(5.0)
        )
        eventData.tunnelStartDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(3.0)
        )
        eventData.overallDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(10.0)
        )

        let parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.name"], "vpn-connection")
        XCTAssertEqual(parameters["feature.data.ext.extension_type"], "system")
        XCTAssertEqual(parameters["feature.data.ext.startup_method"], "manual_by_main_app")
        XCTAssertEqual(parameters["feature.data.ext.is_setup"], "unknown")

        // Have all per step latencies
        XCTAssertEqual(parameters["feature.data.ext.latency_ms"], "10000")
        XCTAssertEqual(parameters["feature.data.ext.browser_start_latency_ms"], "1000")
        XCTAssertEqual(parameters["feature.data.ext.controller_start_latency_ms"], "2000")
        XCTAssertEqual(parameters["feature.data.ext.oauth_latency_ms"], "5000")
        XCTAssertEqual(parameters["feature.data.ext.tunnel_start_latency_ms"], "3000")

        // No per step errors
        XCTAssertNil(parameters["feature.data.ext.browser_start_error.domain"])
        XCTAssertNil(parameters["feature.data.ext.controller_start_error.domain"])
        XCTAssertNil(parameters["feature.data.ext.oauth_error.domain"])
        XCTAssertNil(parameters["feature.data.ext.tunnel_start_error.domain"])
    }

    func testPixelParameters_setupWithFailedFlow() {
        let eventData = VPNConnectionWideEventData(
            extensionType: .app,
            startupMethod: .manualByMainApp,
            contextData: WideEventContextData(name: "Test-Context")
        )

        let base = Date()
        eventData.controllerStartDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.0)
        )

        // Non-fatal OAuth failed error
        eventData.oauthDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(0.5)
        )
        let oauthError = NSError(domain: "OAuthError", code: 100, userInfo: nil)
        eventData.oauthError = WideEventErrorData(error: oauthError, description: "OauthTokenExpired")

        // Fatal tunnel start error
        let tunnelError = NSError(domain: "TunnelError", code: 200, userInfo: nil)
        eventData.tunnelStartError = WideEventErrorData(error: tunnelError, description: "TunnelStartFailed")

        let parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.name"], "vpn-connection")
        XCTAssertEqual(parameters["feature.data.ext.extension_type"], "app")
        XCTAssertEqual(parameters["feature.data.ext.startup_method"], "manual_by_main_app")
        XCTAssertEqual(parameters["feature.data.ext.is_setup"], "unknown")

        // Have partial latencies
        XCTAssertEqual(parameters["feature.data.ext.controller_start_latency_ms"], "1000")
        XCTAssertEqual(parameters["feature.data.ext.oauth_latency_ms"], "500")
        XCTAssertNil(parameters["feature.data.ext.tunnel_start_latency_ms"])

        // Have per step error data
        XCTAssertEqual(parameters["feature.data.ext.oauth_error.domain"], "OAuthError")
        XCTAssertEqual(parameters["feature.data.ext.oauth_error.code"], "100")
        XCTAssertEqual(parameters["feature.data.ext.oauth_error.description"], "OauthTokenExpired")
        XCTAssertEqual(parameters["feature.data.ext.tunnel_start_error.domain"], "TunnelError")
        XCTAssertEqual(parameters["feature.data.ext.tunnel_start_error.code"], "200")
        XCTAssertEqual(parameters["feature.data.ext.tunnel_start_error.description"], "TunnelStartFailed")
    }

    // MARK: - Abandoned and Delayed Flows

    func testPixelParameters_withAbandonedFlows() {
        let eventData = VPNConnectionWideEventData(
            extensionType: .app,
            startupMethod: .manualByMainApp,
            contextData: WideEventContextData(name: "Test-Context")
        )
        let base = Date()
        // no start interval
        var parameters = eventData.pixelParameters()
        XCTAssertNil(parameters["feature.data.ext.latency_ms"])

        // has ended interval
        eventData.overallDuration = WideEvent.MeasuredInterval(
            start: base, end: base.addingTimeInterval(2.5)
        ) // 2500ms
        parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.data.ext.latency_ms"], "2500")
    }

    func testPixelParameters_withDelayedFlows() {
        let eventData = VPNConnectionWideEventData(
            extensionType: .system,
            startupMethod: .manualByMainApp,
            contextData: WideEventContextData(name: "Test-Context")
        )
        let base = Date()

        // start only
        eventData.overallDuration  = WideEvent.MeasuredInterval(start: base, end: nil)
        var parameters = eventData.pixelParameters()
        XCTAssertNil(parameters["feature.data.ext.latency_ms"])

        // end only
        eventData.overallDuration = WideEvent.MeasuredInterval(start: nil, end: base)
        parameters = eventData.pixelParameters()
        XCTAssertNil(parameters["feature.data.ext.latency_ms"])
    }

    // MARK: - addStepLatency

    func testAddStepLatency_withValidInterval() {
        let eventData = VPNConnectionWideEventData(
            extensionType: .app,
            startupMethod: .manualByMainApp,
            contextData: WideEventContextData(name: "Test-Context")
        )

        let base = Date()
        eventData.browserStartDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(0.5)
        )
        var parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.data.ext.browser_start_latency_ms"], "500")

        eventData.controllerStartDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.0)
        )
        parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.data.ext.controller_start_latency_ms"], "1000")

        eventData.oauthDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(2.5)
        )
        parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.data.ext.oauth_latency_ms"], "2500")

        eventData.tunnelStartDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.5)
        )
        parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.data.ext.tunnel_start_latency_ms"], "1500")
    }

    func testAddStepLatency_withNilInterval() {
        let eventData = VPNConnectionWideEventData(
            extensionType: .app,
            startupMethod: .manualByMainApp,
            contextData: WideEventContextData(name: "Test-Context")
        )

        // All durations are nil
        let parameters = eventData.pixelParameters()

        XCTAssertNil(parameters["feature.data.ext.browser_start_latency_ms"])
        XCTAssertNil(parameters["feature.data.ext.controller_start_latency_ms"])
        XCTAssertNil(parameters["feature.data.ext.oauth_latency_ms"])
        XCTAssertNil(parameters["feature.data.ext.tunnel_start_latency_ms"])
    }

    func testAddStepLatency_roundedToInteger() {
        let eventData = VPNConnectionWideEventData(
            extensionType: .app,
            startupMethod: .manualByMainApp,
            contextData: WideEventContextData(name: "Test-Context")
        )

        let base = Date()
        eventData.controllerStartDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.9999999)
        )

        let parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.data.ext.controller_start_latency_ms"], "1999")
    }

    // MARK: - addStepError

    func testAddStepError_withNilError() {
        let eventData = VPNConnectionWideEventData(
            extensionType: .app,
            startupMethod: .manualByMainApp,
            contextData: WideEventContextData(name: "Test-Context")
        )

        // All errors are nil
        let parameters = eventData.pixelParameters()
        XCTAssertNil(parameters["feature.data.ext.browser_start_error.domain"])
        XCTAssertNil(parameters["feature.data.ext.controller_start_error.domain"])
        XCTAssertNil(parameters["feature.data.ext.oauth_error.domain"])
        XCTAssertNil(parameters["feature.data.ext.tunnel_start_error.domain"])
    }

    func testAddStepError_withTopLevelError() {
        let eventData = VPNConnectionWideEventData(
            extensionType: .app,
            startupMethod: .manualByMainApp,
            contextData: WideEventContextData(name: "Test-Context")
        )

        let error = NSError(domain: "TestDomain", code: 42, userInfo: nil)
        eventData.controllerStartError = WideEventErrorData(error: error, description: "ControllerStartFailed")

        let parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.data.ext.controller_start_error.domain"], "TestDomain")
        XCTAssertEqual(parameters["feature.data.ext.controller_start_error.code"], "42")
        XCTAssertEqual(parameters["feature.data.ext.controller_start_error.description"], "ControllerStartFailed")
    }

    func testAddStepError_withSingleUnderlyingError() {
        let eventData = VPNConnectionWideEventData(
            extensionType: .app,
            startupMethod: .manualByTheSystem,
            contextData: WideEventContextData(name: "Test-Context")
        )

        let underlyingError = NSError(domain: "UnderlyingDomain", code: 100, userInfo: nil)
        let topError = NSError(domain: "TopDomain", code: 200, userInfo: [
            NSUnderlyingErrorKey: underlyingError
        ])
        eventData.tunnelStartError = WideEventErrorData(error: topError)

        let parameters = eventData.pixelParameters()
        // Top error
        XCTAssertEqual(parameters["feature.data.ext.tunnel_start_error.domain"], "TopDomain")
        XCTAssertEqual(parameters["feature.data.ext.tunnel_start_error.code"], "200")

        // Underlying error: Single Underlying error does not have suffix
        XCTAssertEqual(parameters["feature.data.ext.tunnel_start_error.underlying_domain"], "UnderlyingDomain")
        XCTAssertEqual(parameters["feature.data.ext.tunnel_start_error.underlying_code"], "100")
    }

    func testAddStepError_withMultipleUnderlyingErrors() {
        let eventData = VPNConnectionWideEventData(
            extensionType: .app,
            startupMethod: .automaticOnDemand,
            contextData: WideEventContextData(name: "Test-Context")
        )

        let underlyingError2 = NSError(domain: "Domain2", code: 2, userInfo: [:])
        let underlyingError1 = NSError(domain: "Domain1", code: 1, userInfo: [
            NSUnderlyingErrorKey: underlyingError2
        ])
        let topError = NSError(domain: "TopDomain", code: 0, userInfo: [
            NSUnderlyingErrorKey: underlyingError1
        ])

        eventData.controllerStartError = WideEventErrorData(error: topError)

        let parameters = eventData.pixelParameters()

        // Top error
        XCTAssertEqual(parameters["feature.data.ext.controller_start_error.domain"], "TopDomain")
        XCTAssertEqual(parameters["feature.data.ext.controller_start_error.code"], "0")

        // First underlying error: First Underlying error does not have suffix
        XCTAssertEqual(parameters["feature.data.ext.controller_start_error.underlying_domain"], "Domain1")
        XCTAssertEqual(parameters["feature.data.ext.controller_start_error.underlying_code"], "1")

        // Second underlying error
        XCTAssertEqual(parameters["feature.data.ext.controller_start_error.underlying_domain2"], "Domain2")
        XCTAssertEqual(parameters["feature.data.ext.controller_start_error.underlying_code2"], "2")
    }

    // MARK: - transformErrorKey

    func testTransformErrorKey() {
        let eventData = VPNConnectionWideEventData(
            extensionType: .app,
            startupMethod: .manualByMainApp,
            contextData: WideEventContextData(name: "Test-Context")
        )

        let error = NSError(domain: "TestDomain", code: 1, userInfo: nil)

        eventData.controllerStartError = WideEventErrorData(error: error, description: "ControllerError")
        var parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.data.ext.controller_start_error.domain"], "TestDomain")
        XCTAssertEqual(parameters["feature.data.ext.controller_start_error.code"], "1")
        XCTAssertEqual(parameters["feature.data.ext.controller_start_error.description"], "ControllerError")

        eventData.oauthError = WideEventErrorData(error: error, description: "OauthError")
        parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.data.ext.oauth_error.domain"], "TestDomain")
        XCTAssertEqual(parameters["feature.data.ext.oauth_error.domain"], "TestDomain")
        XCTAssertEqual(parameters["feature.data.ext.oauth_error.code"], "1")
        XCTAssertEqual(parameters["feature.data.ext.oauth_error.description"], "OauthError")

        // No Description
        eventData.tunnelStartError = WideEventErrorData(error: error)
        parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.data.ext.tunnel_start_error.domain"], "TestDomain")
        XCTAssertEqual(parameters["feature.data.ext.tunnel_start_error.code"], "1")
        XCTAssertNil(parameters["feature.data.ext.tunnel_start_error.description"])
    }

    func testTransformErrorKey_underlyingDomainWithNoSuffix() {
        let eventData = VPNConnectionWideEventData(
            extensionType: .app,
            startupMethod: .manualByMainApp,
            contextData: WideEventContextData(name: "Test-Context")
        )

        let underlyingError = NSError(domain: "UnderlyingDomain", code: 1, userInfo: nil)
        let topError = NSError(domain: "TopDomain", code: 0, userInfo: [
            NSUnderlyingErrorKey: underlyingError
        ])

        eventData.controllerStartError = WideEventErrorData(error: topError)
        let parameters = eventData.pixelParameters()
        // Underlying error: Single Underlying error does not have suffix
        XCTAssertEqual(parameters["feature.data.ext.controller_start_error.underlying_domain"], "UnderlyingDomain")
        XCTAssertEqual(parameters["feature.data.ext.controller_start_error.underlying_code"], "1")
    }

    func testTransformErrorKey_underlyingDomainWithSuffix() {
        let eventData = VPNConnectionWideEventData(
            extensionType: .app,
            startupMethod: .manualByMainApp,
            contextData: WideEventContextData(name: "Text-Context")
        )

        // Create deep nested underlying errors
        let underlyingError20 = NSError(domain: "Domain20", code: 20, userInfo: nil)
        var currentError = underlyingError20
        for i in (1...19).reversed() {
            currentError = NSError(domain: "Domain\(i)", code: i, userInfo: [
                NSUnderlyingErrorKey: currentError
            ])
        }

        let topError = NSError(domain: "TopDomain", code: 0, userInfo: [
            NSUnderlyingErrorKey: currentError
        ])

        eventData.oauthError = WideEventErrorData(error: topError)
        let parameters = eventData.pixelParameters()

        for i in 1...20 {
            if i == 1 {
                XCTAssertEqual(parameters["feature.data.ext.oauth_error.underlying_domain"], "Domain1")
            } else {
                XCTAssertEqual(parameters["feature.data.ext.oauth_error.underlying_domain\(i)"], "Domain\(i)")
            }
        }
    }
}
