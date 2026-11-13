//
//  DefaultBrowserWinBackPromoDelegate.swift
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

import AppKit
import Combine
import Foundation
import PixelKit

final class DefaultBrowserWinBackPromoDelegate: InternalPromoDelegate {

    typealias ModalFactory = @MainActor (DefaultBrowserAndDockPromptType,
                                         _ onConfirm: @escaping () -> Void,
                                         _ onDismiss: @escaping () -> Void) -> DefaultBrowserAndDockPromptModalPresenting

    private let actionPerformer: DefaultBrowserAndDockActionPerforming
    private let churnState: UserChurnStateProviding
    private let promptStore: DefaultBrowserAndDockPromptStorage
    private let confirmationMonitor: DefaultBrowserConfirmationMonitoring
    private let pixelFiring: PixelFiring?
    private let isFeatureEnabled: () -> Bool
    private let uiHosting: () -> DefaultBrowserAndDockPromptUIHosting?
    private let modalFactory: ModalFactory
    private let dateProvider: () -> Date

    private let eligibility = CurrentValueSubject<Bool, Never>(false)
    private var showContinuation: CheckedContinuation<PromoResult, Never>?
    private var modal: DefaultBrowserAndDockPromptModalPresenting?

    var isEligible: Bool {
        eligibility.value
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        eligibility.removeDuplicates().eraseToAnyPublisher()
    }

    init(actionPerformer: DefaultBrowserAndDockActionPerforming,
         churnState: UserChurnStateProviding,
         promptStore: DefaultBrowserAndDockPromptStorage,
         confirmationMonitor: DefaultBrowserConfirmationMonitoring,
         pixelFiring: PixelFiring? = PixelKit.shared,
         isFeatureEnabled: @escaping () -> Bool,
         uiHosting: @escaping () -> DefaultBrowserAndDockPromptUIHosting?,
         modalFactory: @escaping ModalFactory,
         dateProvider: @escaping () -> Date) {
        self.actionPerformer = actionPerformer
        self.churnState = churnState
        self.promptStore = promptStore
        self.confirmationMonitor = confirmationMonitor
        self.pixelFiring = pixelFiring
        self.isFeatureEnabled = isFeatureEnabled
        self.uiHosting = uiHosting
        self.modalFactory = modalFactory
        self.dateProvider = dateProvider
        eligibility.value = computeEligibility()
    }

    func refreshEligibility() {
        churnState.checkForDefaultBrowserChange()
        eligibility.send(computeEligibility())
    }

    private func computeEligibility() -> Bool {
        guard isFeatureEnabled(),
              churnState.hasChurnedFromDefault,
              !promptStore.isBannerPermanentlyDismissed,
              !promptStore.hasSeenInactiveUserModal else {
            return false
        }
        return isSetAsDefaultPending
    }

    private var isSetAsDefaultPending: Bool {
        switch actionPerformer.pendingPromptType {
        case .setAsDefaultPrompt, .bothDefaultBrowserAndDockPrompt:
            return true
        case .addToDockPrompt, nil:
            return false
        }
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool = false) async -> PromoResult {
        guard let uiHosting = uiHosting(),
              !uiHosting.isInPopUpWindow,
              let type = actionPerformer.pendingPromptType,
              let anchor = uiHosting.provideModalAnchor() else {
            return .noChange
        }

        return await withCheckedContinuation { continuation in
            showContinuation = continuation
            let onConfirm: () -> Void = { [weak self] in self?.handleConfirm(type: type, isForceShow: force) }
            let onDismiss: () -> Void = { [weak self] in self?.handleDismiss(type: type, isForceShow: force) }
            let modal = modalFactory(type, onConfirm, onDismiss)
            self.modal = modal
            modal.present(over: anchor)
            pixelFiring?.fire(DefaultBrowserWinBackPixel.shown(type: type))
        }
    }

    @MainActor
    func hide() {
        if showContinuation != nil, !isSetAsDefaultPending {
            pixelFiring?.fire(DefaultBrowserWinBackPixel.defaultSetWithoutPromoAction)
        }
        if let modal {
            Task { await modal.dismiss() }
        }
        modal = nil
        resume(with: .noChange)
    }

    @MainActor
    private func handleConfirm(type: DefaultBrowserAndDockPromptType, isForceShow: Bool) {
        guard showContinuation != nil else { return }
        pixelFiring?.fire(DefaultBrowserWinBackPixel.confirmButtonClicked(type: type))
        markInactiveUserModalSeen(isForceShow: isForceShow)
        actionPerformer.performPendingActions()
        confirmationMonitor.start(clickDate: dateProvider())
        resume(with: .actioned())
    }

    @MainActor
    private func handleDismiss(type: DefaultBrowserAndDockPromptType, isForceShow: Bool) {
        guard showContinuation != nil else { return }
        pixelFiring?.fire(DefaultBrowserWinBackPixel.dismissed(type: type))
        markInactiveUserModalSeen(isForceShow: isForceShow)
        resume(with: .ignored())
    }

    // The win-back and the legacy inactive-user modal are mutually exclusive: once the win-back
    // is resolved, the inactive-user modal must never show. Force Show leaves no history.
    private func markInactiveUserModalSeen(isForceShow: Bool) {
        guard !isForceShow else { return }
        promptStore.inactiveUserModalShownDate = dateProvider().timeIntervalSince1970
    }

    @MainActor
    private func resume(with result: PromoResult) {
        showContinuation?.resume(returning: result)
        showContinuation = nil
    }
}
