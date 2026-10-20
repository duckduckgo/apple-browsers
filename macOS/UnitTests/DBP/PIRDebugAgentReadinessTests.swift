//
//  PIRDebugAgentReadinessTests.swift
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

#if DEBUG
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class PIRDebugAgentReadinessTests: XCTestCase {
    @MainActor
    func testReadinessCanRecoverOnThirdAttempt() async throws {
        var probes = 0
        try await DataBrokerProtectionManager.waitForDebugAgentReady(timeout: 5, retryInterval: 0) { completion in
            probes += 1
            completion(probes == 3)
        }
        XCTAssertEqual(probes, 3)
    }

    @MainActor
    func testReadinessStopsAfterThreeFailedAttempts() async {
        var probes = 0
        do {
            try await DataBrokerProtectionManager.waitForDebugAgentReady(timeout: 5, retryInterval: 0) { completion in
                probes += 1
                completion(false)
            }
            XCTFail("Expected readiness to fail after three attempts")
        } catch DataBrokerProtectionManager.DebugLaunchError.agentNotReady {
            XCTAssertEqual(probes, 3)
        } catch {
            XCTFail("Expected agentNotReady, got \(error)")
        }
    }

    @MainActor
    func testUnansweredProbeReachesDeadlineWithoutAdditionalProbes() async {
        var probes = 0
        do {
            try await DataBrokerProtectionManager.waitForDebugAgentReady(timeout: 0.15, retryInterval: 0) { _ in
                probes += 1
            }
            XCTFail("Expected the readiness deadline to expire")
        } catch DataBrokerProtectionManager.DebugLaunchError.agentNotReady {
            XCTAssertEqual(probes, 1)
        } catch {
            XCTFail("Expected agentNotReady, got \(error)")
        }
    }
}
#endif
