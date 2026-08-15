//
//  PromoQueueLeaseArbiter.swift
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

import Foundation

struct PromoQueueAcquisitionIdentity: Hashable {
    fileprivate let id: UUID

    var diagnosticDescription: String {
        id.uuidString
    }

    fileprivate init() {
        id = UUID()
    }
}

struct PromoQueueModalAttemptIdentity: Hashable {
    fileprivate let acquisitionIdentity: PromoQueueAcquisitionIdentity

    fileprivate init(acquisitionIdentity: PromoQueueAcquisitionIdentity) {
        self.acquisitionIdentity = acquisitionIdentity
    }

    var diagnosticDescription: String {
        acquisitionIdentity.diagnosticDescription
    }
}

enum PromoQueueLeaseOwnerSnapshot: Equatable {
    case modal(attemptIdentity: PromoQueueModalAttemptIdentity)
    case remoteMessage(
        messageID: String,
        acquisitionIdentity: PromoQueueAcquisitionIdentity,
        appearanceConfirmed: Bool
    )
}

struct PromoQueueLeaseSnapshot: Equatable {
    let owner: PromoQueueLeaseOwnerSnapshot?

    var hasModalLease: Bool {
        guard case .modal = owner else { return false }
        return true
    }

    var modalAttemptIdentity: PromoQueueModalAttemptIdentity? {
        guard case .modal(let attemptIdentity) = owner else { return nil }
        return attemptIdentity
    }
}

enum PromoQueueModalLeaseAcquisitionResult {
    case acquired(PromoQueueModalLease)
    case blockedByModal
    case blockedByRemoteMessage(messageID: String)
}

enum PromoQueueRemoteMessageLeaseAcquisitionResult {
    case acquired(PromoQueueRemoteMessageArbiterLease)
    case blockedByModal
    case blockedByRemoteMessage(messageID: String)
}

@MainActor
protocol PromoQueueLeaseArbitrating: AnyObject {
    var snapshot: PromoQueueLeaseSnapshot { get }

    func acquireModalLease() -> PromoQueueModalLeaseAcquisitionResult
    func acquireRemoteMessageLease(for messageID: String) -> PromoQueueRemoteMessageLeaseAcquisitionResult
}

@MainActor
final class PromoQueueModalLease {
    let attemptIdentity: PromoQueueModalAttemptIdentity

    private var releaseHandler: (() -> Void)?

    fileprivate init(
        attemptIdentity: PromoQueueModalAttemptIdentity,
        releaseHandler: @escaping () -> Void
    ) {
        self.attemptIdentity = attemptIdentity
        self.releaseHandler = releaseHandler
    }

    func release() {
        let releaseHandler = releaseHandler
        self.releaseHandler = nil
        releaseHandler?()
    }
}

@MainActor
final class PromoQueueRemoteMessageArbiterLease {
    let messageID: String
    let acquisitionIdentity: PromoQueueAcquisitionIdentity

    private var confirmAppearanceHandler: (() -> Bool)?
    private var releaseHandler: (() -> Void)?

    fileprivate init(
        messageID: String,
        acquisitionIdentity: PromoQueueAcquisitionIdentity,
        confirmAppearanceHandler: @escaping () -> Bool,
        releaseHandler: @escaping () -> Void
    ) {
        self.messageID = messageID
        self.acquisitionIdentity = acquisitionIdentity
        self.confirmAppearanceHandler = confirmAppearanceHandler
        self.releaseHandler = releaseHandler
    }

    func confirmAppearance() -> Bool {
        confirmAppearanceHandler?() ?? false
    }

    func release() {
        confirmAppearanceHandler = nil
        let releaseHandler = releaseHandler
        self.releaseHandler = nil
        releaseHandler?()
    }
}

@MainActor
final class PromoQueueLeaseArbiter: PromoQueueLeaseArbitrating {
    private struct ModalLeaseRecord {
        let acquisitionIdentity: PromoQueueAcquisitionIdentity
        let attemptIdentity: PromoQueueModalAttemptIdentity
        weak var token: PromoQueueModalLease?
    }

    private struct RemoteMessageLeaseRecord {
        let messageID: String
        let acquisitionIdentity: PromoQueueAcquisitionIdentity
        var appearanceConfirmed: Bool
        weak var token: PromoQueueRemoteMessageArbiterLease?
    }

