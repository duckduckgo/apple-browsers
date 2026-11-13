//
//  FakeStageDurationCalculator.swift
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

public final class FakeStageDurationCalculator: StageDurationCalculator, DebugEventReporting {
    public var attemptId: UUID = UUID()
    public var isImmediateOperation: Bool = false
    public var isFreeScan: Bool?
    public var tries = 1
    private let onDebugEvent: ((DebugEventKind, ActionType?, String) -> Void)?

    public init(onDebugEvent: ((DebugEventKind, ActionType?, String) -> Void)? = nil) {
        self.onDebugEvent = onDebugEvent
    }

    public func durationSinceLastStage() -> Double { 0.0 }
    public func durationSinceStartTime() -> Double { 0.0 }
    public func awakeDurationSinceStartTime() -> Double { 0.0 }
    public func fireOptOutStart() {}
    public func setEmailPattern(_ emailPattern: String?) {}
    public func fireOptOutEmailGenerate() {}
    public func fireOptOutCaptchaParse() {}
    public func fireOptOutCaptchaSend() {}
    public func fireOptOutCaptchaSolve() {}
    public func fireOptOutSubmit() {}
    public func fireOptOutEmailReceive() {}
    public func fireOptOutEmailConfirm() {}
    public func fireOptOutEmailGetData() {}
    public func fireOptOutFillForm() {}
    public func fireOptOutValidate() {}
    public func fireOptOutSubmitSuccess(tries: Int) {}
    public func fireOptOutFailure(tries: Int, error: Error) {}
    public func fireScanStarted() {}
    public func fireScanSuccess(matchesFound: Int) {}
    public func fireScanNoResults() {}
    public func fireScanError(error: Error) {}
    public func setStage(_ stage: Stage) {}
    public func setLastAction(_ action: Action) {}
    public func fireOptOutConditionFound() {}
    public func fireOptOutConditionNotFound() {}
    public func resetTries() { tries = 1 }
    public func incrementTries() { tries += 1 }

    public func recordDebugEvent(kind: DebugEventKind, actionType: ActionType?, details: String) {
        onDebugEvent?(kind, actionType, details)
    }
}
