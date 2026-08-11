//
//  PromptCooldownMocks.swift
//  DuckDuckGo
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

import Foundation
@testable import DuckDuckGo

final class MockPromptCooldownStore: PromptCooldownStore {
    var lastPresentationTimestamp: TimeInterval?
}

final class MockPromptCooldownIntervalProvider: PromptCooldownIntervalProviding {
    var cooldownInterval: Int = 24
}

final class MockPromptCooldownManager: PromptCooldownManaging {
    var cooldownInfoToReturn: PromptCooldownInfo = .notInCoolDown

    private(set) var didCallRecordLastPromptPresentationTimestamp = false
    private(set) var recordLastPromptPresentationTimestampCallCount = 0

    var cooldownInfo: PromptCooldownInfo {
        cooldownInfoToReturn
    }

    func recordLastPromptPresentationTimestamp() {
        didCallRecordLastPromptPresentationTimestamp = true
        recordLastPromptPresentationTimestampCallCount += 1
    }
}

@MainActor
final class MockPromoQueueCooldownPolicy: PromoQueueCooldownPolicying {
    var remoteMessageAdmissionDecision: PromoQueueCooldownDecision = .eligible
    var modalAdmissionDecision: PromoQueueCooldownDecision = .eligible
    var remoteMessageAdmissionDecisionProvider: ((Date) -> PromoQueueCooldownDecision)?
    var modalAdmissionDecisionProvider: ((Date) -> PromoQueueCooldownDecision)?
    var snapshotToReturn: PromoQueueCooldownSnapshot = .empty
    var onEvaluateRemoteMessageAdmission: ((Date) -> Void)?
    var onEvaluateModalAdmission: ((Date) -> Void)?

    private(set) var remoteMessageAdmissionDates = [Date]()
    private(set) var modalAdmissionDates = [Date]()
    private(set) var confirmedRemoteMessageAppearanceDates = [Date]()
    private(set) var snapshotDates = [Date]()

    func evaluateRemoteMessageAdmission(now: Date) -> PromoQueueCooldownDecision {
        remoteMessageAdmissionDates.append(now)
        onEvaluateRemoteMessageAdmission?(now)
        return remoteMessageAdmissionDecisionProvider?(now) ?? remoteMessageAdmissionDecision
    }

    func evaluateModalAdmission(now: Date) -> PromoQueueCooldownDecision {
        modalAdmissionDates.append(now)
        onEvaluateModalAdmission?(now)
        return modalAdmissionDecisionProvider?(now) ?? modalAdmissionDecision
    }

    func recordConfirmedRemoteMessageAppearance(at date: Date) {
        confirmedRemoteMessageAppearanceDates.append(date)
    }

    func snapshot(now: Date) -> PromoQueueCooldownSnapshot {
        snapshotDates.append(now)
        return snapshotToReturn
    }
}

extension PromptCooldownInfo {
    static let inCoolDown: PromptCooldownInfo = .init(
        isInCooldownPeriod: true,
        lastPresentationDate: Date(),
        nextPresentationDate: Date(timeIntervalSinceNow: 100)
    )
    static let notInCoolDown: PromptCooldownInfo = .init(
        isInCooldownPeriod: false,
        lastPresentationDate: nil,
        nextPresentationDate: Date()
    )
}
