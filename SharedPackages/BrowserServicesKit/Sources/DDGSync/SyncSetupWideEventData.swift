//
//  SyncSetupWideEventData.swift
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
import FoundationExtensions
import WideEvent

public final class SyncSetupWideEventData: WideEventData {

    public static let metadata = WideEventMetadata(
        pixelName: "sync_setup",
        featureName: "sync-setup",
        mobileMetaType: "ios-sync-setup",
        desktopMetaType: "macos-sync-setup",
        version: "1.0.0"
    )

    public static let currentLaunchID = UUID().uuidString

    private static let maxStepEntries = 20
    private static let latencyBucketBounds = [1000, 2000, 3000, 5000, 10000, 30000, 60000, 120000, 180000, 300000, 600000]

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData
    public var errorData: WideEventErrorData?

    public var setupMode: SetupMode? {
        didSet {
            if initialSetupMode == nil {
                initialSetupMode = setupMode
            }
        }
    }
    public private(set) var initialSetupMode: SetupMode?
    public var connectMethod: ConnectMethod?
    public var role: Role?
    public var peerKind: PeerKind?
    public var peerOutcome: PeerOutcome?
    public var existingAccount: Bool
    public var accountSwitch = false
    public var flowVersion: FlowVersion
    public var uiVersion: UIVersion
    public var deviceAuthShown = false
    public var cameraPermission: CameraPermission?
    public var syncThisDeviceFallback = false
    public var statusReason: String?
    public var timeoutStage: String?

    public let launchID: String
    public private(set) var steps: [Step]
    public private(set) var totalDuration: WideEvent.MeasuredInterval
    public private(set) var lastStepDuration: WideEvent.MeasuredInterval
    public private(set) var preparingSyncDuration: WideEvent.MeasuredInterval?

    public init(existingAccount: Bool,
                flowVersion: FlowVersion,
                uiVersion: UIVersion,
                setupMode: SetupMode? = nil,
                startedAt: Date = Date(),
                launchID: String = SyncSetupWideEventData.currentLaunchID,
                contextData: WideEventContextData,
                appData: WideEventAppData = WideEventAppData(),
                globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.existingAccount = existingAccount
        self.flowVersion = flowVersion
        self.uiVersion = uiVersion
        self.setupMode = setupMode
        self.initialSetupMode = setupMode
        self.launchID = launchID
        self.steps = [.started]
        self.totalDuration = WideEvent.MeasuredInterval(start: startedAt)
        self.lastStepDuration = WideEvent.MeasuredInterval(start: startedAt)
        self.contextData = contextData.name == nil ? WideEventContextData(name: Self.unknownContextName) : contextData
        self.appData = appData
        self.globalData = globalData
    }

    public func recordStep(_ step: Step, at date: Date = Date()) {
        guard step != steps.last else { return }

        if step != .accountCreated, preparingSyncDuration?.end == nil {
            preparingSyncDuration?.complete(at: date)
        }
        if step == .preparingSync {
            preparingSyncDuration = WideEvent.MeasuredInterval(start: date)
        }

        steps.append(step)
        lastStepDuration = WideEvent.MeasuredInterval(start: date)
    }

    public func end(at date: Date = Date()) {
        totalDuration.complete(at: date)
        lastStepDuration.complete(at: date)
        if preparingSyncDuration?.end == nil {
            preparingSyncDuration?.complete(at: date)
        }
    }

    public func completionDecision(for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision {
        switch trigger {
        case .appLaunch:
            guard launchID != Self.currentLaunchID else { return .keepPending }
            return .complete(.unknown(reason: StatusReason.appRestart))
        }
    }

    private static func latencyBucket(milliseconds: Int) -> Int {
        latencyBucketBounds.last { $0 <= milliseconds } ?? 0
    }

    private var stepsParameter: String {
        guard steps.count > Self.maxStepEntries else {
            return steps.map(\.rawValue).joined(separator: ",")
        }
        return (steps.prefix(Self.maxStepEntries - 1).map(\.rawValue) + [Self.truncatedStepsMarker]).joined(separator: ",")
    }

    private static let truncatedStepsMarker = "truncated"
    private static let unknownContextName = "unknown"
}

extension SyncSetupWideEventData {

    public enum StatusReason {
        public static let appRestart = "app_restart"
        public static let duplicated = "duplicated"
    }

    public enum SetupMode: String, Codable, CaseIterable {
        case singleDevice = "single_device"
        case multiDevice = "multi_device"
        case recovery
    }

