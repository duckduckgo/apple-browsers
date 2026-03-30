//
//  DefaultBrowserAndDockPromoDelegate.swift
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

import Combine
import Foundation

/// PromoDelegate for default browser/dock prompts. One delegate per promo kind (popover, banner, inactive modal).
final class DefaultBrowserAndDockPromoDelegate: PromoDelegate {

    private let type: DefaultBrowserAndDockPromptPresentationType
    private let coordinator: DefaultBrowserAndDockPrompt
    private let presenter: DefaultBrowserAndDockPromptPresenting
    private let uiHosting: () -> DefaultBrowserAndDockPromptUIHosting?

    private var showContinuation: CheckedContinuation<PromoResult, Never>?
    private var cancellables = Set<AnyCancellable>()

    var isEligible: Bool {
        coordinator.eligiblePrompt.value == type
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        coordinator.eligiblePrompt
            .map { [weak self] in $0 == self?.type }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func refreshEligibility() {
        coordinator.evaluateEligibility()
    }

    init(type: DefaultBrowserAndDockPromptPresentationType,
         coordinator: DefaultBrowserAndDockPrompt,
         presenter: DefaultBrowserAndDockPromptPresenting,
         uiHosting: @escaping () -> DefaultBrowserAndDockPromptUIHosting?) {
        self.type = type
        self.coordinator = coordinator
        self.presenter = presenter
        self.uiHosting = uiHosting
    }

    convenience init(type: DefaultBrowserAndDockPromptPresentationType,
                     service: DefaultBrowserAndDockPromptService) {
        self.init(type: type,
                  coordinator: service.coordinator,
                  presenter: service.presenter,
                  uiHosting: service.uiHosting)
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool = false) async -> PromoResult {
        guard let uiHosting = uiHosting(),
              !uiHosting.isInPopUpWindow,
              isEligible || force else {
            return .noChange
        }

        return await withCheckedContinuation { continuation in
            cancellables.removeAll()
            showContinuation = continuation

            func resumeWithNoChange() {
                cancellables.removeAll()
                showContinuation?.resume(returning: .noChange)
                showContinuation = nil
            }

            coordinator.promptDismissedPublisher
                .filter { [weak self] (dismissedType, _) in
                    dismissedType == self?.type
                }
                .first()
                .sink { [weak self] _, result in
                    self?.showContinuation?.resume(returning: result)
                    self?.showContinuation = nil
                }
                .store(in: &cancellables)

            presenter.tryToShowPrompt(
                popoverAnchorProvider: { uiHosting.providePopoverAnchor() },
                bannerViewHandler: { uiHosting.addSetAsDefaultBanner($0) },
                inactiveUserModalWindowProvider: { uiHosting.provideModalAnchor() },
                expectedType: type,
                forceShow: force,
                onNoShow: { resumeWithNoChange() }
            )
        }
    }

    @MainActor
    func hide() {
        Task {
            await presenter.dismissPrompt(type)
        }
        showContinuation?.resume(returning: .noChange)
        showContinuation = nil
    }
}
