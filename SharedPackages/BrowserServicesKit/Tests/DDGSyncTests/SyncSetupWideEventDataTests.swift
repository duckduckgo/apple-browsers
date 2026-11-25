//
//  SyncSetupWideEventDataTests.swift
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

import Foundation
import Testing
import WideEvent
@testable import DDGSync

@Suite("SyncSetupWideEventData")
struct SyncSetupWideEventDataTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func makeData(setupMode: SyncSetupWideEventData.SetupMode? = nil) -> SyncSetupWideEventData {
        SyncSetupWideEventData(existingAccount: false,
                               flowVersion: .v21,
                               uiVersion: .v2,
                               setupMode: setupMode,
                               startedAt: start,
                               contextData: WideEventContextData(name: "settings_page"))
    }

    private func params(_ data: SyncSetupWideEventData) -> [String: String] {
        data.pixelParameters()
    }

    private func at(_ milliseconds: Int) -> Date {
        start.addingTimeInterval(Double(milliseconds) / 1000)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Latencies send the lower bound of their bucket",
          .timeLimit(.minutes(1)),
          arguments: [(400, "0"), (999, "0"), (1000, "1000"), (4000, "3000"), (599_999, "300000"), (600_000, "600000"), (3_600_000, "600000")])
    func latencyBuckets(milliseconds: Int, expected: String) {
        let data = makeData()
        data.end(at: at(milliseconds))

        #expect(params(data)["feature.data.ext.total_latency_ms_bucketed"] == expected)
        #expect(params(data)["feature.data.ext.last_step_latency_ms_bucketed"] == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Last step latency covers only the time on the last step", .timeLimit(.minutes(1)))
    func lastStepLatency() {
        let data = makeData()
        data.recordStep(.codeScreen, at: at(50_000))
        data.end(at: at(54_000))

        #expect(params(data)["feature.data.ext.total_latency_ms_bucketed"] == "30000")
        #expect(params(data)["feature.data.ext.last_step_latency_ms_bucketed"] == "3000")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Preparing sync latency runs through account_created and stops at the next step", .timeLimit(.minutes(1)))
    func preparingSyncLatency() {
        let data = makeData()
        data.recordStep(.preparingSync, at: at(1000))
        data.recordStep(.accountCreated, at: at(3000))
        data.recordStep(.hostAwaitingJoiner, at: at(12_000))
        data.end(at: at(200_000))

        #expect(params(data)["feature.data.ext.preparing_sync_latency_ms_bucketed"] == "10000")
        #expect(params(data)["feature.data.ext.last_step_latency_ms_bucketed"] == "180000")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Preparing sync latency stops when the attempt ends on preparing_sync", .timeLimit(.minutes(1)))
    func preparingSyncLatencyAtEnd() {
        let data = makeData()
        data.recordStep(.preparingSync, at: at(1000))
        data.end(at: at(41_000))

        #expect(params(data)["feature.data.ext.preparing_sync_latency_ms_bucketed"] == "30000")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A step repeated in a row is recorded once", .timeLimit(.minutes(1)))
    func stepDedupe() {
        let data = makeData()
        data.recordStep(.codeScreen)
        data.recordStep(.codeScreen)
        data.recordStep(.codeEntry)
        data.recordStep(.codeScreen)

        #expect(params(data)["feature.data.ext.steps"] == "started,code_screen,code_entry,code_screen")
        #expect(params(data)["feature.data.ext.last_step"] == "code_screen")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A repeated step doesn't restart the last step latency", .timeLimit(.minutes(1)))
    func repeatedStepKeepsLatency() {
        let data = makeData()
        data.recordStep(.codeScreen, at: at(0))
        data.recordStep(.codeScreen, at: at(9000))
        data.end(at: at(10_000))

        #expect(params(data)["feature.data.ext.last_step_latency_ms_bucketed"] == "10000")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Steps past 20 entries keep the first 19 and end with truncated", .timeLimit(.minutes(1)))
    func stepTruncation() {
        let data = makeData()
        for index in 0..<30 {
            data.recordStep(index.isMultiple(of: 2) ? .codeScreen : .codeEntry)
        }
        data.recordStep(.errorScreen)

        let steps = params(data)["feature.data.ext.steps"]?.components(separatedBy: ",") ?? []
        #expect(steps.count == 20)
        #expect(steps.first == "started")
        #expect(steps.last == "truncated")
        #expect(params(data)["feature.data.ext.last_step"] == "error_screen")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Exactly 20 steps are sent without truncation", .timeLimit(.minutes(1)))
    func twentyStepsNotTruncated() {
        let data = makeData()
        for index in 0..<19 {
            data.recordStep(index.isMultiple(of: 2) ? .codeScreen : .codeEntry)
        }

        let steps = params(data)["feature.data.ext.steps"]?.components(separatedBy: ",") ?? []
        #expect(steps.count == 20)
        #expect(!steps.contains("truncated"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Fields that don't apply are left out", .timeLimit(.minutes(1)))
    func absentFields() {
        let parameters = params(makeData())

        for key in ["setup_mode", "initial_setup_mode", "connect_method", "role", "peer_kind", "peer_outcome",
                    "camera_permission", "status_reason", "timeout_stage", "preparing_sync_latency_ms_bucketed",
                    "total_latency_ms_bucketed", "last_step_latency_ms_bucketed"] {
            #expect(parameters["feature.data.ext.\(key)"] == nil, "\(key) should be absent")
        }
        #expect(parameters["feature.data.ext.existing_account"] == "false")
        #expect(parameters["feature.data.ext.account_switch"] == "false")
        #expect(parameters["feature.data.ext.device_auth_shown"] == "false")
        #expect(parameters["feature.data.ext.sync_this_device_fallback"] == "false")
        #expect(parameters["feature.data.ext.flow_version"] == "v2.1")
        #expect(parameters["feature.data.ext.ui_version"] == "v2")
        #expect(parameters["feature.data.ext.steps"] == "started")
        #expect(parameters["feature.data.ext.last_step"] == "started")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Every field is sent once set", .timeLimit(.minutes(1)))
    func populatedFields() {
        let data = makeData(setupMode: .multiDevice)
        data.setupMode = .recovery
        data.connectMethod = .pasteCode
        data.role = .host
        data.peerKind = .thirdParty
        data.peerOutcome = .unknown
        data.accountSwitch = true
        data.deviceAuthShown = true
        data.cameraPermission = .notDetermined
        data.syncThisDeviceFallback = true
        data.statusReason = "session_timeout"
        data.timeoutStage = "waiting_for_peer_hello"

        let parameters = params(data)
        #expect(parameters["feature.data.ext.setup_mode"] == "recovery")
        #expect(parameters["feature.data.ext.initial_setup_mode"] == "multi_device")
        #expect(parameters["feature.data.ext.connect_method"] == "paste_code")
        #expect(parameters["feature.data.ext.role"] == "host")
        #expect(parameters["feature.data.ext.peer_kind"] == "3party")
        #expect(parameters["feature.data.ext.peer_outcome"] == "unknown")
        #expect(parameters["feature.data.ext.account_switch"] == "true")
        #expect(parameters["feature.data.ext.device_auth_shown"] == "true")
        #expect(parameters["feature.data.ext.camera_permission"] == "not_determined")
        #expect(parameters["feature.data.ext.sync_this_device_fallback"] == "true")
        #expect(parameters["feature.data.ext.status_reason"] == "session_timeout")
        #expect(parameters["feature.data.ext.timeout_stage"] == "waiting_for_peer_hello")
    }

    @available(iOS 16, macOS 13, *)
    @Test("The first mode chosen later becomes the initial mode", .timeLimit(.minutes(1)))
    func initialModeSetLater() {
        let data = makeData()
        data.setupMode = .singleDevice
        data.setupMode = .multiDevice

        #expect(params(data)["feature.data.ext.initial_setup_mode"] == "single_device")
        #expect(params(data)["feature.data.ext.setup_mode"] == "multi_device")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A pending attempt at app launch completes as UNKNOWN app_restart", .timeLimit(.minutes(1)))
    func appLaunchCompletesAsAppRestart() async {
        let decision = await makeData().completionDecision(for: .appLaunch)

        guard case .complete(.unknown(let reason)) = decision else {
            Issue.record("Expected UNKNOWN, got \(decision)")
            return
        }
        #expect(reason == "app_restart")
    }

    @available(iOS 16, macOS 13, *)
    @Test("The payload survives storage round-trip", .timeLimit(.minutes(1)))
    func codableRoundTrip() throws {
        let data = makeData()
        data.setupMode = .singleDevice
        data.setupMode = .multiDevice
        data.recordStep(.preparingSync, at: at(1000))
        data.end(at: at(5000))

        let decoded = try JSONDecoder().decode(SyncSetupWideEventData.self, from: JSONEncoder().encode(data))

        #expect(decoded.pixelParameters() == data.pixelParameters())
    }
}
