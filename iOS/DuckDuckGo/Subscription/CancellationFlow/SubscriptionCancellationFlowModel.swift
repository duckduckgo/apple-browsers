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
import Networking
import Subscription

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
    private let onOpenStoreCancellation: (_ closingFlow: Bool) -> Void
    private var didOpenStoreCancellation = false
    private var navigationErrorCancellable: AnyCancellable?

    init(navigationErrors: AnyPublisher<Error?, Never>,
         instrumentation: SubscriptionCancellationInstrumenting = SubscriptionCancellationInstrumentation(),
         onOpenStoreCancellation: @escaping (_ closingFlow: Bool) -> Void) {
        self.instrumentation = instrumentation
        self.onOpenStoreCancellation = onOpenStoreCancellation
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
            instrumentation.featureInfoFailed(entitlement: entitlement)
            return
        }
        guard featureInfoItem == nil else { return }
        featureInfoItem = item
    }

    func requestStoreCancellation() {
        openStoreCancellation(closingFlow: true)
    }

    /// A load failure on any step of the flow, falls back to the store cancellation.
    private func handleLoadFailure(_ error: Error) {
        guard !didOpenStoreCancellation else { return }
        instrumentation.flowLoadFailed(error)
        // The flow shows the generic error alert, which closes the modal when dismissed.
        openStoreCancellation(closingFlow: false)
    }

    private func openStoreCancellation(closingFlow: Bool) {
        guard !didOpenStoreCancellation else { return }
        didOpenStoreCancellation = true
        onOpenStoreCancellation(closingFlow)
    }
}

struct SubscriptionCancellationFlowPresentation: Identifiable {

    let id = UUID()
    let model: SubscriptionCancellationFlowModel
    let containerViewModel: SubscriptionContainerViewModel

    @MainActor
    init(containerViewModel: SubscriptionContainerViewModel,
         onOpenStoreCancellation: @escaping (_ closingFlow: Bool) -> Void) {
        let model = SubscriptionCancellationFlowModel(navigationErrors: containerViewModel.flow.navigationErrorPublisher.eraseToAnyPublisher(),
                                                      onOpenStoreCancellation: onOpenStoreCancellation)
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
