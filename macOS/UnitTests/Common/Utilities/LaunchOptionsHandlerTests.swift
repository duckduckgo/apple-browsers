//
//  LaunchOptionsHandlerTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class LaunchOptionsHandlerTests: XCTestCase {

    private var userDefaults: UserDefaults!
    private var buildType: ApplicationBuildTypeMock!
    private var userDefaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        userDefaultsSuiteName = "LaunchOptionsHandlerTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: userDefaultsSuiteName)
        buildType = ApplicationBuildTypeMock()
    }

    override func tearDown() {
        userDefaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        userDefaultsSuiteName = nil
        buildType = nil
        userDefaults = nil
        super.tearDown()
    }

    func testWebDriverAutomationSessionIsEnabledForDebugBuildWithValidPort() {
        buildType.isDebugBuild = true

        let handler = makeHandler(arguments: ["automationPort": 8788])

        XCTAssertTrue(handler.isWebDriverAutomationSession)
    }

    func testWebDriverAutomationSessionIsEnabledForReviewBuildWithValidPort() {
        buildType.isReviewBuild = true

        let handler = makeHandler(arguments: ["automationPort": 8788])

        XCTAssertTrue(handler.isWebDriverAutomationSession)
    }

    func testWebDriverAutomationSessionIsDisabledForProductionBuild() {
        let handler = makeHandler(arguments: ["automationPort": 8788])

        XCTAssertFalse(handler.isWebDriverAutomationSession)
    }

    func testWebDriverAutomationSessionIsDisabledWithoutValidPort() {
        buildType.isReviewBuild = true

        XCTAssertFalse(makeHandler(arguments: [:]).isWebDriverAutomationSession)
        XCTAssertFalse(makeHandler(arguments: ["automationPort": 0]).isWebDriverAutomationSession)
        XCTAssertFalse(makeHandler(arguments: ["automationPort": 65_536]).isWebDriverAutomationSession)
    }

    func testWebViewProxyAcceptsOnlyLoopbackSOCKS5EndpointsWithValidPorts() {
        let ipv4Proxy = WebViewProxy("socks5://127.0.0.1:1")
        XCTAssertEqual(ipv4Proxy?.host, "127.0.0.1")
        XCTAssertEqual(ipv4Proxy?.port, 1)

        let ipv6Proxy = WebViewProxy("socks5://[::1]:65535")
        XCTAssertEqual(ipv6Proxy?.host, "::1")
        XCTAssertEqual(ipv6Proxy?.port, 65_535)

        XCTAssertNil(WebViewProxy("http://127.0.0.1:9997"))
        XCTAssertNil(WebViewProxy("socks5://localhost:9997"))
        XCTAssertNil(WebViewProxy("socks5://192.168.1.10:9997"))
        XCTAssertNil(WebViewProxy("socks5://127.0.0.1"))
        XCTAssertNil(WebViewProxy("socks5://127.0.0.1:0"))
        XCTAssertNil(WebViewProxy("socks5://127.0.0.1:65536"))
        XCTAssertNil(WebViewProxy("socks5://user@127.0.0.1:9997"))
        XCTAssertNil(WebViewProxy("socks5://127.0.0.1:9997/path"))
    }

    func testWebViewProxyRequiresAuthenticatedDebugOrReviewAutomationSession() {
        let arguments: [String: Any] = [
            "automationPort": 8788,
            "webViewProxy": "socks5://127.0.0.1:9997",
        ]

        XCTAssertNil(makeHandler(arguments: arguments, environment: [:]).webViewProxy)
        XCTAssertNil(makeHandler(arguments: arguments, environment: ["AUTOMATION_TOKEN": ""]).webViewProxy)
        XCTAssertNil(makeHandler(arguments: arguments, environment: ["AUTOMATION_TOKEN": "token"]).webViewProxy)

        buildType.isDebugBuild = true
        let proxy = makeHandler(arguments: arguments, environment: ["AUTOMATION_TOKEN": "token"]).webViewProxy
        XCTAssertEqual(proxy?.host, "127.0.0.1")
        XCTAssertEqual(proxy?.port, 9_997)
    }

    func testAcceptInsecureCertificatesRequiresAuthenticatedSessionAndProxy() {
        buildType.isReviewBuild = true
        let completeArguments: [String: Any] = [
            "automationPort": 8788,
            "webViewProxy": "socks5://127.0.0.1:9997",
            "acceptInsecureCerts": true,
        ]

        XCTAssertTrue(makeHandler(arguments: completeArguments, environment: ["AUTOMATION_TOKEN": "token"]).acceptsInsecureCertificates)
        XCTAssertFalse(makeHandler(arguments: completeArguments, environment: [:]).acceptsInsecureCertificates)
        XCTAssertFalse(
            makeHandler(
                arguments: ["automationPort": 8788, "acceptInsecureCerts": true],
                environment: ["AUTOMATION_TOKEN": "token"]
            ).acceptsInsecureCertificates
        )
        XCTAssertFalse(
            makeHandler(
                arguments: [
                    "webViewProxy": "socks5://127.0.0.1:9997",
                    "acceptInsecureCerts": true,
                ],
                environment: ["AUTOMATION_TOKEN": "token"]
            ).acceptsInsecureCertificates
        )
    }

    func testAcceptInsecureCertificatesReadsStringLaunchArgument() {
        buildType.isReviewBuild = true
        let handler = makeHandler(
            arguments: [
                "automationPort": 8788,
                "webViewProxy": "socks5://127.0.0.1:9997",
                "acceptInsecureCerts": "true",
            ],
            environment: ["AUTOMATION_TOKEN": "token"]
        )

        XCTAssertTrue(handler.acceptsInsecureCertificates)
    }

    private func makeHandler(
        arguments: [String: Any],
        environment: [String: String] = [:]
    ) -> LaunchOptionsHandler {
        userDefaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        return LaunchOptionsHandler(
            userDefaults: userDefaults,
            applicationBuildType: buildType,
            environment: environment
        )
    }
}
