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
    private let uiProvider: any DefaultBrowserPromptUIProviding

    init(coordinator: DefaultBrowserPromptCoordinating, uiProvider: any DefaultBrowserPromptUIProviding) {
        self.coordinator = coordinator
        self.uiProvider = uiProvider
    }

    public func tryPresentDefaultModalPrompt(from viewController: UIViewController) {
        Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Attempting To Present Default Browser Prompt.")

        guard let prompt = coordinator.getPrompt() else { return }

        switch prompt {
        case .activeUserModal:
            presentDefaultDefaultBrowserPromptForActiveUser(from: viewController)
        case .inactiveUserModal:
            presentDefaultBrowserPromptForInactiveUser(from: viewController)
        }
    }

}

// MARK: - Private

private extension DefaultBrowserModalPresenter {

    func presentDefaultDefaultBrowserPromptForActiveUser(from viewController: UIViewController) {
        let rootView = DefaultBrowserPromptActiveUserView(
            closeAction: { [weak viewController, weak coordinator] in
                coordinator?.dismissAction(forPrompt: .activeUserModal, shouldDismissPromptPermanently: false)
                viewController?.dismiss(animated: true)
            }, setAsDefaultAction: { [weak viewController, weak coordinator] in
                coordinator?.setDefaultBrowserAction(forPrompt: .activeUserModal)
                viewController?.dismiss(animated: true)
            }, doNotAskAgainAction: { [weak viewController, weak coordinator] in
                coordinator?.dismissAction(forPrompt: .activeUserModal, shouldDismissPromptPermanently: true)
                viewController?.dismiss(animated: true)
            }
        )
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.modalPresentationStyle = .pageSheet
        hostingController.modalTransitionStyle = .coverVertical
        configurePresentationStyle(hostingController: hostingController, presentingController: viewController)
        viewController.present(hostingController, animated: true)
    }

    func presentDefaultBrowserPromptForInactiveUser(from viewController: UIViewController) {
        // Present the full screen from the root controller or from the presented screen if any. (E.g. settings)
        let presentingViewController = viewController.presentedViewController ?? viewController

        let rootView = DefaultBrowserPromptInactiveUserView(
            background: AnyView(uiProvider.makeBackground()),
            browserComparisonChart: AnyView(uiProvider.makeBrowserComparisonChart()),
            closeAction: { [weak presentingViewController, weak coordinator] in
                coordinator?.dismissAction(forPrompt: .inactiveUserModal, shouldDismissPromptPermanently: false)
                presentingViewController?.dismiss(animated: true)
            },
            setAsDefaultAction: { [weak presentingViewController, weak coordinator] in
                coordinator?.setDefaultBrowserAction(forPrompt: .inactiveUserModal)
                presentingViewController?.dismiss(animated: false)
            }
        )
        let hostingController = PortraitHostingController(rootView: rootView)
        hostingController.modalPresentationStyle = .overFullScreen

        presentingViewController.present(hostingController, animated: true)
    }

    func configurePresentationStyle(hostingController: UIHostingController<DefaultBrowserPromptActiveUserView>, presentingController: UIViewController) {
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

final class PortraitHostingController<Content: View>: UIHostingController<Content> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return .portrait
        case .pad:
            return .all
        default:
            return .all
        }
    }
}
