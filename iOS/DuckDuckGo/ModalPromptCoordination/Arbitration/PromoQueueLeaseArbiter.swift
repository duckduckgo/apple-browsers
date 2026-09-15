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

struct PromoQueueModalOwnershipIdentity: Hashable {
    fileprivate let id: UUID

    var diagnosticDescription: String {
        id.uuidString
    }

    fileprivate init() {
        id = UUID()
    }
}

enum PromoQueueLeaseOwnerSnapshot: Equatable {
    case modal(ownershipIdentity: PromoQueueModalOwnershipIdentity)
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

    var modalOwnershipIdentity: PromoQueueModalOwnershipIdentity? {
        guard case .modal(let ownershipIdentity) = owner else { return nil }
        return ownershipIdentity
    }
}

enum PromoQueueModalLeaseAcquisitionResult {
    /// The caller now owns the lease and is responsible for releasing it.
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
    let ownershipIdentity: PromoQueueModalOwnershipIdentity

    private var releaseHandler: (() -> Void)?

    fileprivate init(
        ownershipIdentity: PromoQueueModalOwnershipIdentity,
        releaseHandler: @escaping () -> Void
    ) {
        self.ownershipIdentity = ownershipIdentity
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
        let ownershipIdentity: PromoQueueModalOwnershipIdentity
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
        switch owner {
        case .modal(let record) where record.token != nil:
            return PromoQueueLeaseSnapshot(owner: .modal(ownershipIdentity: record.ownershipIdentity))
        case .remoteMessage(let record) where record.token != nil:
            return PromoQueueLeaseSnapshot(
                owner: .remoteMessage(
                    messageID: record.messageID,
                    acquisitionIdentity: record.acquisitionIdentity,
                    appearanceConfirmed: record.appearanceConfirmed
                )
            )
        case .modal, .remoteMessage, nil:
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

        let ownershipIdentity = PromoQueueModalOwnershipIdentity()
        let lease = PromoQueueModalLease(
            ownershipIdentity: ownershipIdentity,
            releaseHandler: { [weak self] in
                self?.releaseModalLease(ownershipIdentity: ownershipIdentity)
            }
        )
        owner = .modal(
            ModalLeaseRecord(
                ownershipIdentity: ownershipIdentity,
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

    private func releaseModalLease(ownershipIdentity: PromoQueueModalOwnershipIdentity) {
        guard case .modal(let record) = owner,
              record.ownershipIdentity == ownershipIdentity else {
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
