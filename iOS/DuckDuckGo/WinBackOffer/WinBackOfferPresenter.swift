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
    /// Returns a view controller for the win-back offer prompt.
    func makeWinBackOfferPrompt() -> UIViewController
}

final class WinBackOfferPresenter: NSObject, WinBackOfferPresenting {
    private let coordinator: WinBackOfferCoordinating

    init(coordinator: WinBackOfferCoordinating) {
        self.coordinator = coordinator
    }

    func makeWinBackOfferPrompt() -> UIViewController {
        let hostingController = UIHostingController(rootView: AnyView(EmptyView()))

        let rootView = WinBackOfferLaunchView(
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
        hostingController.modalPresentationStyle = .pageSheet
        hostingController.modalTransitionStyle = .coverVertical

        configurePresentationStyle(hostingController: hostingController)

        return hostingController
    }
}

// MARK: - Private

private extension WinBackOfferPresenter {

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
