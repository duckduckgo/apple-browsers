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

import Foundation
import os.log

/// Identifies one logical remote-message ownership lifetime. The service mints a new ID for every successful acquisition.
struct PromoQueueRemoteMessageSession: Hashable {
    let id: UUID
    let messageID: String
}

/// Identifies one physical renderer authorization within a logical remote-message session.
struct PromoQueueRemoteMessagePresentation: Hashable {
    let id: UUID
    let session: PromoQueueRemoteMessageSession
}

/// The latest remote-message candidate reported by one renderer.
enum PromoQueueRemoteMessageCandidateState: Equatable {
    case none
    case available(messageID: String)
    case unrenderable(messageID: String)
}

/// A verified reason why an outgoing renderer can no longer contribute visible remote-message pixels.
enum PromoQueueRemoteMessageRemovalTerminal: Equatable {
    case animationCompleted
    case hostDetached
    case sourceRemovedWithoutAnimation
}

enum PromoQueueRemoteMessageAppearanceResult: Equatable {
    case accepted
    case rejected
}

/// A mounted NTP surface that can render one service-authorized remote-message presentation.
@MainActor
protocol NewTabPagePromoRendering: AnyObject {
    /// Allows the service to verify a reported host-detachment terminal against the exact renderer generation.
    var isRemoteMessageRendererAttachedToWindow: Bool { get }
    /// Defensive proof used when `showRemoteMessage` rejects: `true` means the service must fail closed.
    var hasPublishedRemoteMessagePresentation: Bool { get }

    /// Returns `false` only when this renderer owns no coordinated presentation and atomically publishes no content.
    func showRemoteMessage(_ presentation: PromoQueueRemoteMessagePresentation) -> Bool

    /// Begins removal. The exact presentation and removal identities must be echoed through the registration at terminal.
    func hideRemoteMessage(
        _ presentation: PromoQueueRemoteMessagePresentation,
        removalID: UUID
    )
}

/// An idempotently removable connection between one renderer generation and the app-scoped coordination service.
@MainActor
final class NewTabPagePromoRendererRegistration {
    typealias UpdateHandler = @MainActor (PromoQueueRemoteMessageCandidateState, Bool) -> Void
    typealias AppearanceHandler = @MainActor (UUID, UUID, Bool) -> PromoQueueRemoteMessageAppearanceResult
    typealias RemovalTerminalHandler = @MainActor (UUID, UUID, UUID, PromoQueueRemoteMessageRemovalTerminal) -> Void

    private let updateHandler: UpdateHandler
    private let appearanceHandler: AppearanceHandler
    private let removalTerminalHandler: RemovalTerminalHandler
    private var deregistrationHandler: (@MainActor () -> Void)?
    private let isNoOpRegistration: Bool

    init(
        updateHandler: @escaping UpdateHandler = { _, _ in },
        appearanceHandler: @escaping AppearanceHandler = { _, _, _ in .rejected },
        removalTerminalHandler: @escaping RemovalTerminalHandler = { _, _, _, _ in },
        deregistrationHandler: (@MainActor () -> Void)? = nil,
        isNoOpRegistration: Bool = false
    ) {
        self.updateHandler = updateHandler
        self.appearanceHandler = appearanceHandler
        self.removalTerminalHandler = removalTerminalHandler
        self.deregistrationHandler = deregistrationHandler
        self.isNoOpRegistration = isNoOpRegistration
    }

    deinit {
        guard !isNoOpRegistration, deregistrationHandler != nil else {
            return
        }
        Logger.modalPrompt.error(
            "[Promo Queue] - A renderer registration token deinitialized without explicit deregistration. Ownership will fail closed."
        )
    }

    func update(candidate: PromoQueueRemoteMessageCandidateState, isEligible: Bool) {
        updateHandler(candidate, isEligible)
    }

    func confirmAppearance(
        sessionID: UUID,
        presentationID: UUID,
        isAttachedToWindow: Bool
    ) -> PromoQueueRemoteMessageAppearanceResult {
        appearanceHandler(sessionID, presentationID, isAttachedToWindow)
    }

    func removalDidReachTerminal(
        sessionID: UUID,
        presentationID: UUID,
        removalID: UUID,
        terminal: PromoQueueRemoteMessageRemovalTerminal
    ) {
        removalTerminalHandler(sessionID, presentationID, removalID, terminal)
    }

    func deregister() {
        let deregistrationHandler = deregistrationHandler
        self.deregistrationHandler = nil
        deregistrationHandler?()
    }
}

/// Coordinates app-scoped selection and ownership for NTP remote-message renderers.
@MainActor
protocol NewTabPagePromoCoordinating: AnyObject {
    var promoCoordinationMode: PromoCoordinationMode { get }

    func registerRemoteMessageRenderer(
        id: UUID,
        target: NewTabPagePromoRendering
    ) -> NewTabPagePromoRendererRegistration
}