    private enum Owner {
        case modal(ModalLeaseRecord)
        case remoteMessage(RemoteMessageLeaseRecord)
    }

    private var owner: Owner?

    var snapshot: PromoQueueLeaseSnapshot {
        pruneOwnerWithDeallocatedToken()

        switch owner {
        case .modal(let record):
            return PromoQueueLeaseSnapshot(owner: .modal(attemptIdentity: record.attemptIdentity))
        case .remoteMessage(let record):
            return PromoQueueLeaseSnapshot(
                owner: .remoteMessage(
                    messageID: record.messageID,
                    acquisitionIdentity: record.acquisitionIdentity,
                    appearanceConfirmed: record.appearanceConfirmed
                )
            )
        case nil:
            return PromoQueueLeaseSnapshot(owner: nil)
        }
    }

    func acquireModalLease() -> PromoQueueModalLeaseAcquisitionResult {
        pruneOwnerWithDeallocatedToken()

        switch owner {
        case .modal:
            return .blockedByModal
        case .remoteMessage(let record):
            return .blockedByRemoteMessage(messageID: record.messageID)
        case nil:
            break
        }

        let acquisitionIdentity = PromoQueueAcquisitionIdentity()
        let attemptIdentity = PromoQueueModalAttemptIdentity(acquisitionIdentity: acquisitionIdentity)
        let lease = PromoQueueModalLease(
            attemptIdentity: attemptIdentity,
            releaseHandler: { [weak self] in
                self?.releaseModalLease(acquisitionIdentity: acquisitionIdentity)
            }
        )
        owner = .modal(
            ModalLeaseRecord(
                acquisitionIdentity: acquisitionIdentity,
                attemptIdentity: attemptIdentity,
                token: lease
            )
        )
        return .acquired(lease)
    }

    func acquireRemoteMessageLease(for messageID: String) -> PromoQueueRemoteMessageLeaseAcquisitionResult {
        pruneOwnerWithDeallocatedToken()

        switch owner {
        case .modal:
            return .blockedByModal
        case .remoteMessage(let record):
            return .blockedByRemoteMessage(messageID: record.messageID)
        case nil:
            break
        }

        let acquisitionIdentity = PromoQueueAcquisitionIdentity()
        let lease = PromoQueueRemoteMessageArbiterLease(
            messageID: messageID,
            acquisitionIdentity: acquisitionIdentity,
            confirmAppearanceHandler: { [weak self] in
                self?.confirmRemoteMessageAppearance(acquisitionIdentity: acquisitionIdentity) ?? false
            },
            releaseHandler: { [weak self] in
                self?.releaseRemoteMessageLease(acquisitionIdentity: acquisitionIdentity)
            }
        )
        owner = .remoteMessage(
            RemoteMessageLeaseRecord(
                messageID: messageID,
                acquisitionIdentity: acquisitionIdentity,
                appearanceConfirmed: false,
                token: lease
            )
        )
        return .acquired(lease)
    }

    private func confirmRemoteMessageAppearance(acquisitionIdentity: PromoQueueAcquisitionIdentity) -> Bool {
        guard case .remoteMessage(var record) = owner,
              record.acquisitionIdentity == acquisitionIdentity,
              !record.appearanceConfirmed else {
            return false
        }

        record.appearanceConfirmed = true
        owner = .remoteMessage(record)
        return true
    }

    private func releaseModalLease(acquisitionIdentity: PromoQueueAcquisitionIdentity) {
        guard case .modal(let record) = owner,
              record.acquisitionIdentity == acquisitionIdentity else {
            return
        }

        owner = nil
    }

    private func releaseRemoteMessageLease(acquisitionIdentity: PromoQueueAcquisitionIdentity) {
        guard case .remoteMessage(let record) = owner,
              record.acquisitionIdentity == acquisitionIdentity else {
            return
        }

        owner = nil
    }

    private func pruneOwnerWithDeallocatedToken() {
        switch owner {
        case .modal(let record) where record.token == nil:
            owner = nil
        case .remoteMessage(let record) where record.token == nil:
            owner = nil
        default:
            break
        }
    }
}
