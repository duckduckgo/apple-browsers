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

final class DefaultBrowserWinBackPromoDelegate: InternalPromoDelegate {

    typealias ModalFactory = @MainActor (DefaultBrowserAndDockPromptType,
                                         _ onConfirm: @escaping () -> Void,
                                         _ onDismiss: @escaping () -> Void) -> DefaultBrowserAndDockPromptModalPresenting

    private let actionPerformer: DefaultBrowserAndDockActionPerforming
    private let churnState: UserChurnStateProviding
    private let promptStore: DefaultBrowserAndDockPromptStorage
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
         isFeatureEnabled: @escaping () -> Bool,
         uiHosting: @escaping () -> DefaultBrowserAndDockPromptUIHosting?,
         modalFactory: @escaping ModalFactory,
         dateProvider: @escaping () -> Date) {
        self.actionPerformer = actionPerformer
        self.churnState = churnState
        self.promptStore = promptStore
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
              isEligible || force,
              let anchor = uiHosting.provideModalAnchor() else {
            return .noChange
        }

        return await withCheckedContinuation { continuation in
            showContinuation = continuation

            let modal = modalFactory(type, { [weak self] in
                guard let self else { return }
                recordModalSeen()
                actionPerformer.performPendingActions()
                resume(with: .actioned())
            }, { [weak self] in
                guard let self else { return }
                recordModalSeen()
                resume(with: .ignored())
            })
            self.modal = modal
            modal.present(over: anchor)
        }
    }

    @MainActor
    func hide() {
        let modal = self.modal
        self.modal = nil
        if let modal {
            Task { await modal.dismiss() }
        }
        resume(with: .noChange)
    }

    private func recordModalSeen() {
        promptStore.inactiveUserModalShownDate = dateProvider().timeIntervalSince1970
    }

    private func resume(with result: PromoResult) {
        showContinuation?.resume(returning: result)
        showContinuation = nil
    }
}
