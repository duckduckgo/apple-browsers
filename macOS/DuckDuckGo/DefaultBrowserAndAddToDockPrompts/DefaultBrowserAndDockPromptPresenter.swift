//
//  DefaultBrowserAndDockPresenter.swift
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

import SwiftUIExtensions

protocol DefaultBrowserAndDockPromptPresenting {
    func showPopover(below view: NSView)
    func getBanner(closeAction: @escaping (() -> Void)) -> BannerMessageViewController?
}

final class DefaultBrowserAndDockPromptPresenter: DefaultBrowserAndDockPromptPresenting {

    private let coordinator: DefaultBrowserAndDockPrompt

    init(coordinator: DefaultBrowserAndDockPrompt = DefaultBrowserAndDockPromptCoordinator()) {
        self.coordinator = coordinator
    }

    func showPopover(below view: NSView) {
        guard let content = coordinator.evaluatePromptEligibility else {
            return
        }

        var popover: NSPopover?
        let style = DefaultBrowserAndDockPromptPresentation.popover(content)
        let viewModel = PopoverMessageViewModel(
            title: style.title,
            message: style.message,
            image: style.icon,
            buttonText: style.primaryButtonTitle,
            buttonAction: { self.coordinator.onPromptConfirmation() },
            secondaryButtonText: style.secondaryButtonTitle,
            secondaryButtonAction: {
                popover?.close()
                self.coordinator.onPromptDismissed()
            },
            shouldShowCloseButton: false,
            shouldPresentMultiline: true,
            alignment: .vertical)

        let contentView = PopoverMessageView(viewModel: viewModel, onClick: nil, onClose: nil)
        let viewController = NSHostingController(rootView: contentView)
        popover = DefaultBrowserAndDockPromptPopover(viewController: viewController)
        popover?.show(positionedBelow: view)
        popover?.contentViewController?.view.makeMeFirstResponder()
    }

    func getBanner(closeAction: @escaping (() -> Void)) -> BannerMessageViewController? {
        guard let content = coordinator.evaluatePromptEligibility else {
            return nil
        }

        let style = DefaultBrowserAndDockPromptPresentation.banner(content)

        return BannerMessageViewController(
            message: style.message,
            image: style.icon,
            buttonText: style.primaryButtonTitle,
            buttonAction: { self.coordinator.onPromptConfirmation() },
            closeAction: {
                closeAction()
                self.coordinator.onPromptDismissed()
            })
    }
}
