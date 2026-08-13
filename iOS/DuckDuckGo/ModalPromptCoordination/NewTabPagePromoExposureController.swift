//
//  NewTabPagePromoExposureController.swift
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

/// Receives the one renderer selected by the UI-owned exposure controller.
@MainActor
protocol NewTabPagePromoExposureSelectionSinking: AnyObject {
    var promoCoordinationMode: PromoCoordinationMode { get }

    func setSelectedRemoteMessageRendererID(_ rendererID: UUID?)
}

/// A host whose currently presented content may expose one RMF-capable NTP renderer.
///
/// The callback is only an invalidation signal. Its owner must pull `exposedPromoRendererID` again while resolving the
/// current route, so a delayed callback from an inactive host cannot authoritatively select its renderer.
@MainActor
protocol NewTabPagePromoSurfaceProviding: AnyObject {
    var exposedPromoRendererID: UUID? { get }
    var onPromoSurfaceExposureChanged: (() -> Void)? { get set }
}

enum PromoSurfaceBlockerScope: Hashable, CustomStringConvertible {
    case renderer(UUID)
    case allRenderers

    fileprivate func includes(rendererID: UUID) -> Bool {
        switch self {
        case .renderer(let blockedRendererID):
            return blockedRendererID == rendererID
        case .allRenderers:
            return true
        }
    }

    var description: String {
        switch self {
        case .renderer(let rendererID):
            return "renderer(\(rendererID.uuidString))"
        case .allRenderers:
            return "allRenderers"
        }
    }
}

enum PromoSurfaceBlockerReason: Hashable, CustomStringConvertible {
    case daxOverlay
    case onboardingOverlay
    case standardNTPVisibilityTransition
    case hostTransition
    case other(String)

    var description: String {
        switch self {
        case .daxOverlay:
            return "daxOverlay"
        case .onboardingOverlay:
            return "onboardingOverlay"
        case .standardNTPVisibilityTransition:
            return "standardNTPVisibilityTransition"
        case .hostTransition:
            return "hostTransition"
        case .other(let identifier):
            return "other(\(identifier))"
        }
    }
}

/// Ephemeral developer-facing provenance for a blocker. Callers should use a stable component name, not user data.
struct PromoSurfaceBlockerSource: Hashable, CustomStringConvertible {
    let identifier: String

    init(_ identifier: String) {
        self.identifier = identifier
    }

    var description: String {
        identifier
    }
}

struct PromoSurfaceBlockerRecord: Equatable {
    let id: UUID
    let scope: PromoSurfaceBlockerScope
    let reason: PromoSurfaceBlockerReason
    let source: PromoSurfaceBlockerSource
}

enum NewTabPagePromoExposureSelectionState: Equatable {
    case noRouteCandidate
    case blocked(candidateRendererID: UUID, blockerIDs: [UUID])
    case selected(rendererID: UUID)
}

/// Read-only, ephemeral projection used by focused tests and Promo Queue diagnostics.
struct NewTabPagePromoExposureSnapshot: Equatable {
    let mode: PromoCoordinationMode
    let routeCandidateRendererID: UUID?
    let effectiveSelectedRendererID: UUID?
    let selectionState: NewTabPagePromoExposureSelectionState
    let activeBlockers: [PromoSurfaceBlockerRecord]
}

@MainActor
protocol PromoSurfaceBlocking: AnyObject {
    func blockPromoSurface(
        scope: PromoSurfaceBlockerScope,
        reason: PromoSurfaceBlockerReason,
        source: PromoSurfaceBlockerSource
    ) -> PromoSurfaceBlockerToken
}

/// Narrow renderer-facing blocker seam that also guarantees explicit cleanup for an exact deregistered renderer.
@MainActor
protocol NewTabPagePromoExposureControlling: PromoSurfaceBlocking {
    func rendererDidDeregister(id rendererID: UUID)
}

/// An explicitly releasable suppression lifetime. Dropping a live token deliberately leaves its blocker record active.
@MainActor
final class PromoSurfaceBlockerToken {
    let id: UUID

    private var releaseHandler: (() -> Void)?

    fileprivate init(id: UUID, releaseHandler: @escaping () -> Void) {
        self.id = id
        self.releaseHandler = releaseHandler
    }

    deinit {
        guard releaseHandler != nil else {
            return
        }

        Logger.modalPrompt.error(
            """
            [Promo Queue] - Promo surface blocker \(self.id.uuidString, privacy: .public) deinitialized without explicit \
            release. Exposure remains blocked.
            """
        )
    }

    /// Explicitly releases this token's blocker. Repeated and stale releases are inert.
    func release() {
        let releaseHandler = releaseHandler
        self.releaseHandler = nil
        releaseHandler?()
    }

    /// Renderer deregistration is an explicit controller cleanup boundary. The controller logs the unreleased record
    /// before invalidating a surviving token, so its later deinitialization does not duplicate that diagnostic.
    fileprivate func invalidateAfterRendererDeregistration() {
        releaseHandler = nil
    }
}

