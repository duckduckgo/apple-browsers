//
//  PromoQueueCooldownPolicy.swift
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
import Persistence

struct PromoQueueCooldownSnapshot: Equatable {
    let lastConfirmedModalAppearance: Date?
    let lastConfirmedRemoteMessageAppearance: Date?
    let nextRemoteMessageEligibility: Date?
    let nextModalEligibility: Date?
    let provisionalRemoteMessageIdentity: VisiblePromoIdentity?

    static let empty = PromoQueueCooldownSnapshot(
        lastConfirmedModalAppearance: nil,
        lastConfirmedRemoteMessageAppearance: nil,
        nextRemoteMessageEligibility: nil,
        nextModalEligibility: nil,
        provisionalRemoteMessageIdentity: nil
    )
}

enum PromoQueueModalCooldownAdmissionResult: Equatable {
    case eligible
    case blocked(until: Date)
}

enum PromoQueueRemoteMessageCooldownReservationResult {
    case reserved(PromoQueueRemoteMessageCooldownReservation)
    case blocked(until: Date)
    case provisionalReservationInProgress
}

protocol PromoQueueRemoteMessageCooldownStoring: AnyObject {
    var lastConfirmedRemoteMessageTimestamp: TimeInterval? { get set }
}

final class PromoQueueRemoteMessageCooldownKeyValueFilesStore: PromoQueueRemoteMessageCooldownStoring {
    enum StorageKey {
        static let lastConfirmedRemoteMessageTimestamp = "com.duckduckgo.promo-queue.last-confirmed-remote-message-timestamp"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var lastConfirmedRemoteMessageTimestamp: TimeInterval? {
        get {
            do {
                return try keyValueStore.object(forKey: StorageKey.lastConfirmedRemoteMessageTimestamp) as? TimeInterval
            } catch {
                Logger.modalPrompt.error("[Promo Queue] - Failed to read the last confirmed RMF timestamp.")
                return nil
            }
        }
        set {
            do {
                try keyValueStore.set(newValue, forKey: StorageKey.lastConfirmedRemoteMessageTimestamp)
            } catch {
                Logger.modalPrompt.error("[Promo Queue] - Failed to write the last confirmed RMF timestamp.")
            }
        }
    }
}

@MainActor
protocol PromoQueueCooldownPolicying: AnyObject {
    var snapshot: PromoQueueCooldownSnapshot { get }

    func evaluateModalAdmission() -> PromoQueueModalCooldownAdmissionResult
    func reserveRemoteMessageAdmission(for identity: VisiblePromoIdentity) -> PromoQueueRemoteMessageCooldownReservationResult
    func resetTransientState()
}

@MainActor
final class PromoQueueRemoteMessageCooldownReservation {
    private var confirmationHandler: (() -> Bool)?
    private var releaseHandler: (() -> Bool)?

    fileprivate init(
        confirmationHandler: @escaping () -> Bool,
        releaseHandler: @escaping () -> Bool
    ) {
        self.confirmationHandler = confirmationHandler
        self.releaseHandler = releaseHandler
    }

    @discardableResult
    func confirm() -> Bool {
        guard let confirmationHandler else {
            return false
        }

        self.confirmationHandler = nil
        releaseHandler = nil
        return confirmationHandler()
    }

    @discardableResult
    func release() -> Bool {
        guard let releaseHandler else {
            return false
        }

        confirmationHandler = nil
        self.releaseHandler = nil
        return releaseHandler()
    }
}

@MainActor
final class PromoQueueCooldownPolicy: PromoQueueCooldownPolicying {
    static let remoteMessageTargetInterval: TimeInterval = 10 * 60
    static let modalAfterRemoteMessageInterval: TimeInterval = 24 * 60 * 60

    private struct ProvisionalRemoteMessageReservation {
        let id: UUID
        let identity: VisiblePromoIdentity
        weak var token: PromoQueueRemoteMessageCooldownReservation?
    }

    private let modalPresentationStore: PromptCooldownStore
    private let remoteMessagePresentationStore: PromoQueueRemoteMessageCooldownStoring
    private let dateProvider: () -> Date
    private var provisionalRemoteMessageReservation: ProvisionalRemoteMessageReservation?

    init(
        modalPresentationStore: PromptCooldownStore,
        remoteMessagePresentationStore: PromoQueueRemoteMessageCooldownStoring,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.modalPresentationStore = modalPresentationStore
        self.remoteMessagePresentationStore = remoteMessagePresentationStore
        self.dateProvider = dateProvider
    }

