//
//  TunnelConfigurationUpdateOperationTests.swift
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

import XCTest
@testable import VPN

@MainActor
final class TunnelConfigurationUpdateOperationTests: XCTestCase {

    private enum TestError: Error {
        case generateConfiguration
        case updateAdapter
        case startAdapter
    }

    func testRun_reassertConfigGenerationFailure_handlesFailureWithoutStoppingOrRestartingMonitors() async {
        var events: [String] = []

        do {
            try await TunnelConfigurationUpdateOperation.run(
                reassert: true,
                generateTunnelConfiguration: {
                    events.append("generate")
                    throw TestError.generateConfiguration
                },
                stopMonitors: {
                    events.append("stop")
                },
                updateAdapterConfiguration: { _ in
                    events.append("update")
                },
                handleAdapterStarted: {
                    events.append("start")
                },
                handleFailure: { error in
                    events.append("failure")
                    XCTAssertTrue(error is TestError)
                    return false
                },
                restartMonitorsAfterFailure: {
                    events.append("restart")
                }
            )
            XCTFail("Expected operation to throw")
        } catch TestError.generateConfiguration {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(events, ["generate", "failure"])
    }

    func testRun_reassertAdapterUpdateFailure_restartsMonitorsAfterFailure() async {
        var events: [String] = []

        do {
            try await TunnelConfigurationUpdateOperation.run(
                reassert: true,
                generateTunnelConfiguration: {
                    events.append("generate")
                    return .make()
                },
                stopMonitors: {
                    events.append("stop")
                },
                updateAdapterConfiguration: { _ in
                    events.append("update")
                    throw TestError.updateAdapter
                },
                handleAdapterStarted: {
                    events.append("start")
                },
                handleFailure: { error in
                    events.append("failure")
                    XCTAssertTrue(error is TestError)
                    return false
                },
                restartMonitorsAfterFailure: {
                    events.append("restart")
                }
            )
            XCTFail("Expected operation to throw")
        } catch TestError.updateAdapter {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(events, ["generate", "stop", "update", "failure", "restart"])
    }

    func testRun_reassertAdapterUpdateFailure_whenFailureCancelsTunnel_doesNotRestartMonitors() async {
        var events: [String] = []

        do {
            try await TunnelConfigurationUpdateOperation.run(
                reassert: true,
                generateTunnelConfiguration: {
                    events.append("generate")
                    return .make()
                },
                stopMonitors: {
                    events.append("stop")
                },
                updateAdapterConfiguration: { _ in
                    events.append("update")
                    throw TestError.updateAdapter
                },
                handleAdapterStarted: {
                    events.append("start")
                },
                handleFailure: { _ in
                    events.append("failure")
                    return true
                },
                restartMonitorsAfterFailure: {
                    events.append("restart")
                }
            )
            XCTFail("Expected operation to throw")
        } catch TestError.updateAdapter {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(events, ["generate", "stop", "update", "failure"])
    }

    func testRun_reassertAdapterStartedFailure_restartsMonitorsAfterFailure() async {
        var events: [String] = []

        do {
            try await TunnelConfigurationUpdateOperation.run(
                reassert: true,
                generateTunnelConfiguration: {
                    events.append("generate")
                    return .make()
                },
                stopMonitors: {
                    events.append("stop")
                },
                updateAdapterConfiguration: { _ in
                    events.append("update")
                },
                handleAdapterStarted: {
                    events.append("start")
                    throw TestError.startAdapter
                },
                handleFailure: { error in
                    events.append("failure")
                    XCTAssertTrue(error is TestError)
                    return false
                },
                restartMonitorsAfterFailure: {
                    events.append("restart")
                }
            )
            XCTFail("Expected operation to throw")
        } catch TestError.startAdapter {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(events, ["generate", "stop", "update", "start", "failure", "restart"])
    }

    func testRun_reassertSuccess_stopsMonitorsAfterConfigGenerationAndStartsMonitorsAfterAdapterUpdate() async throws {
        var events: [String] = []

        try await TunnelConfigurationUpdateOperation.run(
            reassert: true,
            generateTunnelConfiguration: {
                events.append("generate")
                return .make()
            },
            stopMonitors: {
                events.append("stop")
            },
            updateAdapterConfiguration: { _ in
                events.append("update")
            },
            handleAdapterStarted: {
                events.append("start")
            },
            handleFailure: { _ in
                events.append("failure")
                return false
            },
            restartMonitorsAfterFailure: {
                events.append("restart")
            }
        )

        XCTAssertEqual(events, ["generate", "stop", "update", "start"])
    }

    func testRun_nonReassertAdapterUpdateFailure_doesNotStopOrRestartMonitors() async {
        var events: [String] = []

        do {
            try await TunnelConfigurationUpdateOperation.run(
                reassert: false,
                generateTunnelConfiguration: {
                    events.append("generate")
                    return .make()
                },
                stopMonitors: {
                    events.append("stop")
                },
                updateAdapterConfiguration: { _ in
                    events.append("update")
                    throw TestError.updateAdapter
                },
                handleAdapterStarted: {
                    events.append("start")
                },
                handleFailure: { _ in
                    events.append("failure")
                    return false
                },
                restartMonitorsAfterFailure: {
                    events.append("restart")
                }
            )
            XCTFail("Expected operation to throw")
        } catch TestError.updateAdapter {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(events, ["generate", "update", "failure"])
    }
}
