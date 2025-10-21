//
//  WinBackOfferPresenter.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import UIKit
import SwiftUI
import Core

/// Presenter for the Win-back offer prompt.
/// 
/// Responsible for presenting the launch prompt.
protocol WinBackOfferPresenting: AnyObject {
    /// Presents the launch prompt if it should be shown.
    /// 
    /// Eligibility is decided by WinBackOfferVisibilityManager, via the coordinator.
    @MainActor
    func tryPresentWinBackOfferPrompt(from viewController: UIViewController)
}

final class WinBackOfferPresenter: NSObject, WinBackOfferPresenting {
    private let coordinator: WinBackOfferCoordinating

    init(coordinator: WinBackOfferCoordinating) {
        self.coordinator = coordinator
    }

    @MainActor
    func tryPresentWinBackOfferPrompt(from viewController: UIViewController) {
        Logger.subscription.debug("[Win-Back Offer] Attempting to present win-back offer prompt.")

        guard coordinator.shouldPresentLaunchPrompt() else {
            return
        }

        presentLaunchPrompt(from: viewController)
    }
}

// MARK: - Private

private extension WinBackOfferPresenter {

    @MainActor
    func presentLaunchPrompt(from viewController: UIViewController) {
        let rootView = WinBackOfferLaunchView(
            closeAction: { [weak viewController, weak coordinator] in
                coordinator?.handleDismissAction()
                viewController?.dismiss(animated: true)
            },
            ctaAction: { [weak viewController, weak coordinator] in
                coordinator?.handleCTAAction()
                viewController?.dismiss(animated: true)
            }
        )

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.modalPresentationStyle = .pageSheet
        hostingController.modalTransitionStyle = .coverVertical

        configurePresentationStyle(hostingController: hostingController)

        // Mark as presented after successful configuration
        coordinator.markLaunchPromptPresented()

        viewController.present(hostingController, animated: true)
    }

    func configurePresentationStyle(hostingController: UIHostingController<WinBackOfferLaunchView>) {
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
