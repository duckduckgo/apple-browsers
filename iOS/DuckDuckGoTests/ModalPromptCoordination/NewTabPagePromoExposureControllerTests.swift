//
//  NewTabPagePromoExposureControllerTests.swift
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
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("New Tab Page Promo Exposure Controller")
struct NewTabPagePromoExposureControllerTests {
    private let source = PromoSurfaceBlockerSource("NewTabPagePromoExposureControllerTests")

    @available(iOS 16, *)
    @Test("Default state selects no renderer", .timeLimit(.minutes(1)))
    func defaultStateSelectsNoRenderer() {
        let sink = RecordingExposureSelectionSink()
        let sut = NewTabPagePromoExposureController(selectionSink: sink)

        #expect(sut.snapshot.mode == .coordinated)
        #expect(sut.snapshot.routeResolution == .noHost)
        #expect(sut.snapshot.routeCandidateRendererID == nil)
        #expect(sut.snapshot.effectiveSelectedRendererID == nil)
        #expect(sut.snapshot.selectionState == .noRouteCandidate)
        #expect(sut.snapshot.activeBlockers.isEmpty)
        #expect(sink.selectedRendererIDs.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Snapshot preserves exact fail-closed route reasoning", .timeLimit(.minutes(1)))
    func snapshotPreservesExactFailClosedRouteReasoning() {
        let sink = RecordingExposureSelectionSink()
        let sut = NewTabPagePromoExposureController(selectionSink: sink)

        sut.setRouteResolution(.unifiedInput(rendererID: nil))

        #expect(sut.snapshot.routeResolution == .unifiedInput(rendererID: nil))
        #expect(sut.snapshot.routeCandidateRendererID == nil)
        #expect(sut.snapshot.selectionState == .noRouteCandidate)
        #expect(sink.selectedRendererIDs.isEmpty)

        sut.setRouteResolution(.contradictory)

        #expect(sut.snapshot.routeResolution == .contradictory)
        #expect(sut.snapshot.routeCandidateRendererID == nil)
        #expect(sut.snapshot.selectionState == .noRouteCandidate)
        #expect(sink.selectedRendererIDs.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Repeated candidate output is deduplicated", .timeLimit(.minutes(1)))
    func repeatedCandidateOutputIsDeduplicated() {
        let sink = RecordingExposureSelectionSink()
        let sut = NewTabPagePromoExposureController(selectionSink: sink)
        let rendererID = UUID()

        sut.setRouteCandidateRendererID(rendererID)
        sut.setRouteCandidateRendererID(rendererID)
        sut.setRouteCandidateRendererID(nil)
        sut.setRouteCandidateRendererID(nil)

        #expect(sink.selectedRendererIDs.count == 2)
        #expect(sink.selectedRendererIDs[0] == rendererID)
        #expect(sink.selectedRendererIDs[1] == nil)
    }

    @available(iOS 16, *)
    @Test("Host resolver follows route precedence and never falls through active alternate content", .timeLimit(.minutes(1)))
    func hostResolverFollowsPrecedenceWithoutAlternateFallback() {
        let editingRendererID = UUID()
        let unifiedRendererID = UUID()
        let trayRendererID = UUID()
        let standardRendererID = UUID()

        var state = NewTabPagePromoHostState(
            isEditingStatePresented: true,
            editingStateRendererID: editingRendererID,
            doesUnifiedInputCover: true,
            unifiedInputRendererID: unifiedRendererID,
            doesSuggestionTrayCover: true,
            suggestionTrayRendererID: trayRendererID,
            isStandardNewTabPageInstalled: true,
            standardNewTabPageRendererID: standardRendererID
        )
        #expect(state.resolve() == .editingState(rendererID: editingRendererID))

        state.isEditingStatePresented = false
        state.editingStateRendererID = nil
        state.doesSuggestionTrayCover = false
        state.unifiedInputRendererID = nil
        #expect(state.resolve() == .unifiedInput(rendererID: nil))
        #expect(state.resolve().rendererID == nil)

        state.doesUnifiedInputCover = false
        state.doesSuggestionTrayCover = true
        state.suggestionTrayRendererID = nil
        #expect(state.resolve() == .suggestionTray(rendererID: nil))
        #expect(state.resolve().rendererID == nil)
    }

    @available(iOS 16, *)
    @Test("Host resolver fails closed for contradictory alternate hosts", .timeLimit(.minutes(1)))
    func hostResolverFailsClosedForContradictoryAlternates() {
        let state = NewTabPagePromoHostState(
            doesUnifiedInputCover: true,
            unifiedInputRendererID: UUID(),
            doesSuggestionTrayCover: true,
            suggestionTrayRendererID: UUID(),
            isStandardNewTabPageInstalled: true,
            standardNewTabPageRendererID: UUID()
        )

        #expect(state.resolve() == .contradictory)
        #expect(state.resolve().rendererID == nil)
    }

    @available(iOS 16, *)
    @Test("Standard renderer resolves only after physical installation", .timeLimit(.minutes(1)))
    func standardRendererRequiresPhysicalInstallation() {
        let rendererID = UUID()
        var state = NewTabPagePromoHostState(
            isStandardNewTabPageInstalled: false,
            standardNewTabPageRendererID: rendererID
        )

        #expect(state.resolve() == .noHost)

        state.isStandardNewTabPageInstalled = true
        #expect(state.resolve() == .standard(rendererID: rendererID))
    }

    @available(iOS 16, *)
    @Test("Delayed inactive-host invalidation resolves from fresh route state", .timeLimit(.minutes(1)))
    func delayedInactiveHostInvalidationUsesFreshRouteState() {
        let staleUnifiedRendererID = UUID()
        let standardRendererID = UUID()
        let state = NewTabPagePromoHostState(
            doesUnifiedInputCover: false,
            unifiedInputRendererID: staleUnifiedRendererID,
            isStandardNewTabPageInstalled: true,
            standardNewTabPageRendererID: standardRendererID
        )

        #expect(state.resolve() == .standard(rendererID: standardRendererID))
    }

    @available(iOS 16, *)
    @Test("A renderer blocker suppresses only its renderer", .timeLimit(.minutes(1)))
    func rendererBlockerSuppressesOnlyItsRenderer() {
        let sink = RecordingExposureSelectionSink()
        let sut = NewTabPagePromoExposureController(selectionSink: sink)
        let selectedRendererID = UUID()
        let otherRendererID = UUID()
        sut.setRouteCandidateRendererID(selectedRendererID)

        let unrelatedToken = sut.blockPromoSurface(
            scope: .renderer(otherRendererID),
            reason: .hostTransition,
            source: source
        )

        #expect(sut.snapshot.effectiveSelectedRendererID == selectedRendererID)
        #expect(sink.selectedRendererIDs.count == 1)

        let matchingToken = sut.blockPromoSurface(
            scope: .renderer(selectedRendererID),
            reason: .standardNTPVisibilityTransition,
            source: source
        )

        #expect(sut.snapshot.effectiveSelectedRendererID == nil)
        #expect(sink.selectedRendererIDs.count == 2)
        #expect(sink.selectedRendererIDs[1] == nil)

        matchingToken.release()
        unrelatedToken.release()

        #expect(sut.snapshot.effectiveSelectedRendererID == selectedRendererID)
        #expect(sink.selectedRendererIDs.count == 3)
        #expect(sink.selectedRendererIDs[2] == selectedRendererID)
    }

    @available(iOS 16, *)
    @Test("A global blocker suppresses every route candidate", .timeLimit(.minutes(1)))
    func globalBlockerSuppressesEveryRouteCandidate() {
        let sink = RecordingExposureSelectionSink()
        let sut = NewTabPagePromoExposureController(selectionSink: sink)
        let firstRendererID = UUID()
        let secondRendererID = UUID()
        sut.setRouteCandidateRendererID(firstRendererID)

        let token = sut.blockPromoSurface(
            scope: .allRenderers,
            reason: .onboardingOverlay,
            source: source
        )
        sut.setRouteCandidateRendererID(secondRendererID)

        #expect(sut.snapshot.routeCandidateRendererID == secondRendererID)
        #expect(sut.snapshot.effectiveSelectedRendererID == nil)
        #expect(sink.selectedRendererIDs.count == 2)
        #expect(sink.selectedRendererIDs[1] == nil)

        token.release()

        #expect(sut.snapshot.effectiveSelectedRendererID == secondRendererID)
        #expect(sink.selectedRendererIDs.count == 3)
        #expect(sink.selectedRendererIDs[2] == secondRendererID)
    }

    @available(iOS 16, *)
    @Test("Nested blockers require every applicable token to release", .timeLimit(.minutes(1)))
    func nestedBlockersRequireEveryApplicableRelease() {
        let sink = RecordingExposureSelectionSink()
        let sut = NewTabPagePromoExposureController(selectionSink: sink)
        let rendererID = UUID()
        sut.setRouteCandidateRendererID(rendererID)

        let firstToken = sut.blockPromoSurface(
            scope: .renderer(rendererID),
            reason: .hostTransition,
            source: source
        )
        let secondToken = sut.blockPromoSurface(
            scope: .allRenderers,
            reason: .daxOverlay,
            source: source
        )

        #expect(firstToken.id != secondToken.id)
        #expect(sut.snapshot.activeBlockers.count == 2)
        #expect(sink.selectedRendererIDs.count == 2)

        firstToken.release()
        firstToken.release()

        #expect(sut.snapshot.effectiveSelectedRendererID == nil)
        #expect(sut.snapshot.activeBlockers.count == 1)
        #expect(sink.selectedRendererIDs.count == 2)

        secondToken.release()

        #expect(sut.snapshot.effectiveSelectedRendererID == rendererID)
        #expect(sut.snapshot.activeBlockers.isEmpty)
        #expect(sink.selectedRendererIDs.count == 3)
    }

    @available(iOS 16, *)
    @Test("Dropping a token leaves a fail-closed diagnostic record", .timeLimit(.minutes(1)))
    func droppedTokenLeavesFailClosedDiagnosticRecord() {
        let sink = RecordingExposureSelectionSink()
        let sut = NewTabPagePromoExposureController(selectionSink: sink)
        let rendererID = UUID()
        sut.setRouteCandidateRendererID(rendererID)
        var blockerID: UUID?

        do {
            let token = sut.blockPromoSurface(
                scope: .renderer(rendererID),
                reason: .other("intentional-test-leak"),
                source: source
            )
            blockerID = token.id
        }

        #expect(sut.snapshot.effectiveSelectedRendererID == nil)
        #expect(sut.snapshot.activeBlockers.count == 1)
        #expect(sut.snapshot.activeBlockers.first?.id == blockerID)

        sut.rendererDidDeregister(id: rendererID)

        #expect(sut.snapshot.activeBlockers.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Renderer deregistration clears only exact scoped state without reopening it", .timeLimit(.minutes(1)))
    func rendererDeregistrationClearsOnlyExactScopedState() {
        let sink = RecordingExposureSelectionSink()
        let sut = NewTabPagePromoExposureController(selectionSink: sink)
        let rendererID = UUID()
        sut.setRouteCandidateRendererID(rendererID)
        let rendererToken = sut.blockPromoSurface(
            scope: .renderer(rendererID),
            reason: .standardNTPVisibilityTransition,
            source: source
        )
        let globalToken = sut.blockPromoSurface(
            scope: .allRenderers,
            reason: .onboardingOverlay,
            source: source
        )

        sut.rendererDidDeregister(id: rendererID)

        #expect(sut.snapshot.routeResolution == .noHost)
        #expect(sut.snapshot.routeCandidateRendererID == nil)
        #expect(sut.snapshot.effectiveSelectedRendererID == nil)
        #expect(sut.snapshot.activeBlockers.count == 1)
        #expect(sut.snapshot.activeBlockers[0].scope == .allRenderers)
        #expect(sink.selectedRendererIDs.count == 2)

        rendererToken.release()
        globalToken.release()

        #expect(sut.snapshot.activeBlockers.isEmpty)
        #expect(sink.selectedRendererIDs.count == 2)
    }

    @available(iOS 16, *)
    @Test("Alternate-host deregistration retains the fail-closed host reason", .timeLimit(.minutes(1)))
    func alternateHostDeregistrationRetainsHostReason() {
        let sink = RecordingExposureSelectionSink()
        let sut = NewTabPagePromoExposureController(selectionSink: sink)
        let rendererID = UUID()
        sut.setRouteResolution(.unifiedInput(rendererID: rendererID))

        sut.rendererDidDeregister(id: rendererID)

        #expect(sut.snapshot.routeResolution == .unifiedInput(rendererID: nil))
        #expect(sut.snapshot.routeCandidateRendererID == nil)
        #expect(sut.snapshot.selectionState == .noRouteCandidate)
        #expect(sink.selectedRendererIDs.count == 2)
        #expect(sink.selectedRendererIDs[0] == rendererID)
        #expect(sink.selectedRendererIDs[1] == nil)
    }

    @available(iOS 16, *)
    @Test("Snapshot retains composed blocker provenance and matching identities", .timeLimit(.minutes(1)))
    func snapshotRetainsComposedBlockerProvenance() {
        let sink = RecordingExposureSelectionSink()
        let sut = NewTabPagePromoExposureController(selectionSink: sink)
        let selectedRendererID = UUID()
        let otherRendererID = UUID()
        sut.setRouteCandidateRendererID(selectedRendererID)
        let selectedToken = sut.blockPromoSurface(
            scope: .renderer(selectedRendererID),
            reason: .standardNTPVisibilityTransition,
            source: PromoSurfaceBlockerSource("standard-ntp")
        )
        let unrelatedToken = sut.blockPromoSurface(
            scope: .renderer(otherRendererID),
            reason: .hostTransition,
            source: PromoSurfaceBlockerSource("suggestion-tray")
        )
        let globalToken = sut.blockPromoSurface(
            scope: .allRenderers,
            reason: .daxOverlay,
            source: PromoSurfaceBlockerSource("dax-overlay")
        )

        let snapshot = sut.snapshot
        #expect(snapshot.activeBlockers.map(\.id) == [selectedToken.id, unrelatedToken.id, globalToken.id])
        #expect(snapshot.activeBlockers.map(\.source.identifier) == ["standard-ntp", "suggestion-tray", "dax-overlay"])
        #expect(
            snapshot.selectionState == .blocked(
                candidateRendererID: selectedRendererID,
                blockerIDs: [selectedToken.id, globalToken.id]
            )
        )

        selectedToken.release()
        unrelatedToken.release()
        globalToken.release()
    }

    @available(iOS 16, *)
    @Test("Legacy mode retains no route, selection, or blocker state", .timeLimit(.minutes(1)))
    func legacyModeRetainsNoExposureState() {
        let sink = RecordingExposureSelectionSink(mode: .legacy)
        let sut = NewTabPagePromoExposureController(selectionSink: sink)
        let rendererID = UUID()

        sut.setRouteCandidateRendererID(rendererID)
        let token = sut.blockPromoSurface(
            scope: .allRenderers,
            reason: .daxOverlay,
            source: source
        )
        token.release()
        sut.rendererDidDeregister(id: rendererID)

        #expect(sut.snapshot.mode == .legacy)
        #expect(sut.snapshot.routeResolution == .noHost)
        #expect(sut.snapshot.routeCandidateRendererID == nil)
        #expect(sut.snapshot.effectiveSelectedRendererID == nil)
        #expect(sut.snapshot.selectionState == .noRouteCandidate)
        #expect(sut.snapshot.activeBlockers.isEmpty)
        #expect(sink.selectedRendererIDs.isEmpty)
    }
}

@MainActor
private final class RecordingExposureSelectionSink: NewTabPagePromoExposureSelectionSinking {
    let promoCoordinationMode: PromoCoordinationMode
    private(set) var selectedRendererIDs = [UUID?]()

    init(mode: PromoCoordinationMode = .coordinated) {
        promoCoordinationMode = mode
    }

    func setSelectedRemoteMessageRendererID(_ rendererID: UUID?) {
        selectedRendererIDs.append(rendererID)
    }
}