/// UI-owned selection authority for NTP promo renderers.
///
/// The controller filters the route candidate through composable blockers and sends at most one effective renderer ID
/// to the coordination service. It does not own RMF candidates, queue admission, presentations, or removal terminals.
@MainActor
final class NewTabPagePromoExposureController {
    private struct ActiveBlocker {
        let record: PromoSurfaceBlockerRecord
        weak var token: PromoSurfaceBlockerToken?
    }

    private let selectionSink: NewTabPagePromoExposureSelectionSinking
    private let mode: PromoCoordinationMode
    private var routeCandidateRendererID: UUID?
    private var activeBlockers = [ActiveBlocker]()
    private var lastSelectedRendererIDSentToSink: UUID?

    init(selectionSink: NewTabPagePromoExposureSelectionSinking) {
        self.selectionSink = selectionSink
        mode = selectionSink.promoCoordinationMode
    }

    var snapshot: NewTabPagePromoExposureSnapshot {
        let selection = currentSelection
        return NewTabPagePromoExposureSnapshot(
            mode: mode,
            routeCandidateRendererID: routeCandidateRendererID,
            effectiveSelectedRendererID: selection.rendererID,
            selectionState: selection.state,
            activeBlockers: activeBlockers.map(\.record)
        )
    }

    /// Updates the renderer selected by the current route/content resolver. `nil` is fail-closed and never falls back to
    /// another registered renderer.
    func setRouteCandidateRendererID(_ rendererID: UUID?) {
        guard mode == .coordinated,
              routeCandidateRendererID != rendererID else {
            return
        }

        routeCandidateRendererID = rendererID
        reconcileSelection()
    }

    /// Clears all state scoped to an exact renderer generation's stable renderer ID. Global blockers remain active.
    /// Clearing the route candidate in the same operation prevents cleanup from briefly reopening a stale renderer.
    func rendererDidDeregister(id rendererID: UUID) {
        guard mode == .coordinated else { return }

        let removedBlockers = activeBlockers.filter { blocker in
            blocker.record.scope == .renderer(rendererID)
        }
        for blocker in removedBlockers {
            Logger.modalPrompt.error(
                """
                [Promo Queue] - Clearing unreleased promo surface blocker \(blocker.record.id.uuidString, privacy: .public) \
                from \(blocker.record.source.description, privacy: .public), reason \
                \(blocker.record.reason.description, privacy: .public), while renderer \
                \(rendererID.uuidString, privacy: .public) deregisters.
                """
            )
            blocker.token?.invalidateAfterRendererDeregistration()
        }
        activeBlockers.removeAll { blocker in
            blocker.record.scope == .renderer(rendererID)
        }

        if routeCandidateRendererID == rendererID {
            routeCandidateRendererID = nil
        }
        reconcileSelection()
    }

    private var currentSelection: (
        rendererID: UUID?,
        state: NewTabPagePromoExposureSelectionState
    ) {
        guard let routeCandidateRendererID else {
            return (nil, .noRouteCandidate)
        }

        let matchingBlockerIDs = activeBlockers.compactMap { blocker in
            blocker.record.scope.includes(rendererID: routeCandidateRendererID) ? blocker.record.id : nil
        }
        guard matchingBlockerIDs.isEmpty else {
            return (
                nil,
                .blocked(
                    candidateRendererID: routeCandidateRendererID,
                    blockerIDs: matchingBlockerIDs
                )
            )
        }

        return (routeCandidateRendererID, .selected(rendererID: routeCandidateRendererID))
    }

    private func releaseBlocker(id: UUID) {
        guard let blockerIndex = activeBlockers.firstIndex(where: { $0.record.id == id }) else {
            return
        }

        activeBlockers.remove(at: blockerIndex)
        reconcileSelection()
    }

    private func reconcileSelection() {
        guard mode == .coordinated else {
            return
        }

        let selectedRendererID = currentSelection.rendererID
        guard selectedRendererID != lastSelectedRendererIDSentToSink else {
            return
        }

        lastSelectedRendererIDSentToSink = selectedRendererID
        selectionSink.setSelectedRemoteMessageRendererID(selectedRendererID)
    }
}

// MARK: - NewTabPagePromoExposureControlling

extension NewTabPagePromoExposureController: NewTabPagePromoExposureControlling {
    func blockPromoSurface(
        scope: PromoSurfaceBlockerScope,
        reason: PromoSurfaceBlockerReason,
        source: PromoSurfaceBlockerSource
    ) -> PromoSurfaceBlockerToken {
        guard mode == .coordinated else {
            // Preserve the call-site lifetime shape without introducing blocker state or leak
            // diagnostics into the feature-off path.
            let inertToken = PromoSurfaceBlockerToken(id: UUID(), releaseHandler: {})
            inertToken.release()
            return inertToken
        }

        let blockerID = UUID()
        let token = PromoSurfaceBlockerToken(id: blockerID) { [weak self] in
            self?.releaseBlocker(id: blockerID)
        }
        activeBlockers.append(
            ActiveBlocker(
                record: PromoSurfaceBlockerRecord(
                    id: blockerID,
                    scope: scope,
                    reason: reason,
                    source: source
                ),
                token: token
            )
        )
        reconcileSelection()
        return token
    }
}