    public enum ConnectMethod: String, Codable, CaseIterable {
        case showCode = "show_code"
        case scanCode = "scan_code"
        case pasteCode = "paste_code"
        case link
    }

    public enum Role: String, Codable, CaseIterable {
        case host
        case joiner
    }

    public enum PeerKind: String, Codable, CaseIterable {
        case ddg
        case thirdParty = "3party"
    }

    public enum PeerOutcome: String, Codable, CaseIterable {
        case success
        case failure
        case cancelled
        case unknown
    }

    public enum FlowVersion: String, Codable, CaseIterable {
        case v1
        case v2
        case v21 = "v2.1"
    }

    public enum UIVersion: String, Codable, CaseIterable {
        case v1
        case v2
    }

    public enum CameraPermission: String, Codable, CaseIterable {
        case granted
        case denied
        case notDetermined = "not_determined"
    }

    public enum Step: String, Codable, CaseIterable {
        case started
        case choiceScreen = "choice_screen"
        case deviceAuth = "device_auth"
        case preparingCode = "preparing_code"
        case codeScreen = "code_screen"
        case codeEntry = "code_entry"
        case codeAcceptedByOtherDevice = "code_accepted_by_other_device"
        case confirmationScreen = "confirmation_screen"
        case waitingForConfirmation = "waiting_for_confirmation"
        case syncConfirmation = "sync_confirmation"
        case preparingSync = "preparing_sync"
        case hostAwaitingJoiner = "host_awaiting_joiner"
        case accountCreated = "account_created"
        case syncThisDeviceOffer = "sync_this_device_offer"
        case restoreOffer = "restore_offer"
        case errorScreen = "error_screen"
        case recoveryCodeShown = "recovery_code_shown"
        case successScreenShown = "success_screen_shown"
    }
}

extension SyncSetupWideEventData {

    private enum Key {
        static let setupMode = "feature.data.ext.setup_mode"
        static let initialSetupMode = "feature.data.ext.initial_setup_mode"
        static let connectMethod = "feature.data.ext.connect_method"
        static let role = "feature.data.ext.role"
        static let peerKind = "feature.data.ext.peer_kind"
        static let peerOutcome = "feature.data.ext.peer_outcome"
        static let existingAccount = "feature.data.ext.existing_account"
        static let accountSwitch = "feature.data.ext.account_switch"
        static let flowVersion = "feature.data.ext.flow_version"
        static let uiVersion = "feature.data.ext.ui_version"
        static let lastStep = "feature.data.ext.last_step"
        static let steps = "feature.data.ext.steps"
        static let deviceAuthShown = "feature.data.ext.device_auth_shown"
        static let cameraPermission = "feature.data.ext.camera_permission"
        static let syncThisDeviceFallback = "feature.data.ext.sync_this_device_fallback"
        static let statusReason = "feature.data.ext.status_reason"
        static let timeoutStage = "feature.data.ext.timeout_stage"
        static let totalLatency = "feature.data.ext.total_latency_ms_bucketed"
        static let lastStepLatency = "feature.data.ext.last_step_latency_ms_bucketed"
        static let preparingSyncLatency = "feature.data.ext.preparing_sync_latency_ms_bucketed"
    }

    public func jsonParameters() -> [String: Encodable] {
        let bucket = DurationBucket.bucketed(Self.latencyBucket(milliseconds:))
        return Dictionary(compacting: [
            (Key.setupMode, setupMode?.rawValue),
            (Key.initialSetupMode, initialSetupMode?.rawValue),
            (Key.connectMethod, connectMethod?.rawValue),
            (Key.role, role?.rawValue),
            (Key.peerKind, peerKind?.rawValue),
            (Key.peerOutcome, peerOutcome?.rawValue),
            (Key.existingAccount, existingAccount),
            (Key.accountSwitch, accountSwitch),
            (Key.flowVersion, flowVersion.rawValue),
            (Key.uiVersion, uiVersion.rawValue),
            (Key.lastStep, steps.last?.rawValue),
            (Key.steps, stepsParameter),
            (Key.deviceAuthShown, deviceAuthShown),
            (Key.cameraPermission, cameraPermission?.rawValue),
            (Key.syncThisDeviceFallback, syncThisDeviceFallback),
            (Key.statusReason, statusReason),
            (Key.timeoutStage, timeoutStage),
            (Key.totalLatency, totalDuration.stringValue(bucket)),
            (Key.lastStepLatency, lastStepDuration.stringValue(bucket)),
            (Key.preparingSyncLatency, preparingSyncDuration?.stringValue(bucket)),
        ])
    }
}
