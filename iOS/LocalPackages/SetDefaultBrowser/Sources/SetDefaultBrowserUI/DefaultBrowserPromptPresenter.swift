//
//  DefaultBrowserPromptPresenter.swift
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
import MetricBuilder
import SetDefaultBrowserCore

@MainActor
public protocol DefaultBrowserPromptPresenting: AnyObject {
    func tryPresentDefaultModalPrompt(from viewController: UIViewController)
}

@MainActor
final class DefaultBrowserModalPresenter: NSObject, DefaultBrowserPromptPresenting {
    private let coordinator: DefaultBrowserPromptCoordinating

    init(coordinator: DefaultBrowserPromptCoordinating) {
        self.coordinator = coordinator
    }

    public func tryPresentDefaultModalPrompt(from viewController: UIViewController) {
        Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Attempting To Present Default Browser Prompt.")
        // When prompt for inactive user is implemented check prompt type and present different view accordingly.
        guard coordinator.getPrompt() != nil else { return }
        presentDefaultDefaultBrowserPrompt(from: viewController)
    }

}

// MARK: - Private

private extension DefaultBrowserModalPresenter {

    func presentDefaultDefaultBrowserPrompt(from viewController: UIViewController) {
        let rootView = DefaultBrowserPromptModalView(
            closeAction: { [weak viewController, weak coordinator] in
                coordinator?.dismissAction(shouldDismissPromptPermanently: false)
                viewController?.dismiss(animated: true)
            }, setAsDefaultAction: { [weak viewController, weak coordinator] in
                coordinator?.setDefaultBrowserAction()
                viewController?.dismiss(animated: true)
            }, doNotAskAgainAction: { [weak viewController, weak coordinator] in
                coordinator?.dismissAction(shouldDismissPromptPermanently: true)
                viewController?.dismiss(animated: true)
            }
        )
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.modalPresentationStyle = .pageSheet
        hostingController.modalTransitionStyle = .coverVertical
        configurePresentationStyle(hostingController: hostingController, presentingController: viewController)
        viewController.present(hostingController, animated: true)
    }

    func configurePresentationStyle(hostingController: UIHostingController<DefaultBrowserPromptModalView>, presentingController: UIViewController) {
        guard let presentationController = hostingController.sheetPresentationController else { return }

        if #available(iOS 16.0, *) {
            presentationController.detents = [
                .custom(resolver: customDetentsHeightFor)
            ]
        } else {
            presentationController.detents = [
                .large()
            ]
        }
    }

    @available(iOS 16.0, *)
    func customDetentsHeightFor(context: UISheetPresentationControllerDetentResolutionContext) -> CGFloat? {
        func isIPhonePortrait(traitCollection: UITraitCollection) -> Bool {
            traitCollection.verticalSizeClass == .regular && traitCollection.horizontalSizeClass == .compact
        }

        func isIPad(traitCollection: UITraitCollection) -> Bool {
            traitCollection.verticalSizeClass == .regular && traitCollection.horizontalSizeClass == .regular
        }

        let traitCollection = context.containerTraitCollection

        if isIPhonePortrait(traitCollection: traitCollection) {
            return 541
        } else if isIPad(traitCollection: traitCollection) {
            return 514
        } else {
            return nil
        }
    }

}
