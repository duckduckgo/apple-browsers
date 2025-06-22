//
//  SetDefaultBrowserModalPresenter.swift
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

@MainActor
public protocol SetDefaultBrowserModalPresenting: AnyObject {
    func presentSetDefaultModal(from viewController: UIViewController)
}

@MainActor
public final class SetDefaultBrowserModalPresenter: SetDefaultBrowserModalPresenting {

    public init() {}

    public func presentSetDefaultModal(from viewController: UIViewController) {
        let rootView = SetDefaultBrowserModalView(
            closeAction: { [weak viewController] in

                viewController?.dismiss(animated: true)
            }, setAsDefaultAction: { [weak viewController] in

                viewController?.dismiss(animated: true)
            }, doNotAskAgainAction: { [weak viewController] in
                // Persist value
                viewController?.dismiss(animated: true)
            }
        )
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.modalPresentationStyle = .pageSheet
        hostingController.modalTransitionStyle = .coverVertical
        configurePresentationStyle(hostingController: hostingController, presentingController: viewController)
        viewController.present(hostingController, animated: true)
    }

}

// MARK: - Private

private extension SetDefaultBrowserModalPresenter {

    private func configurePresentationStyle(hostingController: UIHostingController<SetDefaultBrowserModalView>, presentingController: UIViewController) {
        guard let presentationController = hostingController.presentationController as? UISheetPresentationController else { return }

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
    private func customDetentsHeightFor(context: UISheetPresentationControllerDetentResolutionContext) -> CGFloat? {
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
