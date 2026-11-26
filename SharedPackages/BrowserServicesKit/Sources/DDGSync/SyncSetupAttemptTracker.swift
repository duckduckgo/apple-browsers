//
//  SyncSetupAttemptTracker.swift
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
import WideEvent

@MainActor
public final class SyncSetupAttemptTracker {

    public typealias Outcome = SyncSetupWideEventData.Outcome
    public typealias SetupMode = SyncSetupWideEventData.SetupMode
    public typealias Step = SyncSetupWideEventData.Step

    public enum SuccessStep: CaseIterable {
        case recoveryCodeShown
        case successScreenShown

        var step: Step {
            switch self {
            case .recoveryCodeShown: return .recoveryCodeShown
            case .successScreenShown: return .successScreenShown
            }
        }
    }

    private let wideEvent: WideEventManaging
    private let isEnabled: () -> Bool
    private let now: () -> Date
    private var attempt: SyncSetupWideEventData?
    private var errorOnScreen: SyncConnectionError?

    public init(wideEvent: WideEventManaging,
                isEnabled: @escaping () -> Bool,
                now: @escaping () -> Date = Date.init) {
        self.wideEvent = wideEvent
        self.isEnabled = isEnabled
        self.now = now
    }

    public func start(entryPoint: String?,
                      setupMode: SetupMode?,
                      existingAccount: Bool,
                      flowVersion: SyncSetupWideEventData.FlowVersion,
                      uiVersion: SyncSetupWideEventData.UIVersion) {
        if let attempt {
            close(attempt, status: .unknown(reason: SyncSetupWideEventData.StatusReason.duplicated))
        }
        guard isEnabled() else { return }

        let attempt = SyncSetupWideEventData(existingAccount: existingAccount,
                                             flowVersion: flowVersion,
                                             uiVersion: uiVersion,
                                             setupMode: setupMode,
                                             startedAt: now(),
                                             contextData: WideEventContextData(name: entryPoint))
        self.attempt = attempt
        wideEvent.startFlow(attempt)
    }

    public func recordStep(_ step: Step) {
        update { $0.recordStep(step, at: now()) }
    }

    public func switchMode(to mode: SetupMode) {
        update { $0.setupMode = mode }
    }

    public func recordDeviceAuthShown() {
        update {
            $0.deviceAuthShown = true
            $0.recordStep(.deviceAuth, at: now())
        }
    }

    public func recordCameraPermission(_ permission: SyncSetupWideEventData.CameraPermission) {
        update { $0.cameraPermission = permission }
    }

    public func recordSyncThisDeviceOffer() {
        update {
            $0.syncThisDeviceFallback = true
            $0.recordStep(.syncThisDeviceOffer, at: now())
        }
    }

    public func recordErrorScreen(for error: SyncConnectionError) {
        guard attempt != nil else { return }
        errorOnScreen = error
        recordStep(.errorScreen)
    }

    public func closeErrorScreen() {
        guard let errorOnScreen, attempt?.steps.last == .errorScreen else { return }
        end(with: errorOnScreen)
    }

    public func end(with error: SyncConnectionError) {
        end(error.syncSetupWideEventOutcome)
    }

    public func succeed(_ successStep: SuccessStep) {
        recordStep(successStep.step)
        end(Outcome(status: .success))
    }

    public func end(_ outcome: Outcome) {
        guard let attempt else { return }
        attempt.statusReason = outcome.statusReason
        attempt.timeoutStage = outcome.timeoutStage
        close(attempt, status: outcome.status)
    }

    private func close(_ attempt: SyncSetupWideEventData, status: WideEventStatus) {
        attempt.end(at: now())
        wideEvent.completeFlow(attempt, status: status, onComplete: { _, _ in })
        self.attempt = nil
        errorOnScreen = nil
    }

    private func update(_ change: (SyncSetupWideEventData) -> Void) {
        guard let attempt else { return }
        change(attempt)
        wideEvent.updateFlow(attempt)
    }
}
