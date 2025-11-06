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
    /// Returns a view controller if the prompt is eligible to show to the user. Nil, otherwise.
    func makePresentDefaultModalPrompt() -> UIViewController?
}

@MainActor
final class DefaultBrowserModalPresenter: NSObject, DefaultBrowserPromptPresenting {
    private let coordinator: DefaultBrowserPromptCoordinating
    private let uiProvider: any DefaultBrowserPromptUIProviding

    init(coordinator: DefaultBrowserPromptCoordinating, uiProvider: any DefaultBrowserPromptUIProviding) {
        self.coordinator = coordinator
        self.uiProvider = uiProvider
    }

    func makePresentDefaultModalPrompt() -> UIViewController? {
        Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Attempting To Present Default Browser Prompt.")

        guard let prompt = coordinator.getPrompt() else { return nil }

        switch prompt {
        case .activeUserModal:
            return makeDefaultDefaultBrowserPromptForActiveUser()
        case .inactiveUserModal:
            return makeDefaultBrowserPromptForInactiveUser()
        }
    }

}

// MARK: - Private

private extension DefaultBrowserModalPresenter {

    func makeDefaultDefaultBrowserPromptForActiveUser() -> UIViewController {
        let hostingController = UIHostingController(rootView: AnyView(EmptyView()))

        let rootView = DefaultBrowserPromptActiveUserView(
            closeAction: { [weak hostingController, weak coordinator] in
                coordinator?.dismissAction(forPrompt: .activeUserModal, shouldDismissPromptPermanently: false)
                hostingController?.dismiss(animated: true)
            }, setAsDefaultAction: { [weak hostingController, weak coordinator] in
                coordinator?.setDefaultBrowserAction(forPrompt: .activeUserModal)
                hostingController?.dismiss(animated: true)
            }, doNotAskAgainAction: { [weak hostingController, weak coordinator] in
                coordinator?.dismissAction(forPrompt: .activeUserModal, shouldDismissPromptPermanently: true)
                hostingController?.dismiss(animated: true)
            }
        )

        hostingController.rootView = AnyView(rootView)
        hostingController.modalPresentationStyle = .pageSheet
        hostingController.modalTransitionStyle = .coverVertical
        configurePresentationStyle(hostingController: hostingController)

        return hostingController
    }

    func makeDefaultBrowserPromptForInactiveUser() -> UIViewController {
        let hostingController = PortraitHostingController(rootView: AnyView(EmptyView()))

        let rootView = DefaultBrowserPromptInactiveUserView(
            background: AnyView(uiProvider.makeBackground()),
            browserComparisonChart: AnyView(uiProvider.makeBrowserComparisonChart()),
            closeAction: { [weak hostingController, weak coordinator] in
                coordinator?.dismissAction(forPrompt: .inactiveUserModal, shouldDismissPromptPermanently: false)
                hostingController?.dismiss(animated: true)
            },
            setAsDefaultAction: { [weak hostingController, weak coordinator] in
                coordinator?.setDefaultBrowserAction(forPrompt: .inactiveUserModal)
                hostingController?.dismiss(animated: false)
            }
        )

        hostingController.rootView = AnyView(rootView)
        hostingController.modalPresentationStyle = .overFullScreen

        return hostingController
    }

    func configurePresentationStyle(hostingController: UIHostingController<AnyView>) {
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
