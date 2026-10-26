//
//  SubscriptionCancellationFlowModel.swift
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

import Combine
import Foundation
import FoundationExtensions
import Networking
import Subscription

enum SubscriptionCancellationFlowEligibility {

    static func isEligible(subscription: DuckDuckGoSubscription?, isFeatureEnabled: @autoclosure () -> Bool, locale: Locale) -> Bool {
        guard let subscription,
              subscription.platform == .apple,
              subscription.status == .autoRenewable,
              locale.isEnglishUnitedStates else { return false }
        return isFeatureEnabled()
    }
}

extension SubscriptionOnboardingChecklistItem {

    init?(entitlement: SubscriptionEntitlement) {
        guard let item = Self.checklist(isPIRAvailable: true,
                                        entitlement: EntitlementStatus(enabledEntitlements: [entitlement])).first else { return nil }
        self = item
    }
}

@MainActor
final class SubscriptionCancellationFlowModel: ObservableObject {

    @Published var featureInfoItem: SubscriptionOnboardingChecklistItem?

    private let instrumentation: SubscriptionCancellationInstrumenting
    private let onRequestStoreCancellation: () -> Void
    private let onClose: () -> Void
    private var didRequestStoreCancellation = false
    private var navigationErrorCancellable: AnyCancellable?

    init(navigationErrors: AnyPublisher<Error?, Never>,
         instrumentation: SubscriptionCancellationInstrumenting = SubscriptionCancellationInstrumentation(),
         onRequestStoreCancellation: @escaping () -> Void,
         onClose: @escaping () -> Void) {
        self.instrumentation = instrumentation
        self.onRequestStoreCancellation = onRequestStoreCancellation
        self.onClose = onClose
        navigationErrorCancellable = navigationErrors
            .compactMap { $0 }
            .sink { [weak self] error in
                MainActor.assumeIsolated {
                    self?.handleLoadFailure(error)
                }
            }
    }

    func showFeatureInfo(for entitlement: SubscriptionEntitlement) {
        guard let item = SubscriptionOnboardingChecklistItem(entitlement: entitlement) else {
            instrumentation.featureInfoFailed()
            return
        }
        guard featureInfoItem == nil else { return }
        featureInfoItem = item
    }

    func requestStoreCancellation() {
        guard !didRequestStoreCancellation else { return }
        didRequestStoreCancellation = true
        onRequestStoreCancellation()
        onClose()
    }

    /// A load failure on any step of the flow, not only the first page, falls back to the store cancellation.
    private func handleLoadFailure(_ error: Error) {
        guard !didRequestStoreCancellation else { return }
        didRequestStoreCancellation = true
        instrumentation.flowLoadFailed(error)
        onRequestStoreCancellation()
    }
}

struct SubscriptionCancellationFlowPresentation: Identifiable {

    let id = UUID()
    let model: SubscriptionCancellationFlowModel
    let containerViewModel: SubscriptionContainerViewModel

    @MainActor
    init(containerViewModel: SubscriptionContainerViewModel,
         onRequestStoreCancellation: @escaping () -> Void,
         onClose: @escaping () -> Void) {
        let model = SubscriptionCancellationFlowModel(navigationErrors: containerViewModel.flow.webViewModel.$navigationError.eraseToAnyPublisher(),
                                                      onRequestStoreCancellation: onRequestStoreCancellation,
                                                      onClose: onClose)
        containerViewModel.subFeature.onShowFeatureInfo = { [weak model] entitlement in
            model?.showFeatureInfo(for: entitlement)
        }
        containerViewModel.subFeature.onRequestCancellation = { [weak model] in
            model?.requestStoreCancellation()
        }
        self.model = model
        self.containerViewModel = containerViewModel
    }
}
