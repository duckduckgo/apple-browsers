//
//  NewTabPagePromoCoordination.swift
//  DuckDuckGo
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

enum PromoCoordinationMode: Equatable {
    case legacy
    case coordinated
}

/// Retains one raw arbiter acquisition and connects its first valid appearance to queue history.
@MainActor
final class PromoQueueRemoteMessageLease {
    let messageID: String
    let acquisitionIdentity: PromoQueueAcquisitionIdentity

    private let arbiterLease: PromoQueueRemoteMessageArbiterLease
    private let cooldownPolicy: PromoQueueCooldownPolicying

    init(
        arbiterLease: PromoQueueRemoteMessageArbiterLease,
        cooldownPolicy: PromoQueueCooldownPolicying
    ) {
        messageID = arbiterLease.messageID
        acquisitionIdentity = arbiterLease.acquisitionIdentity
        self.arbiterLease = arbiterLease
        self.cooldownPolicy = cooldownPolicy
    }

    func markShown() -> Bool {
        guard arbiterLease.confirmAppearance() else {
            return false
        }

        cooldownPolicy.recordConfirmedRemoteMessageAppearance()
        return true
    }

    func release() {
        arbiterLease.release()
    }
}

/// The source-level admission contract used by the shared NTP message configuration.
/// Renderers do not participate in promo ownership.
@MainActor
protocol PromoGating: AnyObject {
    var mode: PromoCoordinationMode { get }

    func tryAcquireRemoteMessageLease(for messageID: String) -> PromoQueueRemoteMessageLease?
}