    var snapshot: PromoQueueCooldownSnapshot {
        pruneAbandonedReservation()
        let lastModalAppearance = modalPresentationStore.lastPresentationTimestamp.map(Date.init(timeIntervalSince1970:))
        let lastRemoteMessageAppearance = remoteMessagePresentationStore.lastConfirmedRemoteMessageTimestamp.map(Date.init(timeIntervalSince1970:))

        return PromoQueueCooldownSnapshot(
            lastConfirmedModalAppearance: lastModalAppearance,
            lastConfirmedRemoteMessageAppearance: lastRemoteMessageAppearance,
            nextRemoteMessageEligibility: nextRemoteMessageEligibility(
                lastModalAppearance: lastModalAppearance,
                lastRemoteMessageAppearance: lastRemoteMessageAppearance
            ),
            nextModalEligibility: lastRemoteMessageAppearance?.addingTimeInterval(Self.modalAfterRemoteMessageInterval),
            provisionalRemoteMessageIdentity: provisionalRemoteMessageReservation?.identity
        )
    }

    func evaluateModalAdmission() -> PromoQueueModalCooldownAdmissionResult {
        guard let nextModalEligibility = snapshot.nextModalEligibility,
              dateProvider() < nextModalEligibility else {
            return .eligible
        }

        return .blocked(until: nextModalEligibility)
    }

    func reserveRemoteMessageAdmission(for identity: VisiblePromoIdentity) -> PromoQueueRemoteMessageCooldownReservationResult {
        pruneAbandonedReservation()
        guard provisionalRemoteMessageReservation == nil else {
            return .provisionalReservationInProgress
        }

        if let nextRemoteMessageEligibility = snapshot.nextRemoteMessageEligibility,
           dateProvider() < nextRemoteMessageEligibility {
            return .blocked(until: nextRemoteMessageEligibility)
        }

        let reservationID = UUID()
        let reservation = PromoQueueRemoteMessageCooldownReservation(
            confirmationHandler: { [weak self] in
                self?.confirmRemoteMessageAppearance(reservationID: reservationID) ?? false
            },
            releaseHandler: { [weak self] in
                self?.releaseRemoteMessageReservation(reservationID: reservationID) ?? false
            }
        )
        provisionalRemoteMessageReservation = ProvisionalRemoteMessageReservation(
            id: reservationID,
            identity: identity,
            token: reservation
        )

        return .reserved(reservation)
    }

    func resetTransientState() {
        provisionalRemoteMessageReservation = nil
    }

    private func nextRemoteMessageEligibility(
        lastModalAppearance: Date?,
        lastRemoteMessageAppearance: Date?
    ) -> Date? {
        let modalBoundary = lastModalAppearance?.addingTimeInterval(Self.remoteMessageTargetInterval)
        let remoteMessageBoundary = lastRemoteMessageAppearance?.addingTimeInterval(Self.remoteMessageTargetInterval)

        return [modalBoundary, remoteMessageBoundary]
            .compactMap { $0 }
            .max()
    }

    private func pruneAbandonedReservation() {
        if provisionalRemoteMessageReservation?.token == nil {
            provisionalRemoteMessageReservation = nil
        }
    }

    private func confirmRemoteMessageAppearance(reservationID: UUID) -> Bool {
        guard provisionalRemoteMessageReservation?.id == reservationID else {
            return false
        }

        provisionalRemoteMessageReservation = nil
        remoteMessagePresentationStore.lastConfirmedRemoteMessageTimestamp = dateProvider().timeIntervalSince1970
        return true
    }

    private func releaseRemoteMessageReservation(reservationID: UUID) -> Bool {
        guard provisionalRemoteMessageReservation?.id == reservationID else {
            return false
        }

        provisionalRemoteMessageReservation = nil
        return true
    }
}

final class InMemoryPromoQueueRemoteMessageCooldownStore: PromoQueueRemoteMessageCooldownStoring {
    var lastConfirmedRemoteMessageTimestamp: TimeInterval?
}

final class InMemoryPromptCooldownStore: PromptCooldownStore {
    var lastPresentationTimestamp: TimeInterval?
}

@MainActor
final class PromoQueueCooldownScheduledTask {
    private var cancellationHandler: (() -> Void)?

    init(cancellationHandler: @escaping () -> Void = {}) {
        self.cancellationHandler = cancellationHandler
    }

    func cancel() {
        let cancellationHandler = cancellationHandler
        self.cancellationHandler = nil
        cancellationHandler?()
    }
}

@MainActor
protocol PromoQueueCooldownScheduling: AnyObject {
    func schedule(at date: Date, execute: @escaping @MainActor () -> Void) -> PromoQueueCooldownScheduledTask
}

@MainActor
final class PromoQueueCooldownScheduler: PromoQueueCooldownScheduling {
    func schedule(at date: Date, execute: @escaping @MainActor () -> Void) -> PromoQueueCooldownScheduledTask {
        let workItem = DispatchWorkItem(block: execute)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, date.timeIntervalSinceNow), execute: workItem)
        return PromoQueueCooldownScheduledTask {
            workItem.cancel()
        }
    }
}
