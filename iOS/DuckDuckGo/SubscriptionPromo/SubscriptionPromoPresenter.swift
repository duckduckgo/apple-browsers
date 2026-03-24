//
//  SubscriptionPromoPresenter.swift
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

import DesignResourcesKit
import SwiftUI
import UIKit

/// Presenter for the subscription promo launch sheet.
///
/// Creates a page-sheet view controller wrapping `SubscriptionPromoLaunchView`.
protocol SubscriptionPromoPresenting: AnyObject {
    func makeSubscriptionPromoPrompt() -> UIViewController
}

final class SubscriptionPromoPresenter: NSObject, SubscriptionPromoPresenting {
    private let coordinator: SubscriptionPromoCoordinating

    init(coordinator: SubscriptionPromoCoordinating) {
        self.coordinator = coordinator
    }

    func makeSubscriptionPromoPrompt() -> UIViewController {
        let hostingController = UIHostingController(rootView: AnyView(EmptyView()))

        let rootView = SubscriptionPromoLaunchView(
            title: coordinator.promoTitle(),
            message: coordinator.promoMessage(),
            ctaText: coordinator.proceedButtonText(),
            closeAction: { [weak hostingController, weak coordinator] in
                coordinator?.handleDismissAction()
                hostingController?.dismiss(animated: true)
            },
            ctaAction: { [weak hostingController, weak coordinator] in
                coordinator?.handleCTAAction()
                hostingController?.dismiss(animated: true)
            }
        )

        hostingController.rootView = AnyView(rootView)
        hostingController.view.backgroundColor = UIColor(designSystemColor: .surface)
        hostingController.modalPresentationStyle = .pageSheet
        hostingController.modalTransitionStyle = .coverVertical

        configurePresentationStyle(hostingController: hostingController)
        hostingController.presentationController?.delegate = self

        return hostingController
    }
}

// MARK: - UIAdaptivePresentationControllerDelegate

extension SubscriptionPromoPresenter: UIAdaptivePresentationControllerDelegate {

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        coordinator.handleDismissAction()
    }
}

// MARK: - Private

private extension SubscriptionPromoPresenter {

    func configurePresentationStyle(hostingController: UIHostingController<AnyView>) {
        guard let presentationController = hostingController.sheetPresentationController else { return }

        if #available(iOS 16.0, *) {
            presentationController.detents = [
                .custom(resolver: customDetentsHeightFor)
            ]
        } else {
            presentationController.detents = [
                .medium()
            ]
        }

        presentationController.prefersGrabberVisible = false
        presentationController.preferredCornerRadius = 16
    }

    @available(iOS 16.0, *)
    func customDetentsHeightFor(context: UISheetPresentationControllerDetentResolutionContext) -> CGFloat? {
        470
    }
}
