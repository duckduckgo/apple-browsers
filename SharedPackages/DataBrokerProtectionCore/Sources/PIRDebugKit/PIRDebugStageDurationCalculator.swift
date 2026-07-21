//
//  PIRDebugStageDurationCalculator.swift
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
import DataBrokerProtectionCore

/// A public `StageDurationCalculator & DebugEventReporting` that emits `PIRDebugEvent`s and does no
/// real timing. Promotes/replaces the app-side private `FakeStageDurationCalculator`; timing methods
/// are no-ops and `isFreeScan` is `true`. Step 3 will make the debug window use this type.
public final class PIRDebugStageDurationCalculator: StageDurationCalculator, DebugEventReporting {

    public var attemptId: UUID = UUID()
    public var isImmediateOperation: Bool = false
    public var isFreeScan: Bool? = true
    public var tries: Int = 1

    private let profileQueryLabel: String
    private let onEvent: (PIRDebugEvent) -> Void

    /// - Parameters:
    ///   - profileQueryLabel: Human-readable label for the profile query this calculator serves.
    ///   - onEvent: Sink for every recorded debug event.
    public init(profileQueryLabel: String, onEvent: @escaping (PIRDebugEvent) -> Void) {
        self.profileQueryLabel = profileQueryLabel
        self.onEvent = onEvent
    }

    public func durationSinceLastStage() -> Double { 0 }
    public func durationSinceStartTime() -> Double { 0 }

    public func fireOptOutStart() {}
    public func fireOptOutEmailGenerate() {}
    public func fireOptOutCaptchaParse() {}
    public func fireOptOutCaptchaSend() {}
    public func fireOptOutCaptchaSolve() {}
    public func fireOptOutSubmit() {}
    public func fireOptOutFillForm() {}
    public func fireOptOutEmailReceive() {}
    public func fireOptOutEmailConfirm() {}
    public func fireOptOutEmailGetData() {}
    public func fireOptOutValidate() {}
    public func fireOptOutSubmitSuccess(tries: Int) {}
    public func fireOptOutFailure(tries: Int, error: Error) {}
    public func fireOptOutConditionFound() {}
    public func fireOptOutConditionNotFound() {}

#if os(iOS)
    public func fireScanStarted() {}
#endif

    public func fireScanSuccess(matchesFound: Int) {}
    public func fireScanNoResults() {}
    public func fireScanError(error: Error) {}

    public func setStage(_ stage: Stage) {}
    public func setEmailPattern(_ emailPattern: String?) {}
    public func setLastAction(_ action: Action) {}

    public func resetTries() { tries = 1 }
    public func incrementTries() { tries += 1 }

    public func recordDebugEvent(kind: DebugEventKind, actionType: ActionType?, details: String) {
        onEvent(PIRDebugEvent(profileQueryLabel: profileQueryLabel,
                              kind: PIRDebugEvent.Kind(kind),
                              actionType: actionType?.rawValue,
                              details: details))
    }
}
